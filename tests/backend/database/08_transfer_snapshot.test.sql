-- G15: снимок предложения и независимые основания доступа получателя.
begin;
select plan(26);

insert into auth.users (id, email) values
  ('d0000000-0000-4000-8000-000000000001', 'snapshot-admin@x.test'),
  ('d0000000-0000-4000-8000-000000000002', 'snapshot-manager@x.test'),
  ('d0000000-0000-4000-8000-000000000003', 'snapshot-recipient@x.test'),
  ('d0000000-0000-4000-8000-000000000004', 'snapshot-executor@x.test'),
  ('d0000000-0000-4000-8000-000000000005', 'snapshot-recipient-executor@x.test');
insert into public.profiles (id, full_name, role) values
  ('d0000000-0000-4000-8000-000000000001', 'Администратор', 'admin'),
  ('d0000000-0000-4000-8000-000000000002', 'Менеджер', 'manager'),
  ('d0000000-0000-4000-8000-000000000003', 'Получатель', 'manager'),
  ('d0000000-0000-4000-8000-000000000004', 'Исполнитель', 'executor'),
  ('d0000000-0000-4000-8000-000000000005', 'Получатель исполнитель', 'executor');
insert into public.objects (id, title, address, customer_name, customer_phone, created_by) values
  ('d1000000-0000-4000-8000-000000000001', 'Объект', 'Адрес', 'Заказчик', '12345', 'd0000000-0000-4000-8000-000000000002');
insert into public.tasks (id, object_id, title, created_by, responsible_manager_id, assigned_to) values
  ('d2000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001', 'Исходное название', 'd0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000002', null),
  ('d2000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000001', 'Другая задача', 'd0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000004');
insert into public.comments (id, task_id, author_id, content) values
  ('d3000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000002', 'Первый чат'),
  ('d3000000-0000-4000-8000-000000000002', 'd2000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000002', 'Другой чат');
insert into public.task_history (id, task_id, event_type, actor_id) values
  ('d4000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001', 'task_created', 'd0000000-0000-4000-8000-000000000002'),
  ('d4000000-0000-4000-8000-000000000002', 'd2000000-0000-4000-8000-000000000002', 'task_created', 'd0000000-0000-4000-8000-000000000002');

create function pg_temp.act(p_uid uuid, p_sql text, p_role text default 'authenticated')
returns text language plpgsql as $f$
declare result text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', p_role)::text, true);
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

select set_config('test.snapshot_transfer', pg_temp.act('d0000000-0000-4000-8000-000000000001',
  $$select public.create_transfer('d2000000-0000-4000-8000-000000000001', 'manager', 'd0000000-0000-4000-8000-000000000003')::text$$), true);
select matches(current_setting('test.snapshot_transfer'), '^[0-9a-f-]{36}$', 'RPC создаёт предложение менеджеру');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003',
  $$select task_title_snapshot from public.transfers where id = current_setting('test.snapshot_transfer')::uuid$$),
  'Исходное название', 'получатель видит снимок до принятия');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.tasks where id = 'd2000000-0000-4000-8000-000000000001'$$), '0', 'предложение не открывает задачу');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.objects where id = 'd1000000-0000-4000-8000-000000000001'$$), '0', 'предложение не открывает объект');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.task_history where task_id = 'd2000000-0000-4000-8000-000000000001'$$), '0', 'предложение не открывает историю');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.comments where task_id = 'd2000000-0000-4000-8000-000000000001'$$), '0', 'предложение не открывает чат');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000002',
  $$select public.update_task('d2000000-0000-4000-8000-000000000001', 'Новое название', '')$$), '', 'менеджер переименовывает задачу');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003',
  $$select task_title_snapshot from public.transfers where id = current_setting('test.snapshot_transfer')::uuid$$), 'Исходное название', 'снимок не меняется после переименования');
select is(pg_temp.act(null, $$update public.transfers set task_title_snapshot = 'Подмена' where id = current_setting('test.snapshot_transfer')::uuid$$, 'postgres'),
  'ERR:23001', 'снимок нельзя изменить даже привилегированным UPDATE');
select is((select task_title_snapshot from public.transfers where id = current_setting('test.snapshot_transfer')::uuid), 'Исходное название', 'отклонённое изменение не портит снимок');

-- Другая ответственность открывает объект и задачу, но не чужой чат.
update public.tasks set responsible_manager_id = 'd0000000-0000-4000-8000-000000000003' where id = 'd2000000-0000-4000-8000-000000000002';
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.objects where id = 'd1000000-0000-4000-8000-000000000001'$$), '1', 'независимая ответственность открывает объект');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.tasks where id = 'd2000000-0000-4000-8000-000000000001'$$), '1', 'независимая ответственность открывает задачу');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.comments where task_id = 'd2000000-0000-4000-8000-000000000001'$$), '0', 'чужой чат по-прежнему закрыт');
update public.tasks set responsible_manager_id = 'd0000000-0000-4000-8000-000000000002' where id = 'd2000000-0000-4000-8000-000000000002';
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003',
  $$select public.respond_to_transfer(current_setting('test.snapshot_transfer')::uuid, true)$$), '', 'получатель принимает передачу');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select title from public.tasks where id = 'd2000000-0000-4000-8000-000000000001'$$), 'Новое название', 'после принятия доступно актуальное название');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select task_title_snapshot from public.transfers where id = current_setting('test.snapshot_transfer')::uuid$$), 'Исходное название', 'после принятия сохраняется прежний снимок');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.tasks where id in ('d2000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000002')$$), '2', 'после принятия видны все задачи объекта');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000003', $$select count(*)::text from public.comments where task_id = 'd2000000-0000-4000-8000-000000000002'$$), '0', 'после принятия чужой чат закрыт');

select set_config('test.executor_transfer', pg_temp.act('d0000000-0000-4000-8000-000000000001',
  $$select public.create_transfer('d2000000-0000-4000-8000-000000000002', 'executor', 'd0000000-0000-4000-8000-000000000005')::text$$), true);
select is(pg_temp.act('d0000000-0000-4000-8000-000000000005', $$select task_title_snapshot from public.transfers where id = current_setting('test.executor_transfer')::uuid$$), 'Другая задача', 'получатель-исполнитель видит снимок');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000005', $$select count(*)::text from public.tasks where id = 'd2000000-0000-4000-8000-000000000002'$$), '0', 'предложение не открывает задачу исполнителю');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000005', $$select count(*)::text from public.objects where id = 'd1000000-0000-4000-8000-000000000001'$$), '0', 'предложение исполнителю не открывает объект');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000005', $$select count(*)::text from public.task_history where task_id = 'd2000000-0000-4000-8000-000000000002'$$), '0', 'предложение исполнителю не открывает историю');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000005', $$select count(*)::text from public.comments where task_id = 'd2000000-0000-4000-8000-000000000002'$$), '0', 'предложение исполнителю не открывает чат');
select is(pg_temp.act('d0000000-0000-4000-8000-000000000004', $$select count(*)::text from public.tasks where id = 'd2000000-0000-4000-8000-000000000002'$$), '1', 'независимое назначение прежнего исполнителя сохраняет доступ');

-- Даже прямой INSERT с подставленным снимком получает название из задачи.
insert into public.transfers (id, task_id, responsibility_type, from_user_id, to_user_id, initiated_by, task_title_snapshot)
values ('d5000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001', 'manager',
  'd0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000002',
  'd0000000-0000-4000-8000-000000000001', 'Подмена');
select is((select task_title_snapshot from public.transfers where id = 'd5000000-0000-4000-8000-000000000001'), 'Новое название', 'сервер перезаписывает переданный снимок актуальным названием');
select is(pg_temp.act(null, $$update public.transfers set task_title_snapshot = 'Подмена' where id = current_setting('test.snapshot_transfer')::uuid$$, 'postgres'), 'ERR:23001', 'снимок принятого предложения тоже неизменяем');

select * from finish();
rollback;
