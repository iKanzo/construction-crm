-- Регрессионные проверки критичных бизнес-операций RPC.
begin;
select plan(25);

insert into auth.users (id, email) values
  ('c0000000-0000-4000-8000-000000000001', 'rpc-manager@x.test'),
  ('c0000000-0000-4000-8000-000000000002', 'rpc-executor@x.test'),
  ('c0000000-0000-4000-8000-000000000003', 'rpc-executor2@x.test'),
  ('c0000000-0000-4000-8000-000000000004', 'rpc-admin@x.test'),
  ('c0000000-0000-4000-8000-000000000005', 'rpc-manager2@x.test');
insert into public.profiles (id, full_name, role) values
  ('c0000000-0000-4000-8000-000000000001', 'Менеджер', 'manager'),
  ('c0000000-0000-4000-8000-000000000002', 'Исполнитель', 'executor'),
  ('c0000000-0000-4000-8000-000000000003', 'Новый исполнитель', 'executor'),
  ('c0000000-0000-4000-8000-000000000004', 'Администратор', 'admin'),
  ('c0000000-0000-4000-8000-000000000005', 'Новый менеджер', 'manager');
insert into public.objects (id, title, address, customer_name, customer_phone, created_by) values
  ('c1000000-0000-4000-8000-000000000001', 'Объект', 'Адрес', 'Заказчик', '12345', 'c0000000-0000-4000-8000-000000000001');
insert into public.tasks (id, object_id, title, created_by, responsible_manager_id, assigned_to) values
  ('c2000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001', 'Без исполнителя', 'c0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', null),
  ('c2000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000001', 'С исполнителем', 'c0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000002');
insert into public.transfers (id, task_id, responsibility_type, from_user_id, to_user_id, initiated_by) values
  ('c3000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000002', 'executor', 'c0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000004');

create function pg_temp.act(p_uid uuid, p_sql text) returns text language plpgsql as $f$
declare result text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    result := 'OK';
  exception when others then
    result := 'ERR:' || sqlstate;
  end;
  reset role;
  return result;
end $f$;

select is(pg_temp.act('c0000000-0000-4000-8000-000000000002',
  $$select public.decline_assignment('c2000000-0000-4000-8000-000000000001')$$),
  'ERR:42501', 'Нельзя отказаться от неназначенной задачи');
select is((select count(*)::integer from public.task_history where task_id = 'c2000000-0000-4000-8000-000000000001'),
  0, 'Отклонённая операция не создаёт запись истории');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000003',
  $$select public.respond_to_transfer('c3000000-0000-4000-8000-000000000001', null)$$),
  'ERR:22023', 'NULL не считается отказом от передачи');
select is((select status from public.transfers where id = 'c3000000-0000-4000-8000-000000000001'),
  'pending', 'Предложение после неверного ответа остаётся активным');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000002',
  $$select public.transition_task('c2000000-0000-4000-8000-000000000002', 'in_progress', 'Приступаю к работе')$$),
  'OK', 'Исполнитель принимает назначенную задачу');
select is((select content from public.comments where task_id = 'c2000000-0000-4000-8000-000000000002'),
  'Приступаю к работе', 'Необязательный комментарий к переходу сохраняется');

select is(pg_temp.act('c0000000-0000-4000-8000-000000000001',
  $$select public.assign_executor('c2000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000003')$$),
  'OK', 'Менеджер назначает исполнителя');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000004',
  $$select public.create_transfer('c2000000-0000-4000-8000-000000000001', 'executor', 'c0000000-0000-4000-8000-000000000002')$$),
  'OK', 'Администратор предлагает передачу');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000004',
  $$select public.create_transfer('c2000000-0000-4000-8000-000000000001', 'manager', 'c0000000-0000-4000-8000-000000000005')$$),
  'OK', 'Одновременно предложена передача менеджера');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000003',
  $$select public.decline_assignment('c2000000-0000-4000-8000-000000000001')$$),
  'OK', 'Исполнитель отказывается от назначения');
select is((select count(*)::integer from public.transfers where task_id = 'c2000000-0000-4000-8000-000000000001' and status = 'cancelled' and responded_at is not null),
  2, 'Отказ автоматически отменяет обе передачи');
select is((select count(*)::integer from public.task_history h join public.transfers t
  on h.details->>'transfer_id' = t.id::text where t.task_id = 'c2000000-0000-4000-8000-000000000001'
  and h.event_type = 'transfer_cancelled' and h.actor_id = 'c0000000-0000-4000-8000-000000000003'
  and h.details->>'reason' = 'assignment_declined'), 2, 'Обе автоотмены отражены в аудите');

select is(pg_temp.act('c0000000-0000-4000-8000-000000000005',
  $$select public.respond_to_transfer((select id from public.transfers where task_id = 'c2000000-0000-4000-8000-000000000001' and responsibility_type = 'manager'), true)$$),
  'ERR:42501', 'Отменённую передачу нельзя принять');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000001',
  $$select public.transition_task('c2000000-0000-4000-8000-000000000002', 'accepted', null)$$),
  'ERR:42501', 'Нельзя принять задачу до проверки');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000002',
  $$select public.transition_task('c2000000-0000-4000-8000-000000000002', 'under_review', null)$$),
  'OK', 'Исполнитель отправляет на проверку');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000001',
  $$select public.transition_task('c2000000-0000-4000-8000-000000000002', 'revision', ' ')$$),
  'ERR:22023', 'Доработка требует непустой комментарий');
select is((select status from public.tasks where id = 'c2000000-0000-4000-8000-000000000002'),
  'under_review', 'Ошибка не меняет статус');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000001',
  $$select public.transition_task('c2000000-0000-4000-8000-000000000002', 'revision', 'Исправить')$$),
  'OK', 'Возврат на доработку с комментарием');
select is((select count(*)::integer from public.task_history h join public.comments c
  on c.id::text = h.details->>'comment_id' where h.task_id = 'c2000000-0000-4000-8000-000000000002'
  and h.new_status = 'revision' and c.content = 'Исправить' and not (h.details ? 'content')), 1,
  'История ссылается на комментарий без копирования текста');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000004',
  $$select public.deactivate_user('c0000000-0000-4000-8000-000000000002')$$),
  'ERR:23514', 'Нельзя деактивировать исполнителя с открытой задачей');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000004',
  $$select public.deactivate_user('c0000000-0000-4000-8000-000000000004')$$),
  'ERR:42501', 'Администраторов нельзя деактивировать');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000005',
  $$select public.add_comment('c2000000-0000-4000-8000-000000000002', 'Чужой чат')$$),
  'ERR:42501', 'Посторонний менеджер не пишет в чат');
select ok(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('create_object','update_object','delete_object',
    'create_task','assign_executor','decline_assignment','update_task','transition_task',
    'create_transfer','respond_to_transfer','cancel_transfer','deactivate_user','add_comment','get_task_object_title','get_object_task_summaries')
    and (not has_function_privilege('authenticated', p.oid, 'EXECUTE')
      or has_function_privilege('anon', p.oid, 'EXECUTE')
      or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0))
), 'Все ключевые RPC доступны authenticated, но не anon и PUBLIC');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000002',
  $$select public.deactivate_user('c0000000-0000-4000-8000-000000000005')$$),
  'ERR:42501', 'Исполнитель не может деактивировать пользователя');
select is(pg_temp.act('c0000000-0000-4000-8000-000000000001',
  $$select public.create_transfer('c2000000-0000-4000-8000-000000000002', 'executor', 'c0000000-0000-4000-8000-000000000003')$$),
  'ERR:42501', 'Менеджер не инициирует передачу');

select * from finish();
rollback;
