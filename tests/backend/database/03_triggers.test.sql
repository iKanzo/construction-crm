-- Этап 3: триггеры (неизменяемость, запрет удаления, append-only, снимки имён,
-- updated_at, переходы статусов, правила редактирования, проверки ролей, жизненный цикл передач).
begin;
select plan(84);

insert into auth.users (id, email) values
  ('f0000000-0000-4000-8000-000000000001', 't1@x.test'),
  ('f0000000-0000-4000-8000-000000000002', 't2@x.test'),
  ('f0000000-0000-4000-8000-000000000003', 't3@x.test'),
  ('f0000000-0000-4000-8000-000000000004', 't4@x.test'),
  ('f0000000-0000-4000-8000-000000000005', 't5@x.test');
insert into public.profiles (id, full_name, role) values
  ('f0000000-0000-4000-8000-000000000001', 'Админ Тест', 'admin'),
  ('f0000000-0000-4000-8000-000000000002', 'Менеджер А', 'manager'),
  ('f0000000-0000-4000-8000-000000000003', 'Менеджер Б', 'manager'),
  ('f0000000-0000-4000-8000-000000000004', 'Исполнитель А', 'executor'),
  ('f0000000-0000-4000-8000-000000000005', 'Исполнитель Б', 'executor');
insert into public.objects (id, title, address, customer_name, customer_phone, created_by) values
  ('f2000000-0000-4000-8000-000000000001', 'Объект 1', 'Адрес', 'Заказчик', '+79990000000', 'f0000000-0000-4000-8000-000000000002'),
  ('f2000000-0000-4000-8000-000000000002', 'Объект 2', 'Адрес', 'Заказчик', '+79990000000', 'f0000000-0000-4000-8000-000000000002');
-- 1: new без исполнителя; 2: new с исполнителем; 3: проходит весь цикл; 4: closed; 5: для запретов из new; 6: для передач
insert into public.tasks (id, object_id, title, created_by, responsible_manager_id, assigned_to) values
  ('f3000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001', 'T1', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', null),
  ('f3000000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000001', 'T2', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004'),
  ('f3000000-0000-4000-8000-000000000003', 'f2000000-0000-4000-8000-000000000001', 'T3', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004'),
  ('f3000000-0000-4000-8000-000000000004', 'f2000000-0000-4000-8000-000000000001', 'T4', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', null),
  ('f3000000-0000-4000-8000-000000000005', 'f2000000-0000-4000-8000-000000000001', 'T5', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004'),
  ('f3000000-0000-4000-8000-000000000006', 'f2000000-0000-4000-8000-000000000001', 'T6', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004');
update public.tasks set status = 'closed' where id = 'f3000000-0000-4000-8000-000000000004';
insert into public.comments (id, task_id, author_id, content) values
  ('f5000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000006', 'f0000000-0000-4000-8000-000000000002', 'c1');
insert into public.task_history (id, task_id, event_type, actor_id) values
  ('f6000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000006', 'task_created', 'f0000000-0000-4000-8000-000000000002');

-- ---- неизменяемость колонок
select throws_ilike($$update public.profiles set role = 'admin' where id = 'f0000000-0000-4000-8000-000000000002'$$, '%immutable%', 'profiles.role неизменна');
select throws_ilike($$update public.profiles set created_at = now() - interval '1 day' where id = 'f0000000-0000-4000-8000-000000000002'$$, '%immutable%', 'profiles.created_at неизменна');
select throws_ilike($$update public.objects set created_by = 'f0000000-0000-4000-8000-000000000003' where id = 'f2000000-0000-4000-8000-000000000001'$$, '%immutable%', 'objects.created_by неизменна');
select throws_ilike($$update public.tasks set object_id = 'f2000000-0000-4000-8000-000000000002' where id = 'f3000000-0000-4000-8000-000000000001'$$, '%immutable%', 'tasks.object_id неизменна');
select throws_ilike($$update public.tasks set created_by = 'f0000000-0000-4000-8000-000000000003' where id = 'f3000000-0000-4000-8000-000000000001'$$, '%immutable%', 'tasks.created_by неизменна');
select throws_ilike($$update public.tasks set created_at = now() - interval '1 day' where id = 'f3000000-0000-4000-8000-000000000001'$$, '%immutable%', 'tasks.created_at неизменна');
-- ---- запрет физического удаления
select throws_ok($$delete from public.profiles where id = 'f0000000-0000-4000-8000-000000000005'$$, '23001', null, 'profiles: DELETE запрещён');
select throws_ok($$delete from public.tasks where id = 'f3000000-0000-4000-8000-000000000001'$$, '23001', null, 'tasks: DELETE запрещён');
select throws_ok($$truncate public.profiles cascade$$, '23001', null, 'profiles: TRUNCATE запрещён');
select throws_ok($$truncate public.tasks cascade$$, '23001', null, 'tasks: TRUNCATE запрещён');
-- ---- append-only: task_history и comments
select throws_ok($$update public.task_history set details = '{"x":1}'::jsonb$$, '23001', null, 'history: UPDATE запрещён');
select throws_ok($$delete from public.task_history$$, '23001', null, 'history: DELETE запрещён');
select throws_ok($$truncate public.task_history$$, '23001', null, 'history: TRUNCATE запрещён');
select throws_ok($$update public.comments set content = 'changed'$$, '23001', null, 'comments: UPDATE запрещён');
select throws_ok($$delete from public.comments$$, '23001', null, 'comments: DELETE запрещён');
select throws_ok($$truncate public.comments$$, '23001', null, 'comments: TRUNCATE запрещён');
-- ---- снимки имён и серверное время
select lives_ok($$insert into public.task_history (id, task_id, event_type, actor_id, actor_name, created_at) values ('f6000000-0000-4000-8000-000000000002', 'f3000000-0000-4000-8000-000000000006', 'task_updated', 'f0000000-0000-4000-8000-000000000004', 'Поддельное имя', '2000-01-01')$$, 'history: вставка с поддельными именем и временем проходит');
select ok((select actor_name from public.task_history where id = 'f6000000-0000-4000-8000-000000000002') = 'Исполнитель А', 'history: actor_name берётся из профиля, а не от клиента');
select ok((select created_at from public.task_history where id = 'f6000000-0000-4000-8000-000000000002') >= now(), 'history: created_at задаётся сервером');
select lives_ok($$insert into public.comments (id, task_id, author_id, author_name, content, created_at) values ('f5000000-0000-4000-8000-000000000002', 'f3000000-0000-4000-8000-000000000006', 'f0000000-0000-4000-8000-000000000004', 'Поддельное имя', 'c2', '2000-01-01')$$, 'comments: вставка с поддельными именем и временем проходит');
select ok((select author_name from public.comments where id = 'f5000000-0000-4000-8000-000000000002') = 'Исполнитель А', 'comments: author_name берётся из профиля');
select ok((select created_at from public.comments where id = 'f5000000-0000-4000-8000-000000000002') >= now(), 'comments: created_at задаётся сервером');
select lives_ok($$insert into public.task_history (id, task_id, event_type, actor_id) values ('f6000000-0000-4000-8000-000000000003', 'f3000000-0000-4000-8000-000000000006', 'task_updated', 'f0000000-0000-4000-8000-000000000002'), ('f6000000-0000-4000-8000-000000000004', 'f3000000-0000-4000-8000-000000000006', 'task_updated', 'f0000000-0000-4000-8000-000000000002')$$, 'history: два события одной транзакции');
select ok((select h4.created_at > h3.created_at from public.task_history h3, public.task_history h4 where h3.id = 'f6000000-0000-4000-8000-000000000003' and h4.id = 'f6000000-0000-4000-8000-000000000004'), 'history: события одной транзакции упорядочены по времени');
select throws_ok($$insert into public.task_history (task_id, event_type, actor_id) values ('f3000000-0000-4000-8000-000000000006', 'task_updated', 'f0000000-0000-4000-8000-0000000000ff')$$, '23503', null, 'history: неизвестный участник отклонён');
select throws_ok($$insert into public.comments (task_id, author_id, content) values ('f3000000-0000-4000-8000-000000000006', 'f0000000-0000-4000-8000-0000000000ff', 'x')$$, '23503', null, 'comments: неизвестный автор отклонён');
-- ---- updated_at
select lives_ok($$update public.objects set title = 'Объект 1 (новый)' where id = 'f2000000-0000-4000-8000-000000000001'$$, 'objects: обновление названия');
select ok((select updated_at > created_at from public.objects where id = 'f2000000-0000-4000-8000-000000000001'), 'objects: updated_at обновляется триггером');
select lives_ok($$update public.tasks set title = 'T1 новое' where id = 'f3000000-0000-4000-8000-000000000001'$$, 'tasks: обновление названия');
select ok((select updated_at > created_at from public.tasks where id = 'f3000000-0000-4000-8000-000000000001'), 'tasks: updated_at обновляется триггером');
-- ---- создание задачи и проверка ролей ссылок
select throws_ok($$insert into public.tasks (object_id, title, status, created_by, responsible_manager_id, assigned_to) values ('f2000000-0000-4000-8000-000000000001', 't', 'in_progress', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004')$$, '23514', null, 'tasks: создание сразу не в new отклонено');
select throws_ilike($$insert into public.tasks (object_id, title, created_by, responsible_manager_id) values ('f2000000-0000-4000-8000-000000000001', 't', 'f0000000-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-000000000002')$$, '%creator must be a manager%', 'tasks: создатель-исполнитель отклонён');
select throws_ilike($$insert into public.tasks (object_id, title, created_by, responsible_manager_id) values ('f2000000-0000-4000-8000-000000000001', 't', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004')$$, '%Responsible manager must be a manager%', 'tasks: ответственный-исполнитель отклонён');
select throws_ilike($$insert into public.tasks (object_id, title, created_by, responsible_manager_id, assigned_to) values ('f2000000-0000-4000-8000-000000000001', 't', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000003')$$, '%Assignee must be an executor%', 'tasks: исполнитель-менеджер отклонён');
select throws_ilike($$update public.tasks set assigned_to = 'f0000000-0000-4000-8000-000000000001' where id = 'f3000000-0000-4000-8000-000000000001'$$, '%Assignee must be an executor%', 'tasks: назначение админа исполнителем отклонено');
select throws_ilike($$insert into public.objects (title, address, customer_name, customer_phone, created_by) values ('t', 'a', 'c', '+79990000000', 'f0000000-0000-4000-8000-000000000004')$$, '%creator must be a manager%', 'objects: создатель-исполнитель отклонён');
-- ---- редактирование содержания (ТЗ 6.5)
select lives_ok($$update public.tasks set title = 'T1 правка', description = 'd' where id = 'f3000000-0000-4000-8000-000000000001'$$, 'new без исполнителя: правка разрешена');
select throws_ilike($$update public.tasks set title = 'правка' where id = 'f3000000-0000-4000-8000-000000000002'$$, '%cannot be edited%', 'new с исполнителем: правка запрещена');
-- ---- переходы статусов (ТЗ 6.4): допустимые и запрещённые
select throws_ilike($$update public.tasks set status = 'under_review' where id = 'f3000000-0000-4000-8000-000000000005'$$, '%transition%not allowed%', 'new -> under_review запрещён');
select throws_ilike($$update public.tasks set status = 'accepted' where id = 'f3000000-0000-4000-8000-000000000005'$$, '%transition%not allowed%', 'new -> accepted запрещён');
select throws_ilike($$update public.tasks set status = 'revision' where id = 'f3000000-0000-4000-8000-000000000005'$$, '%transition%not allowed%', 'new -> revision запрещён');
select lives_ok($$update public.tasks set status = 'in_progress' where id = 'f3000000-0000-4000-8000-000000000003'$$, 'new -> in_progress');
select throws_ilike($$update public.tasks set title = 'правка' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%cannot be edited%', 'in_progress: правка запрещена');
select throws_ilike($$update public.tasks set status = 'new' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'in_progress -> new запрещён');
select throws_ilike($$update public.tasks set status = 'accepted' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'in_progress -> accepted запрещён');
select throws_ilike($$update public.tasks set status = 'closed' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'in_progress -> closed запрещён');
select throws_ilike($$update public.tasks set status = 'revision' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'in_progress -> revision запрещён');
select lives_ok($$update public.tasks set status = 'under_review' where id = 'f3000000-0000-4000-8000-000000000003'$$, 'in_progress -> under_review');
select throws_ilike($$update public.tasks set title = 'правка' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%cannot be edited%', 'under_review: правка запрещена');
select throws_ilike($$update public.tasks set status = 'new' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'under_review -> new запрещён');
select throws_ilike($$update public.tasks set status = 'in_progress' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'under_review -> in_progress запрещён');
select throws_ilike($$update public.tasks set status = 'closed' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'under_review -> closed запрещён');
select lives_ok($$update public.tasks set status = 'revision' where id = 'f3000000-0000-4000-8000-000000000003'$$, 'under_review -> revision');
select lives_ok($$update public.tasks set title = 'T3 после доработки' where id = 'f3000000-0000-4000-8000-000000000003'$$, 'revision: правка разрешена');
select throws_ilike($$update public.tasks set status = 'new' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'revision -> new запрещён');
select throws_ilike($$update public.tasks set status = 'under_review' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'revision -> under_review запрещён');
select throws_ilike($$update public.tasks set status = 'accepted' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'revision -> accepted запрещён');
select throws_ilike($$update public.tasks set status = 'closed' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'revision -> closed запрещён');
select lives_ok($$update public.tasks set status = 'in_progress' where id = 'f3000000-0000-4000-8000-000000000003'$$, 'revision -> in_progress');
select lives_ok($$update public.tasks set status = 'under_review' where id = 'f3000000-0000-4000-8000-000000000003'$$, 'in_progress -> under_review (повторно)');
select lives_ok($$update public.tasks set status = 'accepted' where id = 'f3000000-0000-4000-8000-000000000003'$$, 'under_review -> accepted');
select throws_ilike($$update public.tasks set title = 'правка' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%cannot be edited%', 'accepted: правка запрещена');
select throws_ilike($$update public.tasks set status = 'new' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'accepted -> new запрещён');
select throws_ilike($$update public.tasks set status = 'in_progress' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'accepted -> in_progress запрещён');
select throws_ilike($$update public.tasks set status = 'under_review' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'accepted -> under_review запрещён');
select throws_ilike($$update public.tasks set status = 'revision' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'accepted -> revision запрещён');
select throws_ilike($$update public.tasks set status = 'closed' where id = 'f3000000-0000-4000-8000-000000000003'$$, '%transition%not allowed%', 'accepted -> closed запрещён');
select throws_ilike($$update public.tasks set title = 'правка' where id = 'f3000000-0000-4000-8000-000000000004'$$, '%cannot be edited%', 'closed: правка запрещена');
select throws_ilike($$update public.tasks set status = 'new' where id = 'f3000000-0000-4000-8000-000000000004'$$, '%transition%not allowed%', 'closed -> new запрещён (повторное открытие)');
select throws_ilike($$update public.tasks set status = 'in_progress' where id = 'f3000000-0000-4000-8000-000000000004'$$, '%transition%not allowed%', 'closed -> in_progress запрещён (повторное открытие)');
select throws_ilike($$update public.tasks set status = 'under_review' where id = 'f3000000-0000-4000-8000-000000000004'$$, '%transition%not allowed%', 'closed -> under_review запрещён (повторное открытие)');
select throws_ilike($$update public.tasks set status = 'revision' where id = 'f3000000-0000-4000-8000-000000000004'$$, '%transition%not allowed%', 'closed -> revision запрещён (повторное открытие)');
select throws_ilike($$update public.tasks set status = 'accepted' where id = 'f3000000-0000-4000-8000-000000000004'$$, '%transition%not allowed%', 'closed -> accepted запрещён (повторное открытие)');
-- ---- жизненный цикл передач
select throws_ilike($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by, status, responded_at) values ('f3000000-0000-4000-8000-000000000006', 'executor', 'f0000000-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-000000000005', 'f0000000-0000-4000-8000-000000000001', 'accepted', now())$$, '%must be pending%', 'transfers: сразу принятая отклонена');
select throws_ilike($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by) values ('f3000000-0000-4000-8000-000000000006', 'executor', 'f0000000-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-000000000005', 'f0000000-0000-4000-8000-000000000002')$$, '%only by an admin%', 'transfers: инициатор не админ отклонён');
select throws_ilike($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by) values ('f3000000-0000-4000-8000-000000000006', 'executor', 'f0000000-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-000000000003', 'f0000000-0000-4000-8000-000000000001')$$, '%must be executors%', 'transfers: исполнитель -> менеджер отклонена');
select throws_ilike($$insert into public.transfers (task_id, responsibility_type, from_user_id, to_user_id, initiated_by) values ('f3000000-0000-4000-8000-000000000006', 'manager', 'f0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000005', 'f0000000-0000-4000-8000-000000000001')$$, '%must be managers%', 'transfers: менеджер -> исполнитель отклонена');
select lives_ok($$insert into public.transfers (id, task_id, responsibility_type, from_user_id, to_user_id, initiated_by) values ('f4000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000006', 'executor', 'f0000000-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-000000000005', 'f0000000-0000-4000-8000-000000000001')$$, 'transfers: корректная передача создаётся');
select throws_ilike($$update public.transfers set responded_at = null where id = 'f4000000-0000-4000-8000-000000000001'$$, '%can only move%', 'transfers: pending нельзя обновить без ответа');
select throws_ilike($$update public.transfers set to_user_id = 'f0000000-0000-4000-8000-000000000004', from_user_id = 'f0000000-0000-4000-8000-000000000005' where id = 'f4000000-0000-4000-8000-000000000001'$$, '%immutable%', 'transfers: стороны неизменны');
select lives_ok($$update public.transfers set status = 'accepted', responded_at = now() where id = 'f4000000-0000-4000-8000-000000000001'$$, 'transfers: pending -> accepted');
select throws_ilike($$update public.transfers set status = 'declined', responded_at = now() where id = 'f4000000-0000-4000-8000-000000000001'$$, '%already processed%', 'transfers: повторная обработка запрещена');
select throws_ok($$delete from public.transfers where id = 'f4000000-0000-4000-8000-000000000001'$$, '23001', null, 'transfers: DELETE запрещён');
select throws_ok($$truncate public.transfers$$, '23001', null, 'transfers: TRUNCATE запрещён');

select * from finish();
rollback;
