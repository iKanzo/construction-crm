-- Тестовые данные для ЛОКАЛЬНОЙ среды (`supabase db reset`).
-- НЕ применять к облачному проекту: пароли ниже публичны (решение C4).
-- `supabase db push` seed не выполняет, если не указан --include-seed.
--
-- Пользователи создаются напрямую в auth.users/auth.identities (формат GoTrue) и в profiles.
-- Роль берётся только из profiles.role, в user_metadata она не пишется.
--
-- Пароль всех тестовых учётных записей: Password123!

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('a0000000-0000-4000-8000-000000000001'::uuid, 'admin@crm.test',     'Админов Админ Админович',  'admin'),
      ('a0000000-0000-4000-8000-000000000011'::uuid, 'manager1@crm.test',  'Петров Пётр Петрович',     'manager'),
      ('a0000000-0000-4000-8000-000000000012'::uuid, 'manager2@crm.test',  'Сидорова Анна Сергеевна',  'manager'),
      ('a0000000-0000-4000-8000-000000000021'::uuid, 'executor1@crm.test', 'Иванов Иван Иванович',     'executor'),
      ('a0000000-0000-4000-8000-000000000022'::uuid, 'executor2@crm.test', 'Кузнецов Олег Николаевич', 'executor')
    ) as v(id, email, full_name, role)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
      extensions.crypt('Password123!', extensions.gen_salt('bf')), now(),
      '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
      '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), u.id, u.id::text,
      jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true, 'phone_verified', false),
      'email', now(), now(), now()
    );

    insert into public.profiles (id, full_name, role) values (u.id, u.full_name, u.role);
  end loop;
end $$;
