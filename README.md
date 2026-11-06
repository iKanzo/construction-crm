# Construction CRM

MVP CRM для строительной компании на React и Supabase. [PROJECT_SPEC.md](PROJECT_SPEC.md) содержит согласованные уточнения и открытые вопросы, но не полное исходное ТЗ.

## Состояние проекта

Frontend подключён к Supabase: реализованы экраны входа и восстановления пароля, объектов, задач, передач, сотрудников и профиля. Действия вызывают backend RPC или Edge Function; доступные кнопки зависят от роли и состояния данных. Это реализация MVP, а не подтверждение работоспособности всех сценариев или готовности к production.

Backend содержит миграции PostgreSQL с RLS, бизнес-RPC и Edge Function `invite-user`. Seed предназначен только для локальной разработки. Тесты и CI присутствуют, но их наличие не означает успешного прохождения. Существующие документы [DATABASE.md](docs/DATABASE.md) и [TESTING.md](docs/TESTING.md) могут содержать устаревшие детали; источником истины остаётся код.

## Быстрый старт

Нужны Node.js 20+, npm и Docker для локального Supabase. Из корня проекта:

```sh
npm install
npm run db:start
npm run supabase -- status
```

Скопируйте `.env.example` в `frontend/.env.local` и укажите `VITE_SUPABASE_URL` и публичный `VITE_SUPABASE_ANON_KEY` из статуса локального Supabase. Не используйте service role key во frontend. Затем запустите `npm run dev` и откройте адрес Vite. При изменении переменных перезапустите Vite.

Локальная конфигурация включает seed с известными учётными данными; он не предназначен для облака. `npm run db:reset` уничтожает данные локальной БД. Для приглашений необходим работающий Edge runtime и доступная функция `invite-user`; локальные письма принимает почтовый сервис Supabase.

## Документация

- [Архитектура](docs/ARCHITECTURE.md) — фактические компоненты и поток данных.
- [Разработка](docs/DEVELOPMENT.md) — настройка, команды и ограничения проверок.
- [Безопасность](docs/SECURITY.md) — границы доступа и меры перед развёртыванием.
- `frontend/` — приложение; `backend/supabase/` — конфигурация, миграции, seed и Edge Function; `tests/` — frontend, e2e и SQL-тесты.
