import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
export const configured = Boolean(url && key);
// Capture the link type before Auth consumes/removes the URL fragment.
const linkParams = new URLSearchParams(window.location.hash.slice(1));
export const passwordLink = ['invite', 'recovery'].includes(linkParams.get('type') || '');
export const authLinkError = linkParams.get('error_description') || '';
export const supabase = createClient(url || 'http://127.0.0.1:54321', key || 'missing-key');

export type Role = 'admin' | 'manager' | 'executor';
export type Profile = { id: string; full_name: string; role: Role; is_active: boolean };
export type ObjectRow = { id: string; title: string; description: string; address: string; customer_name: string; customer_phone: string; created_by: string };
export type Task = { id: string; object_id: string; title: string; description: string; status: string; created_by: string; responsible_manager_id: string; assigned_to: string | null };
export type TaskSummary = Pick<Task, 'id' | 'object_id' | 'title' | 'assigned_to'>;
export type Transfer = { id: string; task_id: string; task_title_snapshot: string; responsibility_type: 'manager' | 'executor'; from_user_id: string; to_user_id: string; status: string; created_at: string };
export type Comment = { id: string; author_name: string; content: string; created_at: string };
export type History = { id: string; actor_name: string; event_type: string; old_status: string | null; new_status: string | null; details: Record<string, unknown>; created_at: string };

export async function rows<T>(table: string, column?: string, value?: string, page?: number): Promise<T[]> {
  const result: T[] = [];
  const size = page === undefined ? 500 : 21;
  let offset = page === undefined ? 0 : page * 20;
  for (;;) {
    let query = supabase.from(table).select('*').order('id').range(offset, offset + size - 1);
    if (column && value) query = query.eq(column, value);
    const { data, error } = await query;
    if (error) throw error;
    result.push(...((data || []) as T[]));
    if (page !== undefined || !data || data.length < size) return result;
    offset += size;
  }
}
export async function taskPage(profile: Profile, completed: boolean, page: number): Promise<Task[]> {
  let query = supabase.from('tasks').select('*');
  if (profile.role === 'manager') query = query.eq('responsible_manager_id', profile.id);
  if (profile.role === 'executor') query = query.eq('assigned_to', profile.id);
  query = completed ? query.in('status', ['accepted', 'closed']) : query.not('status', 'in', '(accepted,closed)');
  const { data, error } = await query.order('id').range(page * 20, page * 20 + 20);
  if (error) throw error;
  return (data || []) as Task[];
}
export async function objectTaskSummaries(objectId: string): Promise<TaskSummary[]> {
  const result: TaskSummary[] = [];
  let offset = 0;
  for (;;) {
    const { data, error } = await supabase.rpc('get_object_task_summaries', { p_object_id: objectId })
      .order('id').range(offset, offset + 499);
    if (error) throw error;
    result.push(...((data || []) as TaskSummary[]));
    if (!data || data.length < 500) return result;
    offset += 500;
  }
}
export async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  return data;
}
const hints: Record<string, string> = {
  object_forbidden: 'Объект недоступен или действие разрешено только его создателю.',
  object_has_open_tasks: 'Изменить объект можно только после завершения всех его задач.',
  object_has_tasks: 'Нельзя удалить объект, в котором есть задачи.',
  task_forbidden: 'Вы больше не отвечаете за эту задачу.',
  chat_forbidden: 'Переписка этой задачи недоступна.',
  pending_transfers: 'Сначала завершите ожидающие передачи сотрудника.',
  user_has_open_tasks: 'Сначала передайте все незавершённые задачи сотрудника и дождитесь принятия.',
  content_edit_forbidden: 'Содержание задачи нельзя изменить в текущем состоянии.',
  transfer_forbidden: 'Предложение уже обработано или предназначено другому сотруднику.',
  inactive_profile: 'Профиль отсутствует или деактивирован.',
};
export function errorText(error: unknown): string {
  if (error && typeof error === 'object') {
    if ('hint' in error) {
      const message = hints[String(error.hint)];
      if (message) return message;
    }
    if ('message' in error) return String(error.message);
  }
  return 'Произошла ошибка. Попробуйте ещё раз.';
}
export async function inviteEmployee(input: { email: string; full_name: string; role: string }) {
  const { error } = await supabase.functions.invoke('invite-user', { body: input });
  if (!error) return;
  let payload: { error?: string; user_id?: string } = {};
  try {
    if (error.context instanceof Response) payload = await error.context.json();
  } catch { /* Keep the original network error when the response is not JSON. */ }
  if (payload.error === 'profile_creation_failed') {
    throw new Error(`Приглашение создано, но профиль не сохранён. Передайте администратору ID ${payload.user_id || 'из журнала функции'} для восстановления профиля. Не удаляйте учётную запись.`);
  }
  const messages: Record<string, string> = {
    invitation_failed: 'Не удалось отправить приглашение. Проверьте адрес, существующую учётную запись и настройки почты.',
    admin_required: 'Приглашать сотрудников может только активный администратор.',
    invalid_input: 'Проверьте имя, email и роль сотрудника.',
    server_configuration: 'Функция приглашения не настроена на сервере.',
  };
  throw new Error(messages[payload.error || ''] || errorText(error));
}
