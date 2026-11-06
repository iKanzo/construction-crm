-- Этап 4a. Хелперы для RLS-политик (схема private, наружу через REST не публикуется).
--
-- Почему SECURITY DEFINER: политика выполняется с правами вызывающего, и подзапрос внутри неё
-- сам фильтруется RLS. Проверка «у объекта нет задач» или «менеджер отвечает за задачу объекта»
-- в таком виде видела бы только уже доступные строки и давала бы неверный ответ.
-- Хелперы читают таблицы от имени владельца, но решают только вопрос «можно ли ЭТОМУ
-- пользователю (auth.uid()) видеть ЭТУ строку» и ничего не возвращают, кроме boolean/роли.
--
-- Все функции: STABLE, фиксированный пустой search_path, явная проверка auth.uid(),
-- активности и роли. Деактивированный пользователь и пользователь без профиля не видят ничего.
-- EXECUTE выдаётся в следующей миграции только роли authenticated.

-- Роль текущего пользователя, если он активен; иначе NULL.
create function private.auth_role() returns text
language sql stable security definer set search_path = '' as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid()) and p.is_active
$$;

-- Решение C1 (вариант A): объект открывает менеджеру только задача,
-- которую он создал и за которую отвечает сейчас.
create function private.manager_has_object_access(p_object_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.auth_role() = 'manager'
    and exists (
      select 1
      from public.tasks t
      where t.object_id = p_object_id
        and t.created_by = (select auth.uid())
        and t.responsible_manager_id = (select auth.uid())
    )
$$;

-- Наборы идентификаторов для политик на СПИСКАХ. Функция без аргументов в `id IN (SELECT ...)`
-- вычисляется один раз на запрос, а не на каждую строку, поэтому неотфильтрованные списки
-- читаются в десятки и сотни раз быстрее, чем с функцией-предикатом на строку.

-- Объекты, доступ к которым менеджеру даёт его собственная задача (решение C1, вариант A).
create function private.manager_object_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select distinct t.object_id
  from public.tasks t
  where (select private.auth_role()) = 'manager'
    and t.created_by = (select auth.uid())
    and t.responsible_manager_id = (select auth.uid())
$$;

-- Все объекты, видимые текущему пользователю (админу — все).
create function private.visible_object_ids() returns setof uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  r   text := private.auth_role();
  uid uuid := (select auth.uid());
begin
  if r = 'admin' then
    return query select o.id from public.objects o;
  elsif r = 'manager' then
    return query
      select private.manager_object_ids()
      union
      -- созданный им объект, пока на нём нет ни одной задачи (любого автора)
      select o.id from public.objects o
      where o.created_by = uid
        and not exists (select 1 from public.tasks t where t.object_id = o.id);
  elsif r = 'executor' then
    -- любая назначенная ему задача объекта, в любом статусе (решение G13)
    return query select distinct t.object_id from public.tasks t where t.assigned_to = uid;
  end if;
  -- r IS NULL (деактивирован или нет профиля): ничего
  return;
end $$;

-- Доступ к карточке объекта по идентификатору (ТЗ 4.2, 5.3; решения C1, G13).
-- Политика на objects использует visible_object_ids(); эта функция нужна RPC (Этап 5)
-- и проверяется тестом на совпадение с политикой.
create function private.can_view_object(p_object_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  r   text := private.auth_role();
  uid uuid := (select auth.uid());
begin
  if r is null then
    return false;
  end if;

  if r = 'admin' then
    return true;
  end if;

  if r = 'manager' then
    return private.manager_has_object_access(p_object_id)
      -- созданный им объект, пока на нём нет ни одной задачи (любого автора)
      or exists (
        select 1 from public.objects o
        where o.id = p_object_id
          and o.created_by = uid
          and not exists (select 1 from public.tasks t where t.object_id = o.id)
      );
  end if;

  -- executor: любая назначенная ему задача объекта, в любом статусе
  return exists (
    select 1 from public.tasks t
    where t.object_id = p_object_id and t.assigned_to = uid
  );
end $$;

-- Доступ к строке задачи (и к её истории). Принимает значения колонок строки, чтобы
-- политика на tasks не делала повторного чтения той же строки.
create function private.can_view_task_row(
  p_object_id uuid, p_responsible_manager_id uuid, p_assigned_to uuid
) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  r   text := private.auth_role();
  uid uuid := (select auth.uid());
begin
  if r is null then
    return false;
  end if;
  if r = 'admin' then
    return true;
  end if;
  if r = 'manager' then
    -- свои задачи (в том числе полученные передачей) + все задачи доступного объекта
    return p_responsible_manager_id = uid or private.manager_has_object_access(p_object_id);
  end if;
  return p_assigned_to = uid;
end $$;

-- То же по идентификатору задачи (для политики на task_history).
create function private.can_view_task(p_task_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  t record;
begin
  select tk.object_id, tk.responsible_manager_id, tk.assigned_to into t
  from public.tasks tk where tk.id = p_task_id;
  if not found then
    return false;
  end if;
  return private.can_view_task_row(t.object_id, t.responsible_manager_id, t.assigned_to);
end $$;

-- Доступ к чату и комментариям (ТЗ раздел 9): админ, текущий ответственный менеджер,
-- текущий исполнитель. Менеджеры объекта, не отвечающие за задачу, доступа не имеют.
create function private.can_view_chat(p_task_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  r   text := private.auth_role();
  uid uuid := (select auth.uid());
begin
  if r is null then
    return false;
  end if;
  if r = 'admin' then
    return true;
  end if;
  return exists (
    select 1 from public.tasks t
    where t.id = p_task_id
      and ((r = 'manager' and t.responsible_manager_id = uid)
        or (r = 'executor' and t.assigned_to = uid))
  );
end $$;
