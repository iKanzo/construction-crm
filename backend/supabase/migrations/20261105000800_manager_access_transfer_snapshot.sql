-- Доступ менеджера по текущей ответственности и снимок названия для предложений.
create or replace function private.manager_has_object_access(p_object_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.auth_role() = 'manager'
    and exists (
      select 1 from public.tasks t
      where t.object_id = p_object_id
        and t.responsible_manager_id = (select auth.uid())
    )
$$;

create or replace function private.manager_object_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select distinct t.object_id
  from public.tasks t
  where (select private.auth_role()) = 'manager'
    and t.responsible_manager_id = (select auth.uid())
$$;

alter table public.transfers add column task_title_snapshot text;

-- Историческое название восстановить невозможно: для старых предложений сохраняем
-- текущее название на момент миграции, которое может отличаться от исходного.
-- Guard запрещает любые обновления обработанных предложений; временно отключаем
-- только его. ALTER TABLE удерживает блокировку таблицы до конца транзакции миграции.
alter table public.transfers disable trigger trg_20_guard;
update public.transfers tr set task_title_snapshot = t.title
from public.tasks t where t.id = tr.task_id;
alter table public.transfers enable trigger trg_20_guard;
alter table public.transfers alter column task_title_snapshot set not null;

-- Заполняем на сервере даже при переданном клиентом значении. create_transfer
-- блокирует строку задачи до вставки, поэтому снимок соответствует предложению.
create function private.transfers_snapshot_title() returns trigger
language plpgsql set search_path = '' as $$
begin
  select t.title into new.task_title_snapshot from public.tasks t where t.id = new.task_id;
  return new;
end $$;

create trigger trg_05_snapshot_title before insert on public.transfers
  for each row execute function private.transfers_snapshot_title();
create trigger trg_11_immutable_snapshot before update on public.transfers
  for each row execute function private.forbid_column_update('task_title_snapshot');
