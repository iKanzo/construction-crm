-- Этап 4b. SQL-привилегии и политики RLS (ТЗ 12.2, 12.3; решение G1).
--
-- Модель: authenticated получает ТОЛЬКО SELECT. INSERT/UPDATE/DELETE/TRUNCATE не выдаются никому,
-- включая администратора: запись идёт исключительно через RPC (Этап 5). Поэтому политик на запись
-- нет. anon не получает ничего. RLS определяет, КАКИЕ строки видны, GRANT — КАКИЕ операции доступны.

-- Политики вызывают хелперы от имени пользователя, поэтому ему нужны USAGE и EXECUTE.
-- Триггерные функции private ему недоступны.
grant usage on schema private to authenticated;

revoke all on function
  private.auth_role(),
  private.manager_has_object_access(uuid),
  private.manager_object_ids(),
  private.visible_object_ids(),
  private.can_view_object(uuid),
  private.can_view_task_row(uuid, uuid, uuid),
  private.can_view_task(uuid),
  private.can_view_chat(uuid)
from public, anon;

grant execute on function
  private.auth_role(),
  private.manager_has_object_access(uuid),
  private.manager_object_ids(),
  private.visible_object_ids(),
  private.can_view_object(uuid),
  private.can_view_task_row(uuid, uuid, uuid),
  private.can_view_task(uuid),
  private.can_view_chat(uuid)
to authenticated;

grant select on
  public.profiles, public.objects, public.tasks,
  public.task_history, public.comments, public.transfers
to authenticated;

-- (select ...) вокруг функций без аргументов заставляет PostgreSQL вычислить их один раз на запрос.

-- G5: активный пользователь видит все профили (в profiles нет email — он остаётся в auth).
-- Свой профиль виден всегда, чтобы деактивированный пользователь мог увидеть причину отказа.
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.auth_role()) is not null);

create policy objects_select on public.objects for select to authenticated
  using ((select private.auth_role()) = 'admin' or id in (select private.visible_object_ids()));

-- Менеджер: свои задачи (в том числе полученные передачей) и все задачи объектов, которые ему
-- открывает его собственная созданная задача. Исполнитель: только назначенные ему.
create policy tasks_select on public.tasks for select to authenticated
  using (
    (select private.auth_role()) = 'admin'
    or ((select private.auth_role()) = 'manager'
        and (responsible_manager_id = (select auth.uid())
             or object_id in (select private.manager_object_ids())))
    or ((select private.auth_role()) = 'executor' and assigned_to = (select auth.uid()))
  );

-- История видна тем, кто видит задачу: менеджеру объекта — история всех задач объекта,
-- новому менеджеру/исполнителю после передачи — вся история задачи (решение G4).
create policy task_history_select on public.task_history for select to authenticated
  using ((select private.auth_role()) = 'admin' or private.can_view_task(task_id));

-- Чат строже задачи: только админ, текущий ответственный менеджер и текущий исполнитель.
create policy comments_select on public.comments for select to authenticated
  using (private.can_view_chat(task_id));

-- Предложения передачи видны администратору и сторонам предложения.
create policy transfers_select on public.transfers for select to authenticated
  using (
    (select private.auth_role()) = 'admin'
    or ((select private.auth_role()) is not null
        and (select auth.uid()) in (to_user_id, from_user_id))
  );
