-- Этап 3: структура схемы (таблицы, RLS, внешние ключи, индексы, типы, отсутствие прав).
begin;
select plan(24);

select has_table('public', t, format('таблица %s существует', t))
from unnest(array['profiles', 'objects', 'tasks', 'task_history', 'comments', 'transfers']) as t;

select ok(
  not exists (
    select 1 from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity
  ),
  'RLS включена на всех таблицах public'
);

select is(
  (select confdeltype::text from pg_constraint
   where conrelid = 'public.tasks'::regclass and confrelid = 'public.objects'::regclass and contype = 'f'),
  'r', 'tasks.object_id -> objects: ON DELETE RESTRICT'
);
select ok(
  not exists (
    select 1 from pg_constraint
    where contype = 'f' and connamespace = 'public'::regnamespace and confdeltype <> 'r'
  ),
  'все внешние ключи public используют ON DELETE RESTRICT'
);

select has_index('public', tbl, idx, format('индекс %s существует', idx))
from (values
  ('objects', 'objects_created_by_idx'),
  ('tasks', 'tasks_object_id_idx'),
  ('tasks', 'tasks_manager_object_idx'),
  ('tasks', 'tasks_assignee_object_idx'),
  ('task_history', 'task_history_task_created_idx'),
  ('comments', 'comments_task_created_idx'),
  ('transfers', 'transfers_one_pending_per_type_uidx'),
  ('transfers', 'transfers_pending_to_idx'),
  ('transfers', 'transfers_pending_from_idx'),
  ('transfers', 'transfers_task_created_idx')
) as i(tbl, idx);

select ok(
  (select indexdef ilike 'create unique index%' and indexdef ilike '%(task_id, responsibility_type)%'
          and indexdef ilike '%where%pending%'
   from pg_indexes where schemaname = 'public' and indexname = 'transfers_one_pending_per_type_uidx'),
  'активные передачи: unique partial index по (task_id, responsibility_type) WHERE pending'
);

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and column_name = 'id' and data_type <> 'uuid'
  ),
  'все id — uuid'
);
select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and column_name in ('created_at', 'updated_at', 'responded_at')
      and data_type <> 'timestamp with time zone'
  ),
  'все метки времени — timestamptz'
);

select ok(
  not exists (
    select 1 from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
      and has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  ),
  'anon не имеет прав на таблицы'
);
select ok(
  not exists (
    select 1 from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
      and has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  ),
  'authenticated не имеет прав записи на таблицы (запись только через RPC)'
);

select * from finish();
rollback;
