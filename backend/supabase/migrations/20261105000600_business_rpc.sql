-- Этап 5. Узкие RPC бизнес-операций. Все изменения атомарны в транзакции вызова.
-- SECURITY DEFINER функции используют пустой search_path; пользователь и роль берутся только из auth.uid()/profiles.

create function private.require_active_profile(p_role text default null)
returns public.profiles
language plpgsql security definer set search_path = '' as $$
declare p public.profiles;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501', hint = 'authentication_required';
  end if;
  -- Serialise business writes before taking any profile/task row locks. This also
  -- protects deactivation against concurrent assignment and transfer creation.
  -- A single transaction-level lock avoids lock-order inversions between actors.
  perform pg_catalog.pg_advisory_xact_lock(170049, 1);
  select * into p from public.profiles where id = (select auth.uid()) and is_active for update;
  if not found then
    raise exception 'Active profile required' using errcode = '42501', hint = 'inactive_profile';
  end if;
  if p_role is not null and p.role <> p_role then
    raise exception 'Role % required', p_role using errcode = '42501', hint = 'role_forbidden';
  end if;
  return p;
end $$;

create function public.create_object(
  p_title text, p_description text, p_address text,
  p_customer_name text, p_customer_phone text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; result_id uuid;
begin
  actor := private.require_active_profile('manager');
  insert into public.objects (title, description, address, customer_name, customer_phone, created_by)
  values (p_title, coalesce(p_description, ''), p_address, p_customer_name, p_customer_phone, actor.id)
  returning id into result_id;
  return result_id;
end $$;

create function public.update_object(
  p_object_id uuid, p_title text, p_description text, p_address text,
  p_customer_name text, p_customer_phone text
) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; obj public.objects;
begin
  actor := private.require_active_profile('manager');
  select * into obj from public.objects where id = p_object_id for update;
  if not found or not private.can_view_object(p_object_id) then
    raise exception 'Object not found or inaccessible' using errcode = '42501', hint = 'object_forbidden';
  end if;
  update public.objects set title = p_title, description = coalesce(p_description, ''),
    address = p_address, customer_name = p_customer_name, customer_phone = p_customer_phone
  where id = p_object_id;
end $$;

create function public.delete_object(p_object_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; obj public.objects;
begin
  actor := private.require_active_profile('manager');
  select * into obj from public.objects where id = p_object_id for update;
  if not found or not private.can_view_object(p_object_id) then
    raise exception 'Object not found or inaccessible' using errcode = '42501', hint = 'object_forbidden';
  end if;
  if exists (select 1 from public.tasks where object_id = p_object_id) then
    raise exception 'Object has tasks' using errcode = '23503', hint = 'object_has_tasks';
  end if;
  delete from public.objects where id = p_object_id;
end $$;

create function public.create_task(
  p_object_id uuid, p_title text, p_description text, p_assigned_to uuid default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; obj public.objects; assignee public.profiles; result_id uuid;
begin
  actor := private.require_active_profile('manager');
  if p_assigned_to is not null then
    select * into assignee from public.profiles where id = p_assigned_to for update;
    if not found or assignee.role <> 'executor' or not assignee.is_active then
      raise exception 'Active executor required' using errcode = '22023', hint = 'invalid_assignee';
    end if;
  end if;
  select * into obj from public.objects where id = p_object_id for update;
  if not found or not private.can_view_object(p_object_id) then
    raise exception 'Object not found or inaccessible' using errcode = '42501', hint = 'object_forbidden';
  end if;
  insert into public.tasks (object_id, title, description, created_by, responsible_manager_id, assigned_to)
  values (p_object_id, p_title, coalesce(p_description, ''), actor.id, actor.id, p_assigned_to)
  returning id into result_id;
  insert into public.task_history (task_id, event_type, actor_id, new_status, details)
    values (result_id, 'task_created', actor.id, 'new', jsonb_build_object('title', p_title));
  if p_assigned_to is not null then
    insert into public.task_history (task_id, event_type, actor_id, details)
      values (result_id, 'executor_assigned', actor.id, jsonb_build_object('new_assignee_id', p_assigned_to));
  end if;
  return result_id;
end $$;

create function public.assign_executor(p_task_id uuid, p_executor_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; task_row public.tasks; target public.profiles;
begin
  actor := private.require_active_profile('manager');
  select * into target from public.profiles where id = p_executor_id for update;
  if not found or target.role <> 'executor' or not target.is_active then
    raise exception 'Active executor required' using errcode = '22023', hint = 'invalid_assignee';
  end if;
  select * into task_row from public.tasks where id = p_task_id for update;
  if not found or task_row.responsible_manager_id <> actor.id then
    raise exception 'Task is not managed by caller' using errcode = '42501', hint = 'task_forbidden';
  end if;
  if task_row.status <> 'new' or task_row.assigned_to is not null then
    raise exception 'Task is not awaiting assignment' using errcode = '23514', hint = 'assignment_not_allowed';
  end if;
  update public.tasks set assigned_to = target.id where id = p_task_id;
  insert into public.task_history (task_id, event_type, actor_id, details)
    values (p_task_id, 'executor_assigned', actor.id, jsonb_build_object('new_assignee_id', target.id));
end $$;

create function public.decline_assignment(p_task_id uuid) returns void
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
      where task_id = p_task_id and responsibility_type = 'executor' and status = 'pending'
      returning id
  )
  insert into public.task_history (task_id, event_type, actor_id, details)
    select p_task_id, 'transfer_cancelled', actor.id,
      jsonb_build_object('transfer_id', id, 'reason', 'assignment_declined') from cancelled;
  insert into public.task_history (task_id, event_type, actor_id, details)
    values (p_task_id, 'assignment_declined', actor.id, jsonb_build_object('declined_assignee_id', old_assignee));
end $$;

create function public.update_task(p_task_id uuid, p_title text, p_description text) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; task_row public.tasks;
begin
  actor := private.require_active_profile('manager');
  select * into task_row from public.tasks where id = p_task_id for update;
  if not found or task_row.responsible_manager_id <> actor.id then
    raise exception 'Task is not managed by caller' using errcode = '42501', hint = 'task_forbidden';
  end if;
  if not ((task_row.status = 'new' and task_row.assigned_to is null) or task_row.status = 'revision') then
    raise exception 'Task content cannot be edited now' using errcode = '23514', hint = 'content_edit_forbidden';
  end if;
  update public.tasks set title = p_title, description = coalesce(p_description, '') where id = p_task_id;
  insert into public.task_history (task_id, event_type, actor_id, details)
    values (p_task_id, 'task_updated', actor.id,
      jsonb_build_object('old_title', task_row.title, 'new_title', p_title,
        'old_description', task_row.description, 'new_description', coalesce(p_description, '')));
end $$;

create function public.transition_task(p_task_id uuid, p_new_status text, p_comment text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; task_row public.tasks; comment_id uuid; event_name text;
begin
  actor := private.require_active_profile();
  select * into task_row from public.tasks where id = p_task_id for update;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  if (p_new_status = 'in_progress' and actor.role = 'executor'
      and task_row.assigned_to = actor.id and task_row.status in ('new', 'revision')) then
    null;
  elsif p_new_status = 'under_review' and actor.role = 'executor'
      and task_row.assigned_to = actor.id and task_row.status = 'in_progress' then
    null;
  elsif p_new_status in ('accepted', 'revision') and actor.role = 'manager'
      and task_row.responsible_manager_id = actor.id and task_row.status = 'under_review' then
    null;
  elsif p_new_status = 'closed' and actor.role = 'manager'
      and task_row.responsible_manager_id = actor.id and task_row.status = 'new'
      and task_row.assigned_to is null then
    null;
  else
    raise exception 'Status transition is not permitted' using errcode = '42501', hint = 'transition_forbidden';
  end if;
  if p_new_status = 'revision' then
    if p_comment is null or char_length(btrim(p_comment)) = 0 then
      raise exception 'Revision requires a comment' using errcode = '22023', hint = 'comment_required';
    end if;
  end if;
  if p_comment is not null and char_length(btrim(p_comment)) > 0 then
    insert into public.comments (task_id, author_id, content)
      values (p_task_id, actor.id, p_comment) returning id into comment_id;
  end if;
  event_name := case when p_new_status = 'closed' then 'task_closed' else 'status_changed' end;
  update public.tasks set status = p_new_status where id = p_task_id;
  insert into public.task_history (task_id, event_type, actor_id, old_status, new_status, details)
    values (p_task_id, event_name, actor.id, task_row.status, p_new_status,
      case when comment_id is null then '{}'::jsonb else jsonb_build_object('comment_id', comment_id) end);
  if p_new_status in ('accepted', 'closed') then
    with cancelled as (
      update public.transfers set status = 'cancelled', responded_at = clock_timestamp()
        where task_id = p_task_id and status = 'pending' returning id
    )
    insert into public.task_history (task_id, event_type, actor_id, details)
      select p_task_id, 'transfer_cancelled', actor.id,
        jsonb_build_object('transfer_id', id, 'reason', 'task_' || p_new_status) from cancelled;
  end if;
end $$;

create function public.create_transfer(p_task_id uuid, p_responsibility_type text, p_to_user_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; task_row public.tasks; target public.profiles; from_id uuid; transfer_id uuid;
begin
  actor := private.require_active_profile('admin');
  if p_responsibility_type is null or p_responsibility_type not in ('executor', 'manager') then
    raise exception 'Unknown responsibility type' using errcode = '22023', hint = 'invalid_transfer_type';
  end if;
  select * into target from public.profiles where id = p_to_user_id for update;
  if not found or target.role <> (case p_responsibility_type when 'executor' then 'executor' else 'manager' end)
      or not target.is_active then
    raise exception 'Invalid or inactive transfer recipient' using errcode = '22023', hint = 'invalid_transfer_party';
  end if;
  select * into task_row from public.tasks where id = p_task_id for update;
  if not found or task_row.status in ('accepted', 'closed') then
    raise exception 'Task cannot be transferred' using errcode = '23514', hint = 'transfer_not_allowed';
  end if;
  if p_responsibility_type = 'executor' then
    from_id := task_row.assigned_to;
    if from_id is null then raise exception 'Task has no assigned executor' using errcode = '23514', hint = 'transfer_not_allowed'; end if;
  else
    from_id := task_row.responsible_manager_id;
  end if;
  if target.id = from_id then
    raise exception 'Recipient is already responsible' using errcode = '22023', hint = 'invalid_transfer_party';
  end if;
  insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by)
    values (p_task_id, p_responsibility_type, from_id, target.id, actor.id) returning id into transfer_id;
  insert into public.task_history (task_id, event_type, actor_id, details)
    values (p_task_id, 'transfer_initiated', actor.id,
      jsonb_build_object('transfer_id', transfer_id, 'responsibility_type', p_responsibility_type,
        'from_user_id', from_id, 'to_user_id', target.id));
  return transfer_id;
end $$;

create function public.respond_to_transfer(p_transfer_id uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; transfer_row public.transfers; task_row public.tasks; event_name text;
begin
  actor := private.require_active_profile();
  select tsk.* into task_row from public.tasks tsk
    join public.transfers tr on tr.task_id = tsk.id where tr.id = p_transfer_id;
  if not found then raise exception 'Transfer not found' using errcode = 'P0002'; end if;
  select * into task_row from public.tasks where id = task_row.id for update;
  select * into transfer_row from public.transfers where id = p_transfer_id for update;
  if transfer_row.status <> 'pending' or transfer_row.to_user_id <> actor.id then
    raise exception 'Transfer is not actionable by caller' using errcode = '42501', hint = 'transfer_forbidden';
  end if;
  if not actor.is_active then raise exception 'Active profile required' using errcode = '42501', hint = 'inactive_profile'; end if;
  if p_accept is null then
    raise exception 'Transfer response is required' using errcode = '22023', hint = 'invalid_transfer_response';
  end if;
  if task_row.status in ('accepted', 'closed') then
    raise exception 'Task cannot be transferred' using errcode = '23514', hint = 'transfer_not_allowed';
  end if;
  if (transfer_row.responsibility_type = 'manager'
      and task_row.responsible_manager_id is distinct from transfer_row.from_user_id)
    or (transfer_row.responsibility_type = 'executor'
      and task_row.assigned_to is distinct from transfer_row.from_user_id) then
    raise exception 'Transfer is no longer current' using errcode = '23514', hint = 'stale_transfer';
  end if;
  update public.transfers set status = case when p_accept then 'accepted' else 'declined' end,
    responded_at = clock_timestamp() where id = p_transfer_id;
  if p_accept then
    if transfer_row.responsibility_type = 'manager' then
      update public.tasks set responsible_manager_id = actor.id where id = task_row.id;
    else
      update public.tasks set assigned_to = actor.id where id = task_row.id;
    end if;
    event_name := 'transfer_accepted';
    insert into public.task_history (task_id, event_type, actor_id, details)
      values (task_row.id, event_name, actor.id, jsonb_build_object('transfer_id', p_transfer_id,
        'responsibility_type', transfer_row.responsibility_type, 'from_user_id', transfer_row.from_user_id,
        'to_user_id', actor.id));
    insert into public.task_history (task_id, event_type, actor_id, details)
      values (task_row.id, case when transfer_row.responsibility_type = 'manager' then 'manager_changed' else 'executor_changed' end,
        actor.id, jsonb_build_object('transfer_id', p_transfer_id, 'old_user_id', transfer_row.from_user_id, 'new_user_id', actor.id));
  else
    insert into public.task_history (task_id, event_type, actor_id, details)
      values (task_row.id, 'transfer_declined', actor.id,
        jsonb_build_object('transfer_id', p_transfer_id, 'responsibility_type', transfer_row.responsibility_type));
  end if;
end $$;

create function public.cancel_transfer(p_transfer_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; task_id_value uuid; transfer_row public.transfers;
begin
  actor := private.require_active_profile('admin');
  select task_id into task_id_value from public.transfers where id = p_transfer_id;
  if task_id_value is null then raise exception 'Transfer not found' using errcode = 'P0002'; end if;
  perform 1 from public.tasks where id = task_id_value for update;
  select * into transfer_row from public.transfers where id = p_transfer_id for update;
  if transfer_row.status <> 'pending' then raise exception 'Transfer already processed' using errcode = '23514', hint = 'transfer_already_processed'; end if;
  update public.transfers set status = 'cancelled', responded_at = clock_timestamp() where id = p_transfer_id;
  insert into public.task_history (task_id, event_type, actor_id, details)
    values (task_id_value, 'transfer_cancelled', actor.id, jsonb_build_object('transfer_id', p_transfer_id));
end $$;

create function public.deactivate_user(p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; target public.profiles;
begin
  actor := private.require_active_profile('admin');
  select * into target from public.profiles where id = p_user_id for update;
  if not found or not target.is_active then raise exception 'Active user not found' using errcode = '22023', hint = 'user_not_active'; end if;
  if target.role = 'admin' then raise exception 'Administrators cannot be deactivated' using errcode = '42501', hint = 'admin_deactivation_forbidden'; end if;
  if target.id = actor.id then raise exception 'Cannot deactivate self' using errcode = '42501', hint = 'self_deactivation_forbidden'; end if;
  if exists (select 1 from public.transfers where status = 'pending' and (from_user_id = target.id or to_user_id = target.id)) then
    raise exception 'User has pending transfers' using errcode = '23514', hint = 'pending_transfers';
  end if;
  if target.role = 'manager' and exists (
    select 1 from public.tasks where responsible_manager_id = target.id and status not in ('accepted', 'closed')) then
    raise exception 'Manager has open tasks' using errcode = '23514', hint = 'user_has_open_tasks';
  end if;
  if target.role = 'executor' and exists (
    select 1 from public.tasks where assigned_to = target.id and status not in ('accepted', 'closed')) then
    raise exception 'Executor has open tasks' using errcode = '23514', hint = 'user_has_open_tasks';
  end if;
  update public.profiles set is_active = false where id = target.id;
end $$;

create function public.add_comment(p_task_id uuid, p_content text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; task_row public.tasks; result_id uuid;
begin
  actor := private.require_active_profile();
  select * into task_row from public.tasks where id = p_task_id for update;
  if not found then raise exception 'Task not found' using errcode = 'P0002'; end if;
  if not ((actor.role = 'admin') or (actor.role = 'manager' and task_row.responsible_manager_id = actor.id)
      or (actor.role = 'executor' and task_row.assigned_to = actor.id)) then
    raise exception 'Chat access denied' using errcode = '42501', hint = 'chat_forbidden';
  end if;
  insert into public.comments (task_id, author_id, content) values (p_task_id, actor.id, p_content) returning id into result_id;
  return result_id;
end $$;

-- A transferred manager may see the task but not the object card (C1).
-- Return only the object title and only when the caller can see that task.
create function public.get_task_object_title(p_task_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select o.title from public.tasks t join public.objects o on o.id = t.object_id
  where t.id = p_task_id and private.can_view_task(t.id)
$$;
revoke all on function public.get_task_object_title(uuid) from public, anon;
grant execute on function public.get_task_object_title(uuid) to authenticated;

-- Ни PUBLIC, ни anon не могут вызывать RPC. Все SECURITY DEFINER имеют фиксированный search_path.
revoke all on function private.require_active_profile(text) from public, anon, authenticated;
revoke all on function
  public.create_object(text,text,text,text,text), public.update_object(uuid,text,text,text,text,text), public.delete_object(uuid),
  public.create_task(uuid,text,text,uuid), public.assign_executor(uuid,uuid), public.decline_assignment(uuid),
  public.update_task(uuid,text,text), public.transition_task(uuid,text,text),
  public.create_transfer(uuid,text,uuid), public.respond_to_transfer(uuid,boolean), public.cancel_transfer(uuid),
  public.deactivate_user(uuid), public.add_comment(uuid,text)
from public, anon;
grant execute on function
  public.create_object(text,text,text,text,text), public.update_object(uuid,text,text,text,text,text), public.delete_object(uuid),
  public.create_task(uuid,text,text,uuid), public.assign_executor(uuid,uuid), public.decline_assignment(uuid),
  public.update_task(uuid,text,text), public.transition_task(uuid,text,text),
  public.create_transfer(uuid,text,uuid), public.respond_to_transfer(uuid,boolean), public.cancel_transfer(uuid),
  public.deactivate_user(uuid), public.add_comment(uuid,text)
to authenticated;
