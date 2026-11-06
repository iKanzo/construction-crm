-- Этап 3b. Триггеры: технические действия и ограничения, которые не выражаются через CHECK.
-- Все функции в схеме private. Сообщения об ошибках на английском, машинный код — в HINT
-- (frontend сопоставляет его с русским текстом). Триггеры BEFORE срабатывают по алфавиту имён,
-- поэтому имена имеют числовые префиксы.
--
-- Это второй рубеж защиты: основную проверку прав и бизнес-правил выполняют RPC (Этап 5).

-- --------------------------------------------------------- общие функции
create function private.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;

-- Запрещает менять перечисленные в аргументах триггера колонки.
create function private.forbid_column_update() returns trigger
language plpgsql set search_path = '' as $$
declare
  col text;
begin
  foreach col in array tg_argv loop
    if (to_jsonb(new) -> col) is distinct from (to_jsonb(old) -> col) then
      raise exception 'Column %.% is immutable', tg_table_name, col
        using errcode = '23001', hint = 'immutable_column';
    end if;
  end loop;
  return new;
end $$;

-- Физическое удаление и TRUNCATE запрещены (profiles, tasks, transfers).
create function private.prevent_delete() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Rows of % cannot be deleted', tg_table_name
    using errcode = '23001', hint = 'delete_forbidden';
end $$;

-- Таблицы только для добавления (task_history, comments).
create function private.prevent_modification() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Table % is append-only (% is not allowed)', tg_table_name, tg_op
    using errcode = '23001', hint = 'append_only';
end $$;

-- ------------------------------------------------------------- profiles
create trigger trg_10_immutable before update on public.profiles
  for each row execute function private.forbid_column_update('id', 'role', 'created_at');
create trigger trg_20_no_delete before delete on public.profiles
  for each row execute function private.prevent_delete();
create trigger trg_21_no_truncate before truncate on public.profiles
  for each statement execute function private.prevent_delete();

-- -------------------------------------------------------------- objects
create function private.objects_validate_refs() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles where id = new.created_by and role = 'manager') then
    raise exception 'Object creator must be a manager'
      using errcode = '23514', hint = 'invalid_object_creator';
  end if;
  return new;
end $$;

create trigger trg_10_immutable before update on public.objects
  for each row execute function private.forbid_column_update('created_by', 'created_at');
create trigger trg_30_refs before insert or update of created_by on public.objects
  for each row execute function private.objects_validate_refs();
create trigger trg_90_updated_at before update on public.objects
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------- tasks
create function private.tasks_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    -- ТЗ 6.4: единственный вход — «Создание → new».
    if new.status <> 'new' then
      raise exception 'A new task must have status new'
        using errcode = '23514', hint = 'invalid_initial_status';
    end if;
    return new;
  end if;

  -- ТЗ 6.4: допустимые переходы статусов. Других переходов нет.
  if new.status is distinct from old.status
     and (old.status, new.status) not in (
       ('new', 'in_progress'),
       ('in_progress', 'under_review'),
       ('under_review', 'accepted'),
       ('under_review', 'revision'),
       ('revision', 'in_progress'),
       ('new', 'closed')
     ) then
    raise exception 'Status transition % -> % is not allowed', old.status, new.status
      using errcode = '23514', hint = 'invalid_status_transition';
  end if;

  -- ТЗ 6.5: содержание правится только в new без исполнителя и в revision.
  if (new.title is distinct from old.title or new.description is distinct from old.description)
     and not ((old.status = 'new' and old.assigned_to is null) or old.status = 'revision') then
    raise exception 'Task content cannot be edited in status % (assigned: %)',
        old.status, old.assigned_to is not null
      using errcode = '23514', hint = 'content_edit_forbidden';
  end if;

  return new;
end $$;

-- Роли ссылающихся профилей (CHECK не умеет смотреть в другие таблицы).
-- Активность пользователей здесь не проверяется: она важна в момент назначения (RPC),
-- а исторические строки могут ссылаться на деактивированных сотрудников.
create function private.tasks_validate_refs() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles where id = new.created_by and role = 'manager') then
    raise exception 'Task creator must be a manager'
      using errcode = '23514', hint = 'invalid_task_creator';
  end if;
  if not exists (select 1 from public.profiles where id = new.responsible_manager_id and role = 'manager') then
    raise exception 'Responsible manager must be a manager'
      using errcode = '23514', hint = 'invalid_responsible_manager';
  end if;
  if new.assigned_to is not null
     and not exists (select 1 from public.profiles where id = new.assigned_to and role = 'executor') then
    raise exception 'Assignee must be an executor'
      using errcode = '23514', hint = 'invalid_assignee';
  end if;
  return new;
end $$;

create trigger trg_10_immutable before update on public.tasks
  for each row execute function private.forbid_column_update('object_id', 'created_by', 'created_at');
create trigger trg_20_guard before insert or update on public.tasks
  for each row execute function private.tasks_guard();
create trigger trg_30_refs before insert or update of created_by, responsible_manager_id, assigned_to on public.tasks
  for each row execute function private.tasks_validate_refs();
create trigger trg_90_updated_at before update on public.tasks
  for each row execute function private.set_updated_at();
create trigger trg_91_no_delete before delete on public.tasks
  for each row execute function private.prevent_delete();
create trigger trg_92_no_truncate before truncate on public.tasks
  for each statement execute function private.prevent_delete();

-- ------------------------------------------- task_history и comments
-- Имя участника — снимок на момент события. Заполняется сервером, значение клиента отбрасывается.
create function private.task_history_prepare() returns trigger
language plpgsql set search_path = '' as $$
begin
  select p.full_name into new.actor_name from public.profiles p where p.id = new.actor_id;
  if not found then
    raise exception 'Unknown actor %', new.actor_id
      using errcode = '23503', hint = 'unknown_actor';
  end if;
  new.created_at := clock_timestamp();
  return new;
end $$;

create function private.comments_prepare() returns trigger
language plpgsql set search_path = '' as $$
begin
  select p.full_name into new.author_name from public.profiles p where p.id = new.author_id;
  if not found then
    raise exception 'Unknown author %', new.author_id
      using errcode = '23503', hint = 'unknown_author';
  end if;
  new.created_at := clock_timestamp();
  return new;
end $$;

create trigger trg_10_prepare before insert on public.task_history
  for each row execute function private.task_history_prepare();
create trigger trg_20_append_only before update or delete on public.task_history
  for each row execute function private.prevent_modification();
create trigger trg_21_no_truncate before truncate on public.task_history
  for each statement execute function private.prevent_modification();

create trigger trg_10_prepare before insert on public.comments
  for each row execute function private.comments_prepare();
create trigger trg_20_append_only before update or delete on public.comments
  for each row execute function private.prevent_modification();
create trigger trg_21_no_truncate before truncate on public.comments
  for each statement execute function private.prevent_modification();

-- ------------------------------------------------------------ transfers
create function private.transfers_guard() returns trigger
language plpgsql set search_path = '' as $$
declare
  expected_role text;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'pending' then
      raise exception 'A new transfer must be pending'
        using errcode = '23514', hint = 'invalid_initial_transfer_status';
    end if;
    if not exists (select 1 from public.profiles where id = new.initiated_by and role = 'admin') then
      raise exception 'Transfer can be initiated only by an admin'
        using errcode = '23514', hint = 'invalid_transfer_initiator';
    end if;
    expected_role := case new.responsibility_type when 'executor' then 'executor' else 'manager' end;
    if (select count(*) from public.profiles
         where id in (new.from_user_id, new.to_user_id) and role = expected_role) <> 2 then
      raise exception 'Both sides of a % transfer must be %s', new.responsibility_type, expected_role
        using errcode = '23514', hint = 'invalid_transfer_party';
    end if;
    return new;
  end if;

  -- UPDATE: единственная допустимая правка — ответ на предложение, один раз.
  if old.status <> 'pending' then
    raise exception 'Transfer is already processed'
      using errcode = '23514', hint = 'transfer_already_processed';
  end if;
  if new.status not in ('accepted', 'declined', 'cancelled') then
    raise exception 'Transfer can only move from pending to accepted, declined or cancelled'
      using errcode = '23514', hint = 'invalid_transfer_transition';
  end if;
  return new;
end $$;

create trigger trg_10_immutable before update on public.transfers
  for each row execute function private.forbid_column_update(
    'task_id', 'responsibility_type', 'from_user_id', 'to_user_id', 'initiated_by', 'created_at');
create trigger trg_20_guard before insert or update on public.transfers
  for each row execute function private.transfers_guard();
create trigger trg_91_no_delete before delete on public.transfers
  for each row execute function private.prevent_delete();
create trigger trg_92_no_truncate before truncate on public.transfers
  for each statement execute function private.prevent_delete();
