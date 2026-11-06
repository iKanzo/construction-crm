-- Этап 3: ограничения данных (CHECK, внешние ключи, unique partial index).
begin;
select plan(33);

-- Фикстуры (независимы от seed): admin, два менеджера, два исполнителя, запасной auth-пользователь.
insert into auth.users (id, email) values
  ('f0000000-0000-4000-8000-000000000001', 't-admin@x.test'),
  ('f0000000-0000-4000-8000-000000000002', 't-mgr-a@x.test'),
  ('f0000000-0000-4000-8000-000000000003', 't-mgr-b@x.test'),
  ('f0000000-0000-4000-8000-000000000004', 't-ex-a@x.test'),
  ('f0000000-0000-4000-8000-000000000005', 't-ex-b@x.test'),
  ('f0000000-0000-4000-8000-000000000006', 't-spare@x.test');
insert into public.profiles (id, full_name, role) values
  ('f0000000-0000-4000-8000-000000000001', 'Админ Тест', 'admin'),
  ('f0000000-0000-4000-8000-000000000002', 'Менеджер А', 'manager'),
  ('f0000000-0000-4000-8000-000000000003', 'Менеджер Б', 'manager'),
  ('f0000000-0000-4000-8000-000000000004', 'Исполнитель А', 'executor'),
  ('f0000000-0000-4000-8000-000000000005', 'Исполнитель Б', 'executor');
insert into public.objects (id, title, address, customer_name, customer_phone, created_by) values
  ('f2000000-0000-4000-8000-000000000001', 'Объект', 'Адрес', 'Заказчик', '+79990000000',
   'f0000000-0000-4000-8000-000000000002'),
  ('f2000000-0000-4000-8000-000000000002', 'Пустой объект', 'Адрес', 'Заказчик', '+79990000000',
   'f0000000-0000-4000-8000-000000000002');
insert into public.tasks (id, object_id, title, created_by, responsible_manager_id, assigned_to) values
  ('f3000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001', 'T1 без исполнителя',
   'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', null),
  ('f3000000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000001', 'T2 с исполнителем',
   'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004'),
  ('f3000000-0000-4000-8000-000000000003', 'f2000000-0000-4000-8000-000000000001', 'T3 для передач',
   'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004');

-- ---- profiles
select throws_ilike($$insert into public.profiles (id, full_name, role)
  values ('f0000000-0000-4000-8000-000000000006', 'X', 'boss')$$,
  '%profiles_role_check%', 'profiles: неизвестная роль отклонена');
select throws_ilike($$insert into public.profiles (id, full_name, role)
  values ('f0000000-0000-4000-8000-000000000006', '   ', 'manager')$$,
  '%profiles_full_name_check%', 'profiles: пустое имя отклонено');
select throws_ok($$insert into public.profiles (id, full_name, role)
  values ('f0000000-0000-4000-8000-0000000000ff', 'X', 'manager')$$,
  '23503', null, 'profiles: профиль без пользователя auth отклонён');
select throws_ok($$delete from auth.users where id = 'f0000000-0000-4000-8000-000000000002'$$,
  '23503', null, 'auth.users с профилем удалить нельзя (RESTRICT)');

-- ---- objects
select throws_ilike($$insert into public.objects (title, address, customer_name, customer_phone, created_by)
  values ('  ', 'a', 'c', '+79990000000', 'f0000000-0000-4000-8000-000000000002')$$,
  '%objects_title_check%', 'objects: пустое название отклонено');
select throws_ilike($$insert into public.objects (title, address, customer_name, customer_phone, created_by)
  values ('t', 'a', '', '+79990000000', 'f0000000-0000-4000-8000-000000000002')$$,
  '%objects_customer_name_check%', 'objects: пустое имя заказчика отклонено');
select throws_ilike($$insert into public.objects (title, address, customer_name, customer_phone, created_by)
  values ('t', 'a', 'c', 'abc', 'f0000000-0000-4000-8000-000000000002')$$,
  '%objects_customer_phone_check%', 'objects: слишком короткий телефон отклонён');
select throws_ok($$insert into public.objects (title, address, customer_name, customer_phone, created_by)
  values ('t', 'a', 'c', '+79990000000', 'f0000000-0000-4000-8000-0000000000ff')$$,
  '23514', null, 'objects: несуществующий создатель отклонён');

-- ---- tasks
select throws_ok($$insert into public.tasks (object_id, title, created_by, responsible_manager_id)
  values ('f2000000-0000-4000-8000-0000000000ff', 't', 'f0000000-0000-4000-8000-000000000002',
          'f0000000-0000-4000-8000-000000000002')$$,
  '23503', null, 'tasks: несуществующий объект отклонён');
select throws_ilike($$insert into public.tasks (object_id, title, created_by, responsible_manager_id)
  values ('f2000000-0000-4000-8000-000000000001', '  ', 'f0000000-0000-4000-8000-000000000002',
          'f0000000-0000-4000-8000-000000000002')$$,
  '%tasks_title_check%', 'tasks: пустое название отклонено');
select throws_ok($$insert into public.tasks (object_id, title, status, created_by, responsible_manager_id)
  values ('f2000000-0000-4000-8000-000000000001', 't', 'bogus', 'f0000000-0000-4000-8000-000000000002',
          'f0000000-0000-4000-8000-000000000002')$$,
  '23514', null, 'tasks: неизвестный статус отклонён');
select throws_ilike($$update public.tasks set status = 'in_progress'
  where id = 'f3000000-0000-4000-8000-000000000001'$$,
  '%tasks_status_assignee_check%', 'tasks: in_progress без исполнителя невозможен');
select throws_ilike($$update public.tasks set status = 'closed'
  where id = 'f3000000-0000-4000-8000-000000000002'$$,
  '%tasks_status_assignee_check%', 'tasks: закрыть задачу с исполнителем нельзя');
select lives_ok($$update public.tasks set status = 'closed'
  where id = 'f3000000-0000-4000-8000-000000000001'$$,
  'tasks: задачу без исполнителя закрыть можно');
select lives_ok($$update public.tasks set status = 'in_progress'
  where id = 'f3000000-0000-4000-8000-000000000002'$$,
  'tasks: задачу с исполнителем можно взять в работу');
select throws_ok($$delete from public.objects where id = 'f2000000-0000-4000-8000-000000000001'$$,
  '23503', null, 'objects: объект с задачами удалить нельзя (RESTRICT)');
select lives_ok($$delete from public.objects where id = 'f2000000-0000-4000-8000-000000000002'$$,
  'objects: объект без задач удалить можно');

-- ---- transfers
select throws_ok($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by)
  values ('f3000000-0000-4000-8000-000000000003', 'executor', 'f0000000-0000-4000-8000-000000000004',
          'f0000000-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-000000000001')$$,
  '23514', null, 'transfers: передача самому себе отклонена');
select throws_ilike($$insert into public.transfers
  (task_id, responsibility_type, from_user_id, to_user_id, initiated_by, status, responded_at)
  values ('f3000000-0000-4000-8000-000000000003', 'executor', 'f0000000-0000-4000-8000-000000000004',
          'f0000000-0000-4000-8000-000000000005', 'f0000000-0000-4000-8000-000000000001', 'pending', now())$$,
  '%transfers_responded_check%', 'transfers: pending с responded_at отклонена');
select lives_ok($$insert into public.transfers (id, task_id, responsibility_type, from_user_id, to_user_id, initiated_by)
  values ('f4000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000003', 'executor',
          'f0000000-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-000000000005',
          'f0000000-0000-4000-8000-000000000001')$$,
  'transfers: активная передача исполнителя создаётся');
select throws_ok($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by)
  values ('f3000000-0000-4000-8000-000000000003', 'executor', 'f0000000-0000-4000-8000-000000000004',
          'f0000000-0000-4000-8000-000000000005', 'f0000000-0000-4000-8000-000000000001')$$,
  '23505', null, 'transfers: вторая активная передача исполнителя той же задачи отклонена');
select lives_ok($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by)
  values ('f3000000-0000-4000-8000-000000000003', 'manager', 'f0000000-0000-4000-8000-000000000002',
          'f0000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-000000000001')$$,
  'transfers: активная передача менеджера параллельно разрешена');
select lives_ok($$update public.transfers set status = 'declined', responded_at = now()
  where id = 'f4000000-0000-4000-8000-000000000001'$$,
  'transfers: передача закрывается отказом');
select lives_ok($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by)
  values ('f3000000-0000-4000-8000-000000000003', 'executor', 'f0000000-0000-4000-8000-000000000004',
          'f0000000-0000-4000-8000-000000000005', 'f0000000-0000-4000-8000-000000000001')$$,
  'transfers: после отказа можно создать новую активную передачу');
select throws_ok($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by, status)
  values ('f3000000-0000-4000-8000-000000000003', 'manager', 'f0000000-0000-4000-8000-000000000003',
          'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000001', 'foo')$$,
  '23514', null, 'transfers: неизвестный статус отклонён');

-- ---- task_history
select throws_ilike($$insert into public.task_history (task_id, event_type, actor_id)
  values ('f3000000-0000-4000-8000-000000000003', 'something', 'f0000000-0000-4000-8000-000000000002')$$,
  '%task_history_event_type_check%', 'history: неизвестный тип события отклонён');
select throws_ilike($$insert into public.task_history (task_id, event_type, actor_id)
  values ('f3000000-0000-4000-8000-000000000003', 'status_changed', 'f0000000-0000-4000-8000-000000000002')$$,
  '%task_history_status_changed_check%', 'history: status_changed требует old и new статус');
select throws_ilike($$insert into public.task_history (task_id, event_type, actor_id, old_status, new_status)
  values ('f3000000-0000-4000-8000-000000000003', 'task_closed', 'f0000000-0000-4000-8000-000000000002',
          'in_progress', 'closed')$$,
  '%task_history_task_closed_check%', 'history: task_closed только из new в closed');
select throws_ilike($$insert into public.task_history (task_id, event_type, actor_id, details)
  values ('f3000000-0000-4000-8000-000000000003', 'task_created', 'f0000000-0000-4000-8000-000000000002', '[]')$$,
  '%task_history_details_check%', 'history: details обязан быть JSON-объектом');
select lives_ok($$insert into public.task_history (task_id, event_type, actor_id, old_status, new_status)
  values ('f3000000-0000-4000-8000-000000000003', 'status_changed', 'f0000000-0000-4000-8000-000000000004',
          'new', 'in_progress')$$,
  'history: корректное событие добавляется');

-- ---- comments
select throws_ilike($$insert into public.comments (task_id, author_id, content)
  values ('f3000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-000000000002', '   ')$$,
  '%comments_content_check%', 'comments: пустой текст отклонён');
select throws_ilike($$insert into public.comments (task_id, author_id, content)
  values ('f3000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-000000000002', repeat('x', 5001))$$,
  '%comments_content_check%', 'comments: слишком длинный текст отклонён');
select lives_ok($$insert into public.comments (task_id, author_id, content)
  values ('f3000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-000000000002', 'Привет')$$,
  'comments: корректный комментарий добавляется');

select * from finish();
rollback;
