-- Этап 4: SQL-привилегии, безопасность функций, форма политик, попытки записи.
-- Файл сгенерирован.
begin;
select plan(110);


-- Выполняет запрос от имени роли БД и пользователя (JWT-claims), возвращает текст результата
-- или 'ERR:<sqlstate>'. Проверки выполняются вне ролей authenticated/anon, поэтому не зависят
-- от того, доступны ли им функции pgTAP.
create function pg_temp.act(p_uid uuid, p_role text, p_sql text, p_extra jsonb default '{}'::jsonb)
returns text language plpgsql as $f$
declare
  res text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then ''
         else (jsonb_build_object('sub', p_uid, 'role', p_role) || p_extra)::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into res;
  exception when others then
    res := 'ERR:' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return res;
end $f$;

-- Двузначные метки строк (последние 2 цифры id), отсортированные, через запятую.
create function pg_temp.vis(p_uid uuid, p_tbl text, p_role text default 'authenticated',
                            p_extra jsonb default '{}'::jsonb)
returns text language sql as $f$
  select pg_temp.act(p_uid, p_role, format(
    $q$select coalesce(string_agg(right(id::text, 2), ',' order by right(id::text, 2)), '')
       from public.%I where id::text ~ '^b[0-6]000000-0000-4000-8000-'$q$, p_tbl), p_extra)
$f$;

select ok(has_table_privilege('authenticated', 'public.profiles', 'SELECT'), 'authenticated: SELECT на profiles');
select ok(not has_table_privilege('authenticated', 'public.profiles', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'authenticated: нет прав записи на profiles');
select ok(not has_table_privilege('anon', 'public.profiles', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: нет прав на profiles');
select ok(has_table_privilege('authenticated', 'public.objects', 'SELECT'), 'authenticated: SELECT на objects');
select ok(not has_table_privilege('authenticated', 'public.objects', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'authenticated: нет прав записи на objects');
select ok(not has_table_privilege('anon', 'public.objects', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: нет прав на objects');
select ok(has_table_privilege('authenticated', 'public.tasks', 'SELECT'), 'authenticated: SELECT на tasks');
select ok(not has_table_privilege('authenticated', 'public.tasks', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'authenticated: нет прав записи на tasks');
select ok(not has_table_privilege('anon', 'public.tasks', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: нет прав на tasks');
select ok(has_table_privilege('authenticated', 'public.task_history', 'SELECT'), 'authenticated: SELECT на task_history');
select ok(not has_table_privilege('authenticated', 'public.task_history', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'authenticated: нет прав записи на task_history');
select ok(not has_table_privilege('anon', 'public.task_history', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: нет прав на task_history');
select ok(has_table_privilege('authenticated', 'public.comments', 'SELECT'), 'authenticated: SELECT на comments');
select ok(not has_table_privilege('authenticated', 'public.comments', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'authenticated: нет прав записи на comments');
select ok(not has_table_privilege('anon', 'public.comments', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: нет прав на comments');
select ok(has_table_privilege('authenticated', 'public.transfers', 'SELECT'), 'authenticated: SELECT на transfers');
select ok(not has_table_privilege('authenticated', 'public.transfers', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'authenticated: нет прав записи на transfers');
select ok(not has_table_privilege('anon', 'public.transfers', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), 'anon: нет прав на transfers');
select ok(has_function_privilege('authenticated', 'private.auth_role()', 'EXECUTE'), 'authenticated: EXECUTE private.auth_role()');
select ok(not has_function_privilege('anon', 'private.auth_role()', 'EXECUTE'), 'anon: нет EXECUTE private.auth_role()');
select ok(not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.auth_role()'::regprocedure and a.grantee = 0), 'PUBLIC: нет EXECUTE private.auth_role()');
select ok(has_function_privilege('authenticated', 'private.manager_has_object_access(uuid)', 'EXECUTE'), 'authenticated: EXECUTE private.manager_has_object_access(uuid)');
select ok(not has_function_privilege('anon', 'private.manager_has_object_access(uuid)', 'EXECUTE'), 'anon: нет EXECUTE private.manager_has_object_access(uuid)');
select ok(not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.manager_has_object_access(uuid)'::regprocedure and a.grantee = 0), 'PUBLIC: нет EXECUTE private.manager_has_object_access(uuid)');
select ok(has_function_privilege('authenticated', 'private.can_view_object(uuid)', 'EXECUTE'), 'authenticated: EXECUTE private.can_view_object(uuid)');
select ok(not has_function_privilege('anon', 'private.can_view_object(uuid)', 'EXECUTE'), 'anon: нет EXECUTE private.can_view_object(uuid)');
select ok(not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.can_view_object(uuid)'::regprocedure and a.grantee = 0), 'PUBLIC: нет EXECUTE private.can_view_object(uuid)');
select ok(has_function_privilege('authenticated', 'private.can_view_task_row(uuid,uuid,uuid)', 'EXECUTE'), 'authenticated: EXECUTE private.can_view_task_row(uuid,uuid,uuid)');
select ok(not has_function_privilege('anon', 'private.can_view_task_row(uuid,uuid,uuid)', 'EXECUTE'), 'anon: нет EXECUTE private.can_view_task_row(uuid,uuid,uuid)');
select ok(not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.can_view_task_row(uuid,uuid,uuid)'::regprocedure and a.grantee = 0), 'PUBLIC: нет EXECUTE private.can_view_task_row(uuid,uuid,uuid)');
select ok(has_function_privilege('authenticated', 'private.can_view_task(uuid)', 'EXECUTE'), 'authenticated: EXECUTE private.can_view_task(uuid)');
select ok(not has_function_privilege('anon', 'private.can_view_task(uuid)', 'EXECUTE'), 'anon: нет EXECUTE private.can_view_task(uuid)');
select ok(not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.can_view_task(uuid)'::regprocedure and a.grantee = 0), 'PUBLIC: нет EXECUTE private.can_view_task(uuid)');
select ok(has_function_privilege('authenticated', 'private.can_view_chat(uuid)', 'EXECUTE'), 'authenticated: EXECUTE private.can_view_chat(uuid)');
select ok(not has_function_privilege('anon', 'private.can_view_chat(uuid)', 'EXECUTE'), 'anon: нет EXECUTE private.can_view_chat(uuid)');
select ok(not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.can_view_chat(uuid)'::regprocedure and a.grantee = 0), 'PUBLIC: нет EXECUTE private.can_view_chat(uuid)');
select ok(has_function_privilege('authenticated', 'private.manager_object_ids()', 'EXECUTE'), 'authenticated: EXECUTE private.manager_object_ids()');
select ok(not has_function_privilege('anon', 'private.manager_object_ids()', 'EXECUTE'), 'anon: нет EXECUTE private.manager_object_ids()');
select ok(not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.manager_object_ids()'::regprocedure and a.grantee = 0), 'PUBLIC: нет EXECUTE private.manager_object_ids()');
select ok(has_function_privilege('authenticated', 'private.visible_object_ids()', 'EXECUTE'), 'authenticated: EXECUTE private.visible_object_ids()');
select ok(not has_function_privilege('anon', 'private.visible_object_ids()', 'EXECUTE'), 'anon: нет EXECUTE private.visible_object_ids()');
select ok(not exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = 'private.visible_object_ids()'::regprocedure and a.grantee = 0), 'PUBLIC: нет EXECUTE private.visible_object_ids()');
select ok(not has_schema_privilege('anon', 'private', 'USAGE'), 'anon: нет USAGE на private');
select ok(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname not in ('auth_role', 'manager_has_object_access', 'manager_object_ids', 'visible_object_ids', 'can_view_object', 'can_view_task_row', 'can_view_task', 'can_view_chat')
    and (has_function_privilege('authenticated', p.oid, 'EXECUTE') or has_function_privilege('anon', p.oid, 'EXECUTE'))
), 'триггерные функции private недоступны authenticated и anon');
select ok(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef and n.nspname in ('public', 'private')
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'search_path=""')
), 'все SECURITY DEFINER функции имеют пустой фиксированный search_path');
select ok(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.prosecdef and p.proname <> 'require_active_profile' and p.provolatile <> 's'
), 'все SECURITY DEFINER хелперы private — STABLE');
select is((select count(*)::int from pg_policies where schemaname = 'public'), 6, 'в public ровно 6 политик (по одной на таблицу)');
select ok(not exists (select 1 from pg_policies where schemaname = 'public' and cmd <> 'SELECT'), 'все политики только на SELECT');
select ok(not exists (select 1 from pg_policies where schemaname = 'public' and roles <> '{authenticated}'), 'все политики назначены только роли authenticated');
select ok(not exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not exists (select 1 from pg_policies pl where pl.schemaname = 'public' and pl.tablename = c.relname)), 'у каждой таблицы public есть политика');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.profiles default values returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): insert в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.profiles set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): update в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.profiles returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): delete в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.objects default values returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): insert в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.objects set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): update в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.objects returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): delete в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.tasks default values returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): insert в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.tasks set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): update в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.tasks returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): delete в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.task_history default values returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): insert в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.task_history set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): update в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.task_history returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): delete в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.comments default values returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): insert в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.comments set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): update в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.comments returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): delete в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.transfers default values returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): insert в transfers запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.transfers set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): update в transfers запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.transfers returning 1) select 'ok'$q$), 'ERR:42501', 'админ (authenticated): delete в transfers запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.profiles default values returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): insert в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.profiles set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): update в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.profiles returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): delete в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.objects default values returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): insert в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.objects set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): update в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.objects returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): delete в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.tasks default values returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): insert в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.tasks set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): update в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.tasks returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): delete в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.task_history default values returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): insert в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.task_history set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): update в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.task_history returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): delete в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.comments default values returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): insert в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.comments set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): update в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.comments returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): delete в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.transfers default values returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): insert в transfers запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.transfers set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): update в transfers запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.transfers returning 1) select 'ok'$q$), 'ERR:42501', 'менеджер (authenticated): delete в transfers запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.profiles default values returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): insert в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.profiles set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): update в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.profiles returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): delete в profiles запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.objects default values returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): insert в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.objects set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): update в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.objects returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): delete в objects запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.tasks default values returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): insert в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.tasks set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): update в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.tasks returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): delete в tasks запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.task_history default values returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): insert в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.task_history set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): update в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.task_history returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): delete в task_history запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.comments default values returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): insert в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.comments set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): update в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.comments returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): delete в comments запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (insert into public.transfers default values returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): insert в transfers запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (update public.transfers set id = id returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): update в transfers запрещён на уровне привилегий');
select is(pg_temp.act('b0000000-0000-4000-8000-000000000099', 'authenticated', $q$with x as (delete from public.transfers returning 1) select 'ok'$q$), 'ERR:42501', 'исполнитель (authenticated): delete в transfers запрещён на уровне привилегий');
select is(pg_temp.act(null, 'anon', $q$with x as (insert into public.profiles default values returning 1) select 'ok'$q$), 'ERR:42501', 'anon: insert в profiles запрещён');
select is(pg_temp.act(null, 'anon', $q$with x as (insert into public.objects default values returning 1) select 'ok'$q$), 'ERR:42501', 'anon: insert в objects запрещён');
select is(pg_temp.act(null, 'anon', $q$with x as (insert into public.tasks default values returning 1) select 'ok'$q$), 'ERR:42501', 'anon: insert в tasks запрещён');
select is(pg_temp.act(null, 'anon', $q$with x as (insert into public.task_history default values returning 1) select 'ok'$q$), 'ERR:42501', 'anon: insert в task_history запрещён');
select is(pg_temp.act(null, 'anon', $q$with x as (insert into public.comments default values returning 1) select 'ok'$q$), 'ERR:42501', 'anon: insert в comments запрещён');
select is(pg_temp.act(null, 'anon', $q$with x as (insert into public.transfers default values returning 1) select 'ok'$q$), 'ERR:42501', 'anon: insert в transfers запрещён');

select * from finish();
rollback;
