-- Этап 2: привилегии по умолчанию (миграция 20261105000100).
-- Проверяем, что НОВЫЕ объекты в public не получают прав anon/authenticated автоматически.
begin;
select plan(15);

create table public._probe_table (id int);
create sequence public._probe_seq;
create function public._probe_fn() returns int language sql as 'select 1';

select has_schema('private', 'схема private существует');
select ok(not has_schema_privilege('anon', 'private', 'USAGE'), 'anon без USAGE на private');
select ok(has_schema_privilege('authenticated', 'private', 'USAGE'),
  'authenticated имеет USAGE на private (нужен для вызова хелперов из политик RLS)');

select ok(not has_schema_privilege('anon', 'public', 'CREATE'), 'anon не может создавать в public');
select ok(not has_schema_privilege('authenticated', 'public', 'CREATE'),
  'authenticated не может создавать в public');

select ok(not has_table_privilege('anon', 'public._probe_table', 'SELECT,INSERT,UPDATE,DELETE'),
  'новая таблица: anon без прав');
select ok(not has_table_privilege('authenticated', 'public._probe_table', 'SELECT,INSERT,UPDATE,DELETE'),
  'новая таблица: authenticated без прав');

select ok(not has_sequence_privilege('anon', 'public._probe_seq', 'USAGE,SELECT,UPDATE'),
  'новая последовательность: anon без прав');
select ok(not has_sequence_privilege('authenticated', 'public._probe_seq', 'USAGE,SELECT,UPDATE'),
  'новая последовательность: authenticated без прав');

select ok(not has_function_privilege('anon', 'public._probe_fn()', 'EXECUTE'),
  'новая функция: anon без EXECUTE');
select ok(not has_function_privilege('authenticated', 'public._probe_fn()', 'EXECUTE'),
  'новая функция: authenticated без EXECUTE');
select ok(
  not exists (
    select 1
    from pg_proc p,
         lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'public._probe_fn()'::regprocedure
      and a.grantee = 0
      and a.privilege_type = 'EXECUTE'
  ),
  'новая функция: PUBLIC без EXECUTE'
);

select ok(has_table_privilege('service_role', 'public._probe_table', 'SELECT,INSERT'),
  'service_role сохраняет доступ (нужен Edge Functions)');
select ok(has_function_privilege('service_role', 'public._probe_fn()', 'EXECUTE'),
  'service_role сохраняет EXECUTE');
select ok(has_table_privilege('postgres', 'public._probe_table', 'SELECT,INSERT'),
  'владелец (postgres) сохраняет доступ');

select * from finish();
rollback;
