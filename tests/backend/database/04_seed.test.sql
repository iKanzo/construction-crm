-- Этап 3: локальный seed (supabase/seed.sql) — тестовые учётные записи трёх ролей.
begin;
select plan(7);

select is((select count(*)::int from public.profiles where id::text like 'a0000000-0000-4000-8000-%'), 5,
  'seed: 5 тестовых профилей');
select is((select string_agg(role || ':' || n, ',' order by role) from (
    select role, count(*) n from public.profiles where id::text like 'a0000000-0000-4000-8000-%' group by role) s),
  'admin:1,executor:2,manager:2', 'seed: 1 админ, 2 менеджера, 2 исполнителя');
select ok(not exists (select 1 from public.profiles where id::text like 'a0000000-0000-4000-8000-%' and not is_active),
  'seed: все активны');
select ok(not exists (
    select 1 from public.profiles p left join auth.users u on u.id = p.id
    where p.id::text like 'a0000000-0000-4000-8000-%' and (u.id is null or u.encrypted_password is null)),
  'seed: у каждого профиля есть пользователь auth с паролем');
select ok(not exists (
    select 1 from public.profiles p
    where p.id::text like 'a0000000-0000-4000-8000-%'
      and not exists (select 1 from auth.identities i where i.user_id = p.id and i.provider = 'email')),
  'seed: у каждого есть email-identity (нужна GoTrue для входа)');
select ok(not exists (
    select 1 from auth.users where id::text like 'a0000000-0000-4000-8000-%' and raw_user_meta_data ? 'role'),
  'seed: роль не хранится в user_metadata');
select ok(not exists (
    select 1 from auth.users where id::text like 'a0000000-0000-4000-8000-%'
      and encrypted_password = 'Password123!'),
  'seed: пароль хранится хешем');

select * from finish();
rollback;
