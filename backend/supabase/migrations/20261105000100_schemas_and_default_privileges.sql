-- Этап 2. Базовая настройка схем и привилегий по умолчанию.
-- Таблиц и функций приложения здесь ещё нет: они добавляются на Этапах 3–5.
-- Расширения не нужны: gen_random_uuid() встроен в PostgreSQL 13+.

-- Схема для внутренних хелперов (RLS-проверки, триггерные функции).
-- Не входит в api.schemas, поэтому недоступна через PostgREST.
-- USAGE для authenticated выдаётся на Этапе 4 вместе с хелперами RLS.
create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

-- В public запрещаем создавать объекты всем, кроме владельца миграций.
revoke create on schema public from public, anon, authenticated;

-- Supabase по умолчанию выдаёт anon/authenticated полные права на каждую НОВУЮ таблицу,
-- последовательность и функцию в public. Для нашей модели (ТЗ 12.3, решение G1)
-- это опасно: права должны выдаваться только явно. Миграции выполняются от роли postgres.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated;

-- PostgreSQL по умолчанию выдаёт EXECUTE на новые функции роли PUBLIC.
-- Отключаем: EXECUTE выдаётся только явным GRANT нужной роли (ТЗ 12.5).
alter default privileges for role postgres revoke execute on functions from public;
