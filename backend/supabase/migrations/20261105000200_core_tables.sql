-- Этап 3a. Шесть основных таблиц, ограничения и индексы (ТЗ раздел 11).
-- Триггеры (неизменяемость, переходы статусов, append-only) — в следующей миграции.
-- Права и политики RLS — Этап 4. Пока RLS включена без политик, а прав у anon/authenticated нет:
-- доступ закрыт полностью.

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id         uuid primary key references auth.users (id) on delete restrict,
  full_name  text        not null,
  role       text        not null,
  is_active  boolean     not null default true,
  created_at timestamptz not null default now(),
  constraint profiles_full_name_check check (char_length(btrim(full_name)) between 1 and 200),
  constraint profiles_role_check check (role in ('admin', 'manager', 'executor'))
);

-- ----------------------------------------------------------------- objects
create table public.objects (
  id             uuid primary key default gen_random_uuid(),
  title          text        not null,
  description    text        not null default '',
  address        text        not null,
  customer_name  text        not null,
  customer_phone text        not null,
  created_by     uuid        not null references public.profiles (id) on delete restrict,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint objects_title_check check (char_length(btrim(title)) between 1 and 200),
  constraint objects_description_check check (char_length(description) <= 5000),
  constraint objects_address_check check (char_length(btrim(address)) between 1 and 500),
  constraint objects_customer_name_check check (char_length(btrim(customer_name)) between 1 and 200),
  constraint objects_customer_phone_check check (char_length(btrim(customer_phone)) between 5 and 32)
);

-- ------------------------------------------------------------------- tasks
create table public.tasks (
  id                     uuid primary key default gen_random_uuid(),
  object_id              uuid        not null references public.objects (id) on delete restrict,
  title                  text        not null,
  description            text        not null default '',
  status                 text        not null default 'new',
  created_by             uuid        not null references public.profiles (id) on delete restrict,
  responsible_manager_id uuid        not null references public.profiles (id) on delete restrict,
  assigned_to            uuid        references public.profiles (id) on delete restrict,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint tasks_title_check check (char_length(btrim(title)) between 1 and 200),
  constraint tasks_description_check check (char_length(description) <= 10000),
  constraint tasks_status_check
    check (status in ('new', 'in_progress', 'under_review', 'revision', 'accepted', 'closed')),
  -- Следствие правил 6.4 и 6.6: исполнитель обязателен после взятия в работу,
  -- а закрытая задача никогда не имела исполнителя.
  constraint tasks_status_assignee_check check (
    status = 'new'
    or (status = 'closed' and assigned_to is null)
    or (status in ('in_progress', 'under_review', 'revision', 'accepted') and assigned_to is not null)
  )
);

-- ------------------------------------------------------------ task_history
create table public.task_history (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid        not null references public.tasks (id) on delete restrict,
  event_type  text        not null,
  actor_id    uuid        not null references public.profiles (id) on delete restrict,
  actor_name  text        not null,
  old_status  text,
  new_status  text,
  details     jsonb       not null default '{}'::jsonb,
  -- clock_timestamp(), а не now(): события одной транзакции получают разное время и порядок.
  created_at  timestamptz not null default clock_timestamp(),
  constraint task_history_event_type_check check (event_type in (
    'task_created', 'executor_assigned', 'assignment_declined', 'status_changed', 'task_closed',
    'task_updated', 'transfer_initiated', 'transfer_accepted', 'transfer_declined',
    'transfer_cancelled', 'executor_changed', 'manager_changed'
  )),
  constraint task_history_old_status_check
    check (old_status is null or old_status in ('new', 'in_progress', 'under_review', 'revision', 'accepted', 'closed')),
  constraint task_history_new_status_check
    check (new_status is null or new_status in ('new', 'in_progress', 'under_review', 'revision', 'accepted', 'closed')),
  constraint task_history_status_changed_check
    check (event_type <> 'status_changed' or (old_status is not null and new_status is not null and old_status <> new_status)),
  constraint task_history_task_closed_check
    check (event_type <> 'task_closed' or (old_status = 'new' and new_status = 'closed')),
  constraint task_history_details_check check (jsonb_typeof(details) = 'object')
);

-- ---------------------------------------------------------------- comments
create table public.comments (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid        not null references public.tasks (id) on delete restrict,
  author_id   uuid        not null references public.profiles (id) on delete restrict,
  author_name text        not null,
  content     text        not null,
  created_at  timestamptz not null default clock_timestamp(),
  constraint comments_content_check check (char_length(btrim(content)) between 1 and 5000)
);

-- --------------------------------------------------------------- transfers
create table public.transfers (
  id                    uuid primary key default gen_random_uuid(),
  task_id               uuid        not null references public.tasks (id) on delete restrict,
  responsibility_type   text        not null,
  from_user_id          uuid        not null references public.profiles (id) on delete restrict,
  to_user_id            uuid        not null references public.profiles (id) on delete restrict,
  initiated_by          uuid        not null references public.profiles (id) on delete restrict,
  -- cancelled добавлен по решению C3 (отмена админом и автоотмена).
  status                text        not null default 'pending',
  created_at            timestamptz not null default now(),
  responded_at          timestamptz,
  constraint transfers_type_check check (responsibility_type in ('executor', 'manager')),
  constraint transfers_status_check check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  constraint transfers_distinct_users_check check (from_user_id <> to_user_id),
  constraint transfers_responded_check check ((status = 'pending') = (responded_at is null))
);

-- ----------------------------------------------------------------- индексы
-- Под реальные запросы: списки по объекту, «мои задачи», проверки доступа к объекту,
-- лента истории и чата задачи, входящие и исходящие предложения передачи.
create index objects_created_by_idx on public.objects (created_by);

create index tasks_object_id_idx on public.tasks (object_id);
create index tasks_manager_object_idx on public.tasks (responsible_manager_id, object_id);
create index tasks_assignee_object_idx on public.tasks (assigned_to, object_id) where assigned_to is not null;

create index task_history_task_created_idx on public.task_history (task_id, created_at);
create index comments_task_created_idx on public.comments (task_id, created_at);

-- ТЗ 7.3 и 11.6: одно активное предложение на задачу и тип ответственности.
create unique index transfers_one_pending_per_type_uidx
  on public.transfers (task_id, responsibility_type) where status = 'pending';
create index transfers_pending_to_idx on public.transfers (to_user_id) where status = 'pending';
create index transfers_pending_from_idx on public.transfers (from_user_id) where status = 'pending';
create index transfers_task_created_idx on public.transfers (task_id, created_at);

-- ---------------------------------------------------------------------- RLS
alter table public.profiles     enable row level security;
alter table public.objects      enable row level security;
alter table public.tasks        enable row level security;
alter table public.task_history enable row level security;
alter table public.comments     enable row level security;
alter table public.transfers    enable row level security;
