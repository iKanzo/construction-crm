import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
export const configured = Boolean(url && key);
// Заглушка позволяет показать понятное сообщение об отсутствии конфигурации.
export const supabase = createClient(url || 'http://127.0.0.1:54321', key || 'missing-key');

export type Role = 'admin' | 'manager' | 'executor';
export type Profile = { id: string; full_name: string; role: Role; is_active: boolean };
export type ObjectRow = { id: string; title: string; description: string; address: string; customer_name: string; customer_phone: string; created_by: string };
export type Task = { id: string; object_id: string; title: string; description: string; status: string; created_by: string; responsible_manager_id: string; assigned_to: string | null };
export type Transfer = { id: string; task_id: string; task_title_snapshot: string; responsibility_type: Role; from_user_id: string; to_user_id: string; status: string; created_at: string };
export type Comment = { id: string; author_name: string; content: string; created_at: string };
export type History = { id: string; actor_name: string; event_type: string; old_status: string | null; new_status: string | null; details: Record<string, unknown>; created_at: string };

export async function rows<T>(table: string, column?: string, value?: string, page?: number): Promise<T[]> {
  let query = supabase.from(table).select('*');
  if (column && value) query = query.eq(column, value);
  if (page !== undefined) query = query.order('id').range(page * 20, page * 20 + 20);
  const { data, error } = await query;
  if (error) throw error;
  return (data || []) as T[];
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
export async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  return data;
}
export function errorText(error: unknown): string {
  if (error && typeof error === 'object' && 'message' in error) return String(error.message);
  return 'Произошла ошибка. Попробуйте ещё раз.';
}
