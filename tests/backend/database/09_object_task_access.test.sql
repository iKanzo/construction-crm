-- Access regression tests run by pgTAP on PostgreSQL, not by frontend mocks.
-- All fixtures and RPC mutations are rolled back at the end of this test file.
begin;
select plan(105);

insert into auth.users (id, email) values
  ('e0000000-0000-4000-8000-000000000001', 'access-admin@x.test'),
  ('e0000000-0000-4000-8000-000000000011', 'access-creator@x.test'),
  ('e0000000-0000-4000-8000-000000000012', 'access-manager@x.test'),
  ('e0000000-0000-4000-8000-000000000013', 'access-recipient@x.test'),
  ('e0000000-0000-4000-8000-000000000014', 'access-inactive@x.test'),
  ('e0000000-0000-4000-8000-000000000021', 'access-executor@x.test'),
  ('e0000000-0000-4000-8000-000000000022', 'access-other-executor@x.test'),
  ('e0000000-0000-4000-8000-000000000099', 'access-no-profile@x.test');
insert into public.profiles (id, full_name, role, is_active) values
  ('e0000000-0000-4000-8000-000000000001', 'Admin', 'admin', true),
  ('e0000000-0000-4000-8000-000000000011', 'Object creator', 'manager', true),
  ('e0000000-0000-4000-8000-000000000012', 'Current manager', 'manager', true),
  ('e0000000-0000-4000-8000-000000000013', 'Recipient', 'manager', true),
  ('e0000000-0000-4000-8000-000000000014', 'Inactive manager', 'manager', false),
  ('e0000000-0000-4000-8000-000000000021', 'Executor', 'executor', true),
  ('e0000000-0000-4000-8000-000000000022', 'Other executor', 'executor', true);
insert into public.objects (id, title, address, customer_name, customer_phone, created_by) values
  ('e1000000-0000-4000-8000-000000000001', 'Shared object', 'Address', 'Customer', '12345', 'e0000000-0000-4000-8000-000000000011'),
  ('e1000000-0000-4000-8000-000000000002', 'Inaccessible object', 'Address', 'Customer', '12345', 'e0000000-0000-4000-8000-000000000014'),
  ('e1000000-0000-4000-8000-000000000003', 'Empty object', 'Address', 'Customer', '12345', 'e0000000-0000-4000-8000-000000000011');
insert into public.tasks (id, object_id, title, description, created_by, responsible_manager_id, assigned_to) values
  ('e2000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'Transfer task', 'Private description', 'e0000000-0000-4000-8000-000000000011', 'e0000000-0000-4000-8000-000000000011', 'e0000000-0000-4000-8000-000000000021'),
  ('e2000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001', 'Creator retained task', 'Private description', 'e0000000-0000-4000-8000-000000000011', 'e0000000-0000-4000-8000-000000000011', null),
  ('e2000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000001', 'Other manager task', 'Other private description', 'e0000000-0000-4000-8000-000000000012', 'e0000000-0000-4000-8000-000000000012', null),
  ('e2000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000002', 'Inaccessible task', 'Secret', 'e0000000-0000-4000-8000-000000000014', 'e0000000-0000-4000-8000-000000000014', null);
insert into public.task_history (task_id, event_type, actor_id, details)
  select id, 'task_created', created_by, jsonb_build_object('private_note', description)
  from public.tasks where id::text like 'e2000000-%';
insert into public.comments (task_id, author_id, content)
  select id, responsible_manager_id, 'Private chat: ' || description
  from public.tasks where id::text like 'e2000000-%';

-- Queries really execute under authenticated/anon and exercise both ACL and RLS.
-- p_extra allows tests to spoof metadata, not to replace the authenticated sub.
create function pg_temp.act(p_uid uuid, p_sql text, p_role text default 'authenticated', p_extra jsonb default '{}'::jsonb)
returns text language plpgsql as $f$
declare result text;
begin
  perform set_config('request.jwt.claims',
    (p_extra || jsonb_build_object('sub', p_uid, 'role', p_role))::text, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into result;
  exception when others then
    result := 'ERR:' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return coalesce(result, '');
end $f$;

-- Catalog checks: exact return shape, fixed search_path, no public/anon EXECUTE.
select ok(has_function_privilege('authenticated', 'public.get_object_task_summaries(uuid)', 'EXECUTE'), 'authenticated can call the summary RPC');
select ok(not has_function_privilege('anon', 'public.get_object_task_summaries(uuid)', 'EXECUTE'), 'anon cannot execute the summary RPC');
select ok(not exists (
  select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = 'public.get_object_task_summaries(uuid)'::regprocedure and a.grantee = 0
), 'PUBLIC cannot execute the summary RPC');
select is((select proargnames from pg_proc where oid = 'public.get_object_task_summaries(uuid)'::regprocedure),
  array['p_object_id','id','object_id','title','assigned_to']::text[], 'RPC declares only the four allowed output fields');
select ok((select prosecdef and provolatile = 's' and 'search_path=""' = any(proconfig)
  from pg_proc where oid = 'public.get_object_task_summaries(uuid)'::regprocedure), 'summary RPC is STABLE, SECURITY DEFINER with an empty search_path');
select ok(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname in ('objects','tasks','task_history','comments')
    and not c.relrowsecurity
), 'RLS remains enabled on all affected tables');
select ok(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname in ('objects','tasks','task_history','comments')
    and has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE')
), 'authenticated still has no direct production write privileges');

-- Object access and full-task access are independent, including for creators.
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.objects where id = 'e1000000-0000-4000-8000-000000000001'$$), '1', 'creator sees an object containing tasks');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.objects where id = 'e1000000-0000-4000-8000-000000000001'$$), '1', 'current manager sees an object created by another manager');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.tasks where object_id = 'e1000000-0000-4000-8000-000000000001'$$), '1', 'manager cannot read other full task rows in a visible object');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.tasks where id = 'e2000000-0000-4000-8000-000000000003'$$), '0', 'object creator cannot read another manager task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select coalesce(string_agg(description || status, ''), '') from public.tasks where id = 'e2000000-0000-4000-8000-000000000003'$$), '', 'selecting protected columns directly returns no foreign row');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.objects o join public.tasks t on t.object_id = o.id where t.id = 'e2000000-0000-4000-8000-000000000003'$$), '0', 'joining a visible object cannot bypass tasks RLS');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.task_history where task_id = 'e2000000-0000-4000-8000-000000000003'$$), '0', 'creator cannot read history of a foreign task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.comments where task_id = 'e2000000-0000-4000-8000-000000000003'$$), '0', 'creator cannot read a foreign task chat');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select private.can_view_task('e2000000-0000-4000-8000-000000000003')::text$$), 'false', 'ID-based full-task helper checks the stored current manager');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select private.can_view_chat('e2000000-0000-4000-8000-000000000003')::text$$), 'false', 'chat helper does not grant access based on object creation');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.get_task_object_title('e2000000-0000-4000-8000-000000000003')$$), '', 'existing SECURITY DEFINER title RPC cannot be used for a foreign task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.add_comment('e2000000-0000-4000-8000-000000000003', 'Attempt')$$), 'ERR:42501', 'creator cannot write into a foreign task chat through RPC');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.update_task('e2000000-0000-4000-8000-000000000003', 'Attempt', '')$$), 'ERR:42501', 'creator cannot edit a foreign task through RPC');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.assign_executor('e2000000-0000-4000-8000-000000000003', 'e0000000-0000-4000-8000-000000000021')$$), 'ERR:42501', 'creator cannot assign a foreign task through RPC');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.transition_task('e2000000-0000-4000-8000-000000000003', 'closed', null)$$), 'ERR:42501', 'creator cannot close a foreign task through RPC');

-- RPC exposes the same brief task list to a creator and a current manager.
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), '3', 'creator gets brief summaries of all object tasks');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), '3', 'current manager gets brief summaries of all object tasks');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select to_jsonb(s)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001') s where s.id = 'e2000000-0000-4000-8000-000000000001'$$),
  jsonb_build_object('id', 'e2000000-0000-4000-8000-000000000001', 'object_id', 'e1000000-0000-4000-8000-000000000001', 'title', 'Transfer task', 'assigned_to', 'e0000000-0000-4000-8000-000000000021')::text,
  'SELECT * / JSON serialization yields exactly the allowed fields and values');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select assigned_to::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001') where id = 'e2000000-0000-4000-8000-000000000002'$$), '', 'unassigned summary preserves NULL');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select description from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42703', 'RPC has no description column to request');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select status from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42703', 'RPC has no status column to request');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001') s join public.tasks t on t.id = s.id$$), '1', 'joining summaries back to tasks does not bypass RLS');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000002')$$), 'ERR:42501', 'guessing an inaccessible object ID does not expose summaries');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000003')$$), '0', 'creator gets an empty list for an empty object');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.get_object_task_summaries(null)$$), 'ERR:42501', 'NULL object ID fails closed');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000099')$$), 'ERR:42501', 'unknown object ID fails closed');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000001', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), '3', 'active administrator can list summaries');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000001', $$select count(*)::text from public.tasks where object_id = 'e1000000-0000-4000-8000-000000000001'$$), '3', 'administrator retains full task access');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000021', $$select count(*)::text from public.tasks where object_id = 'e1000000-0000-4000-8000-000000000001'$$), '1', 'executor reads only the assigned task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000021', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42501', 'executor object access does not expose other task summaries');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000014', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000002')$$), 'ERR:42501', 'inactive creator cannot list summaries');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000099', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42501', 'user without a profile cannot list summaries');
select is(pg_temp.act(null, $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42501', 'authenticated role without auth.uid cannot list summaries');
select is(pg_temp.act(null, $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$, 'anon'), 'ERR:42501', 'anon cannot invoke summaries even with a known object ID');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.tasks where id = 'e2000000-0000-4000-8000-000000000001'$$, 'authenticated', '{"user_role":"admin","app_metadata":{"role":"admin"},"user_metadata":{"role":"admin"}}'), '0', 'forged admin metadata cannot widen full task access');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000002')$$, 'authenticated', '{"user_role":"admin","app_metadata":{"role":"admin"}}'), 'ERR:42501', 'forged admin metadata cannot widen summary access');

-- Explicit bypass attempts cannot disable RLS or turn read access into writes.
set local row_security = off;
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.tasks$$), 'ERR:42501', 'row_security=off does not bypass RLS for authenticated');
set local row_security = on;
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$update public.tasks set responsible_manager_id = 'e0000000-0000-4000-8000-000000000011' where id = 'e2000000-0000-4000-8000-000000000003'$$), 'ERR:42501', 'direct UPDATE cannot claim another manager task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$delete from public.tasks where id = 'e2000000-0000-4000-8000-000000000003'$$), 'ERR:42501', 'direct DELETE remains forbidden');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$update public.comments set content = 'Attempt' where task_id = 'e2000000-0000-4000-8000-000000000003'$$), 'ERR:42501', 'direct UPDATE of foreign comments remains forbidden');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$delete from public.task_history where task_id = 'e2000000-0000-4000-8000-000000000003'$$), 'ERR:42501', 'direct DELETE of foreign history remains forbidden');

-- Object-level access is insufficient for object mutations.
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.update_object('e1000000-0000-4000-8000-000000000001', 'Attempt', '', 'Address', 'Customer', '12345')$$), 'ERR:42501', 'non-creator cannot edit a visible object through SECURITY DEFINER RPC');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.delete_object('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42501', 'non-creator cannot delete a visible object through RPC');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.update_object('e1000000-0000-4000-8000-000000000001', 'Attempt', '', 'Address', 'Customer', '12345')$$), 'ERR:23514', 'creator cannot edit an object with unfinished tasks, including other manager tasks');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.delete_object('e1000000-0000-4000-8000-000000000001')$$), 'ERR:23503', 'creator cannot delete an object containing tasks');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.update_object('e1000000-0000-4000-8000-000000000003', 'Updated empty object', '', 'Address', 'Customer', '12345')$$), '', 'creator can edit an empty object');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000001', $$select public.update_object('e1000000-0000-4000-8000-000000000003', 'Attempt', '', 'Address', 'Customer', '12345')$$), 'ERR:42501', 'administrator cannot edit an object');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000021', $$select public.update_object('e1000000-0000-4000-8000-000000000003', 'Attempt', '', 'Address', 'Customer', '12345')$$), 'ERR:42501', 'executor cannot edit an object');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.delete_object('e1000000-0000-4000-8000-000000000003')$$), '', 'creator can delete an empty object');

-- Real transfer RPCs: a pending proposal confers no task/object access.
select set_config('test.access_transfer', pg_temp.act('e0000000-0000-4000-8000-000000000001',
  $$select public.create_transfer('e2000000-0000-4000-8000-000000000001', 'manager', 'e0000000-0000-4000-8000-000000000013')$$), true);
select matches(current_setting('test.access_transfer'), '^[0-9a-f-]{36}$', 'administrator creates a manager transfer');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select task_title_snapshot from public.transfers where id = current_setting('test.access_transfer')::uuid$$), 'Transfer task', 'pending recipient sees only the proposal snapshot');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.objects where id = 'e1000000-0000-4000-8000-000000000001'$$), '0', 'pending recipient cannot read the object');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.tasks where id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'pending recipient cannot read the full task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.task_history where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'pending recipient cannot read history');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.comments where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'pending recipient cannot read chat');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42501', 'pending recipient cannot request the summary list');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select public.respond_to_transfer(current_setting('test.access_transfer')::uuid, true)$$), '', 'recipient accepts through the real RPC');
select is((select status from public.tasks where id = 'e2000000-0000-4000-8000-000000000001'), 'new', 'manager transfer does not change task status');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select description from public.tasks where id = 'e2000000-0000-4000-8000-000000000001'$$), 'Private description', 'new manager gains the full transferred task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.task_history where task_id = 'e2000000-0000-4000-8000-000000000001' and event_type = 'task_created'$$), '1', 'new manager gains pre-transfer history');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select content from public.comments where task_id = 'e2000000-0000-4000-8000-000000000001'$$), 'Private chat: Private description', 'new manager gains pre-transfer chat');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.objects where id = 'e1000000-0000-4000-8000-000000000001'$$), '1', 'new manager gains the object');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), '3', 'new manager gains all brief object task summaries');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.tasks where object_id = 'e1000000-0000-4000-8000-000000000001'$$), '1', 'new manager cannot read full neighboring tasks');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.task_history where task_id = 'e2000000-0000-4000-8000-000000000002'$$), '0', 'new manager cannot read neighboring history');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.comments where task_id = 'e2000000-0000-4000-8000-000000000002'$$), '0', 'new manager cannot read neighboring chat');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.tasks where id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'old manager loses full task access despite creation and a retained neighboring task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.task_history where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'old manager loses all transferred task history');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.comments where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'old manager loses transferred task chat');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.add_comment('e2000000-0000-4000-8000-000000000001', 'Attempt after transfer')$$), 'ERR:42501', 'old manager cannot post after transfer');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000021', $$select count(*)::text from public.tasks where id = 'e2000000-0000-4000-8000-000000000001'$$), '1', 'manager transfer preserves the assigned executor access');

-- Transfer the creator's last task; creation alone must preserve object/summary
-- access without granting full access to any of the three remaining tasks.
select set_config('test.last_transfer', pg_temp.act('e0000000-0000-4000-8000-000000000001',
  $$select public.create_transfer('e2000000-0000-4000-8000-000000000002', 'manager', 'e0000000-0000-4000-8000-000000000012')$$), true);
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.respond_to_transfer(current_setting('test.last_transfer')::uuid, true)$$), '', 'another manager accepts the creator last task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.objects where id = 'e1000000-0000-4000-8000-000000000001'$$), '1', 'creator keeps object access without any responsibility');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), '3', 'creator keeps the complete brief task list without responsibility');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.tasks where object_id = 'e1000000-0000-4000-8000-000000000001'$$), '0', 'creation alone grants no full task rows');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.task_history where task_id in ('e2000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000002','e2000000-0000-4000-8000-000000000003')$$), '0', 'creation alone grants no task history');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select count(*)::text from public.comments where task_id in ('e2000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000002','e2000000-0000-4000-8000-000000000003')$$), '0', 'creation alone grants no task chats');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.update_object('e1000000-0000-4000-8000-000000000001', 'Attempt', '', 'Address', 'Customer', '12345')$$), 'ERR:23514', 'object edit checks unfinished tasks even when RLS hides every task from creator');

-- A non-creator losing their only task loses object/summary access as well.
select set_config('test.return_transfer', pg_temp.act('e0000000-0000-4000-8000-000000000001',
  $$select public.create_transfer('e2000000-0000-4000-8000-000000000001', 'manager', 'e0000000-0000-4000-8000-000000000012')$$), true);
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.respond_to_transfer(current_setting('test.return_transfer')::uuid, false)$$), '', 'recipient can decline a proposal');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.tasks where id = 'e2000000-0000-4000-8000-000000000001'$$), '1', 'declining preserves the current manager full access');
select set_config('test.return_transfer', pg_temp.act('e0000000-0000-4000-8000-000000000001',
  $$select public.create_transfer('e2000000-0000-4000-8000-000000000001', 'manager', 'e0000000-0000-4000-8000-000000000012')$$), true);
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.respond_to_transfer(current_setting('test.return_transfer')::uuid, true)$$), '', 'recipient accepts the next proposal');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.objects where id = 'e1000000-0000-4000-8000-000000000001'$$), '0', 'non-creator loses object access after transferring their only task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42501', 'past transfer participation is not a basis for summary access');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.task_history where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'past responsibility does not retain history access');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000013', $$select count(*)::text from public.comments where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'past responsibility does not retain chat access');

-- Terminal tasks retain the current participants' chat and history access.
select is(pg_temp.act('e0000000-0000-4000-8000-000000000021', $$select public.transition_task('e2000000-0000-4000-8000-000000000001', 'in_progress', null)$$), '', 'executor starts transferred task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000021', $$select public.transition_task('e2000000-0000-4000-8000-000000000001', 'under_review', null)$$), '', 'executor submits transferred task for review');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.transition_task('e2000000-0000-4000-8000-000000000001', 'accepted', null)$$), '', 'current manager accepts the task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.transition_task('e2000000-0000-4000-8000-000000000002', 'closed', null)$$), '', 'current manager closes an unassigned new task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.transition_task('e2000000-0000-4000-8000-000000000003', 'closed', null)$$), '', 'current manager closes the last unfinished task');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.comments where task_id in ('e2000000-0000-4000-8000-000000000001','e2000000-0000-4000-8000-000000000002')$$), '2', 'current manager retains chats after accepted and closed');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000021', $$select count(*)::text from public.comments where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '1', 'assigned executor retains chat after accepted');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000011', $$select public.update_object('e1000000-0000-4000-8000-000000000001', 'Updated finished object', '', 'Address', 'Customer', '12345')$$), '', 'creator can edit after all tasks finish despite no full task access');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select public.update_object('e1000000-0000-4000-8000-000000000001', 'Attempt', '', 'Address', 'Customer', '12345')$$), 'ERR:42501', 'current manager still cannot edit an object created by someone else');

-- Activity is checked on every call, independently of the existing Auth session.
update public.profiles set is_active = false where id = 'e0000000-0000-4000-8000-000000000012';
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.tasks where object_id = 'e1000000-0000-4000-8000-000000000001'$$), '0', 'inactive current manager cannot read terminal tasks');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.task_history where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'inactive current manager cannot read history');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.comments where task_id = 'e2000000-0000-4000-8000-000000000001'$$), '0', 'inactive current manager cannot read chat');
select is(pg_temp.act('e0000000-0000-4000-8000-000000000012', $$select count(*)::text from public.get_object_task_summaries('e1000000-0000-4000-8000-000000000001')$$), 'ERR:42501', 'inactive current manager cannot list summaries');

select * from finish();
rollback;
