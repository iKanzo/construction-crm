# Construction CRM

MVP CRM для строительной компании: учёт объектов, задач, сотрудников, назначений, передачи ответственности, проверки выполнения, истории и сообщений по задачам.

Frontend: React + TypeScript + Vite. Backend: Supabase (PostgreSQL, Auth, RLS, RPC и Edge Functions). Публикация frontend выполняется через Vercel.

## Возможности

- Авторизация и восстановление пароля.
- Роли: администратор, менеджер, исполнитель.
- Управление объектами и задачами.
- Назначение исполнителей и обработка отказов.
- Изменение состояния задач и проверка результата.
- Предложения о передаче ответственности.
- История событий и чат по задаче.
- Приглашение сотрудников администратором.
- Разграничение доступа на уровне PostgreSQL с помощью RLS.

Проект является MVP. Наличие функции в интерфейсе не следует трактовать как гарантию покрытия всех возможных бизнес-сценариев.

## Технологический стек

### Frontend

- React 18.3
- TypeScript 5.6
- Vite 5
- React Router 6
- TanStack Query 5
- React Hook Form
- Zod
- Supabase JS
- Sass
- Vitest, Testing Library
- Playwright
- Storybook
- ESLint, Prettier

### Backend и инфраструктура

- Supabase PostgreSQL
- Supabase Auth
- PostgreSQL Row Level Security (RLS)
- PostgreSQL functions / RPC
- Supabase Edge Functions (Deno)
- Supabase CLI
- GitHub Actions
- Vercel

Точные версии зависимостей зафиксированы в `package-lock.json`. Корневой проект требует Node.js `>=22.13.0`; CI использует Node.js 24.

## Структура

```text
.
├── frontend/                  # React-приложение
│   └── src/
├── backend/
│   └── supabase/
│       ├── migrations/         # Миграции PostgreSQL
│       ├── functions/
│       │   └── invite-user/    # Приглашение сотрудника
│       ├── config.toml         # Локальная конфигурация Supabase
│       └── seed.sql            # Только локальные демоданные
├── tests/
│   ├── frontend/
│   └── backend/
│       ├── database/           # SQL / pgTAP tests
│       └── local/              # Локальный SQL test harness
├── .github/workflows/ci.yml
├── package.json                # npm workspace и общие scripts
├── package-lock.json
└── .env.example
```

## Требования

- Node.js 22.13.0 или новее.
- npm.
- Docker — для локального Supabase.
- Supabase CLI (проект содержит npm script для вызова локальной CLI).
- Для SQL harness на обычном PostgreSQL: PostgreSQL, `psql`, pgTAP и `pg_prove`.

## Установка и локальный запуск

Команды выполнять из корня репозитория.

```bash
npm install
npm run db:start
npm run supabase -- status
```

Создайте файл `frontend/.env.local` на основе `.env.example` и укажите локальные значения, которые выводит команда `npm run supabase -- status`:

```env
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=your-local-anon-key
```

Затем запустите frontend:

```bash
npm run dev
```

Vite выведет локальный адрес приложения (обычно `http://localhost:5173`).

Остановка локального Supabase:

```bash
npm run db:stop
```

## Доступные команды

| Команда | Назначение |
|---|---|
| `npm run dev` | Запуск Vite dev server |
| `npm run build` | TypeScript build check и production build |
| `npm run typecheck` | Проверка TypeScript |
| `npm run lint` | ESLint |
| `npm test` | Frontend-тесты Vitest |
| `npm run test:e2e` | E2E-тесты Playwright |
| `npm run db:start` | Запуск локального Supabase |
| `npm run db:stop` | Остановка локального Supabase |
| `npm run db:reset` | Пересоздание локальной БД, применение миграций и seed |
| `npm run test:db` | SQL-тесты через Supabase CLI |
| `npm run test:db:local` | SQL-тесты через отдельный PostgreSQL harness |
| `npm run format` | Форматирование Prettier |
| `npm run format:check` | Проверка форматирования |

**Внимание:** `npm run db:reset` удаляет и пересоздаёт локальную базу. Не запускайте эту команду против облачного проекта.

## Переменные окружения

Frontend использует:

| Переменная | Описание |
|---|---|
| `VITE_SUPABASE_URL` | URL Supabase |
| `VITE_SUPABASE_ANON_KEY` | Публичный anon/publishable key |

Локальный env-файл: `frontend/.env.local`. Он не должен попадать в Git.

Переменные с префиксом `VITE_` доступны в браузерной сборке. **Нельзя помещать в frontend или публичный репозиторий `service_role` / secret key.** Серверный ключ используется только на стороне Edge Function.

## Архитектурные принципы

- Frontend отвечает за UI, формы, навигацию и отображение серверных данных.
- Supabase Auth управляет пользовательской сессией.
- Роль приложения хранится в `profiles.role`.
- RLS ограничивает доступ к строкам на стороне PostgreSQL.
- Критические бизнес-операции вынесены в SQL RPC.
- Приглашение сотрудника выполняется через Edge Function `invite-user`.
- Доступ к объекту и доступ к полной строке задачи разделены: наличие доступа к объекту само по себе не открывает все его задачи.
- Локальная конфигурация отключает Realtime и Storage; чат использует polling через TanStack Query.

## Тестирование

Frontend:
- Vitest;
- Testing Library;
- jsdom;
- Playwright для E2E.

Backend:
- SQL/pgTAP проверки RLS и бизнес-операций;
- отдельный локальный harness `tests/backend/local/run.sh`.

Локально 7 ноября 2026 года подтверждены 48 прошедших frontend-тестов, успешная TypeScript-проверка и production build. Основные роли admin, manager и executor также проверялись вручную. Актуальный статус CI см. во вкладке Actions GitHub.

## CI

Workflow: `.github/workflows/ci.yml`.

Запускается на push, pull request и вручную. Frontend job выполняет install, typecheck, lint, Vitest, build и Playwright. Database job запускает локальный Supabase и SQL-тесты.

## Развёртывание

### Vercel

Текущая конфигурация frontend:

- Root Directory: `./`
- Framework Preset: Vite
- Install Command: `npm install`
- Build Command: `npm run build`
- Output Directory: `frontend/dist`

Environment Variables в Vercel:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

После изменения переменных окружения требуется новый deployment.

### Supabase Cloud

Облачный Supabase настраивается отдельно от локального `backend/supabase/config.toml`. Миграции должны быть применены к целевому проекту, а Auth URL/redirect settings и Edge Function secrets должны быть настроены в облачном Dashboard/CLI.

Не запускайте локальный seed в облаке. Файл `backend/supabase/seed.sql` содержит публичные демонстрационные пароли и предназначен только для локальной разработки.


## Репозиторий

[GitHub: iKanzo/construction-crm](https://github.com/iKanzo/construction-crm)
