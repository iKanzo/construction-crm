-- Separate object visibility from access to full task rows and task conversations.
-- Forward-only upgrade: migrations 001-008 and existing data remain unchanged.

create or replace function private.manager_has_object_access(p_object_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.auth_role() = 'manager'
    and exists (
      select 1 from public.objects o
      where o.id = p_object_id
        and (o.created_by = (select auth.uid()) or exists (
          select 1 from public.tasks t
          where t.object_id = o.id
            and t.responsible_manager_id = (select auth.uid())
        ))
    )
$$;

create or replace function private.manager_object_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select o.id from public.objects o
  where (select private.auth_role()) = 'manager'
    and o.created_by = (select auth.uid())
  union
  select t.object_id from public.tasks t
  where (select private.auth_role()) = 'manager'
    and t.responsible_manager_id = (select auth.uid())
$$;

create or replace function private.visible_object_ids() returns setof uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  r text := private.auth_role();
  uid uuid := (select auth.uid());
begin
  if r = 'admin' then
    return query select o.id from public.objects o;
  elsif r = 'manager' then
    return query select private.manager_object_ids();
  elsif r = 'executor' then
    return query select distinct t.object_id from public.tasks t where t.assigned_to = uid;
  end if;
end $$;

create or replace function private.can_view_object(p_object_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from private.visible_object_ids() as visible(id)
    where visible.id = p_object_id
  )
$$;

-- Keep the existing signature for dependent functions/policies. Object access is
-- deliberately not a basis for reading a task row, even for the object's creator.
create or replace function private.can_view_task_row(
  p_object_id uuid, p_responsible_manager_id uuid, p_assigned_to uuid
) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select private.auth_role()) = 'admin'
    or ((select private.auth_role()) = 'manager'
        and p_responsible_manager_id = (select auth.uid()))
    or ((select private.auth_role()) = 'executor'
        and p_assigned_to = (select auth.uid())),
    false
  )
$$;

-- can_view_task(uuid) reads the actual stored assignments and delegates to
-- can_view_task_row. get_task_object_title(uuid) also uses that strict check.
alter policy tasks_select on public.tasks using (
  (select private.auth_role()) = 'admin'
  or ((select private.auth_role()) = 'manager'
      and responsible_manager_id = (select auth.uid()))
  or ((select private.auth_role()) = 'executor'
      and assigned_to = (select auth.uid()))
);

alter policy task_history_select on public.task_history
  using (private.can_view_task(task_id));

-- Comments are the task chat. Its existing helper already checks only current
-- responsibility/assignment and active profiles, including for terminal tasks.
alter policy comments_select on public.comments
  using (private.can_view_chat(task_id));

-- A named four-column result prevents SELECT *, filters or JSON conversion of
-- this RPC from exposing task descriptions, statuses, authors or timestamps.
-- SECURITY DEFINER is necessary because tasks RLS hides other managers' rows.
-- Access is checked using the caller's auth.uid(), never caller-supplied identity.
create function public.get_object_task_summaries(p_object_id uuid)
returns table (id uuid, object_id uuid, title text, assigned_to uuid)
language plpgsql stable security definer set search_path = '' as $$
declare
  r text := private.auth_role();
begin
  if r is null or r not in ('admin', 'manager')
      or not private.can_view_object(p_object_id) then
    raise exception 'Object not found or inaccessible'
      using errcode = '42501', hint = 'object_forbidden';
  end if;
  return query
    select t.id, t.object_id, t.title, t.assigned_to
    from public.tasks t
    where t.object_id = p_object_id
    order by t.id;
end $$;

-- Object read access must never confer object write access. The old RPC used
-- can_view_object alone, which would let a non-creator manager edit the object.
create or replace function public.update_object(
  p_object_id uuid, p_title text, p_description text, p_address text,
  p_customer_name text, p_customer_phone text
) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; obj public.objects;
begin
  actor := private.require_active_profile('manager');
  select * into obj from public.objects where id = p_object_id for update;
  if not found or obj.created_by <> actor.id then
    raise exception 'Object not found or inaccessible'
      using errcode = '42501', hint = 'object_forbidden';
  end if;
  if exists (
    select 1 from public.tasks t
    where t.object_id = p_object_id and t.status not in ('accepted', 'closed')
  ) then
    raise exception 'Object has unfinished tasks'
      using errcode = '23514', hint = 'object_has_open_tasks';
  end if;
  update public.objects set title = p_title, description = coalesce(p_description, ''),
    address = p_address, customer_name = p_customer_name, customer_phone = p_customer_phone
  where id = p_object_id;
end $$;

create or replace function public.delete_object(p_object_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; obj public.objects;
begin
  actor := private.require_active_profile('manager');
  select * into obj from public.objects where id = p_object_id for update;
  if not found or obj.created_by <> actor.id then
    raise exception 'Object not found or inaccessible'
      using errcode = '42501', hint = 'object_forbidden';
  end if;
  if exists (select 1 from public.tasks where object_id = p_object_id) then
    raise exception 'Object has tasks' using errcode = '23503', hint = 'object_has_tasks';
  end if;
  delete from public.objects where id = p_object_id;
end $$;

-- CREATE OR REPLACE preserves existing ACLs: explicitly restate the boundary for
-- affected entrypoints as well as the new RPC. No table write privileges added.
revoke all on function
  private.manager_has_object_access(uuid), private.manager_object_ids(),
  private.visible_object_ids(), private.can_view_object(uuid),
  private.can_view_task_row(uuid,uuid,uuid), private.can_view_task(uuid),
  private.can_view_chat(uuid), public.get_task_object_title(uuid),
  public.get_object_task_summaries(uuid),
  public.update_object(uuid,text,text,text,text,text), public.delete_object(uuid)
from public, anon;

grant execute on function
  private.manager_has_object_access(uuid), private.manager_object_ids(),
  private.visible_object_ids(), private.can_view_object(uuid),
  private.can_view_task_row(uuid,uuid,uuid), private.can_view_task(uuid),
  private.can_view_chat(uuid), public.get_task_object_title(uuid),
  public.get_object_task_summaries(uuid),
  public.update_object(uuid,text,text,text,text,text), public.delete_object(uuid)
to authenticated;
