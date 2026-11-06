-- C3: отказ исполнителя отменяет все ожидающие передачи задачи, а не только передачу исполнителя.
create or replace function public.decline_assignment(p_task_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; task_row public.tasks; old_assignee uuid;
begin
  actor := private.require_active_profile('executor');
  select * into task_row from public.tasks where id = p_task_id for update;
  if not found or task_row.assigned_to is distinct from actor.id or task_row.status <> 'new' then
    raise exception 'Assignment cannot be declined' using errcode = '42501', hint = 'assignment_forbidden';
  end if;
  old_assignee := task_row.assigned_to;
  update public.tasks set assigned_to = null where id = p_task_id;
  with cancelled as (
    update public.transfers set status = 'cancelled', responded_at = clock_timestamp()
      where task_id = p_task_id and status = 'pending'
      returning id
  )
  insert into public.task_history (task_id, event_type, actor_id, details)
    select p_task_id, 'transfer_cancelled', actor.id,
      jsonb_build_object('transfer_id', id, 'reason', 'assignment_declined') from cancelled;
  insert into public.task_history (task_id, event_type, actor_id, details)
    values (p_task_id, 'assignment_declined', actor.id, jsonb_build_object('declined_assignee_id', old_assignee));
end $$;
