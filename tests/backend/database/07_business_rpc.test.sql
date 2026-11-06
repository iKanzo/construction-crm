-- Этап 5: проверка RPC через JWT claims и роль authenticated.
begin;
select plan(11);

create function pg_temp.rpc(p_uid uuid, p_sql text)
returns text language plpgsql as $$
declare result text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute 'set local role authenticated';
  begin
    execute p_sql into result;
  exception when others then
    result := 'ERR:' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return coalesce(result, '');
end $$;

select ok(has_function_privilege('authenticated', 'public.create_task(uuid,text,text,uuid)', 'EXECUTE'), 'authenticated может вызывать create_task');
select ok(not has_function_privilege('anon', 'public.create_task(uuid,text,text,uuid)', 'EXECUTE'), 'anon не может вызывать create_task');
select ok(not exists (
  select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where p.oid = 'public.create_task(uuid,text,text,uuid)'::regprocedure and a.grantee = 0
), 'PUBLIC не имеет EXECUTE на create_task');

select set_config('test.rpc_object', pg_temp.rpc('a0000000-0000-4000-8000-000000000011',
  $$select public.create_object('RPC test object', '', 'Адрес 1', 'Заказчик', '+70000000000')$$), true);
select matches(current_setting('test.rpc_object'), '^[0-9a-f-]{36}$', 'менеджер создаёт объект через RPC');
select is(pg_temp.rpc('a0000000-0000-4000-8000-000000000001',
  $$select public.create_object('Запрещено', '', 'Адрес', 'Заказчик', '+70000000000')$$), 'ERR:42501', 'администратор не создаёт объекты');

select set_config('test.rpc_task', pg_temp.rpc('a0000000-0000-4000-8000-000000000011',
  format('select public.create_task(%L::uuid, %L, %L, null)', current_setting('test.rpc_object'), 'RPC task', 'Описание')), true);
select matches(current_setting('test.rpc_task'), '^[0-9a-f-]{36}$', 'менеджер создаёт задачу без исполнителя');
select is(pg_temp.rpc('a0000000-0000-4000-8000-000000000021',
  format('select public.transition_task(%L::uuid, %L, null)', current_setting('test.rpc_task'), 'in_progress')),
  'ERR:42501', 'не назначенный исполнитель не начинает задачу');
select is(pg_temp.rpc('a0000000-0000-4000-8000-000000000011',
  format('select public.assign_executor(%L::uuid, %L::uuid)', current_setting('test.rpc_task'), 'a0000000-0000-4000-8000-000000000021')),
  '', 'ответственный менеджер назначает активного исполнителя');
select is(pg_temp.rpc('a0000000-0000-4000-8000-000000000021',
  format('select public.decline_assignment(%L::uuid)', current_setting('test.rpc_task'))), '', 'исполнитель отказывается от новой задачи');
select ok((select assigned_to is null from public.tasks where id = current_setting('test.rpc_task')::uuid), 'после отказа назначение очищено');
select is((select count(*)::text from public.task_history where task_id = current_setting('test.rpc_task')::uuid and event_type = 'assignment_declined'), '1', 'отказ сохранён в истории');

select * from finish();
rollback;
