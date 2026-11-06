import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { rows, errorText } from '@/shared/api/supabase';

const statuses: Record<string, string> = { new: 'Новая', in_progress: 'В работе', under_review: 'На проверке', revision: 'На доработке', accepted: 'Принята', closed: 'Закрыта', pending: 'Ожидает ответа', declined: 'Отклонена', cancelled: 'Отменена' };
export const roles: Record<string, string> = { admin: 'Администратор', manager: 'Менеджер', executor: 'Исполнитель' };
export const events: Record<string, string> = { task_created: 'Задача создана', executor_assigned: 'Назначен исполнитель', assignment_declined: 'Отказ от назначения', status_changed: 'Статус изменён', task_closed: 'Задача закрыта', task_updated: 'Задача изменена', transfer_initiated: 'Передача предложена', transfer_accepted: 'Передача принята', transfer_declined: 'Передача отклонена', transfer_cancelled: 'Передача отменена', executor_changed: 'Исполнитель изменён', manager_changed: 'Менеджер изменён' };
export const label = (value: string) => statuses[value] || value;
export const date = (value: string) => new Date(value).toLocaleString('ru-RU');
export function useRows<T>(table: string, column?: string, value?: string, enabled = true, polling = false, page?: number) {
  return useQuery({ queryKey: [table, column, value, page], queryFn: () => rows<T>(table, column, value, page), enabled, refetchInterval: polling ? 5000 : false });
}
export function Pagination({ page, setPage, hasMore }: { page: number; setPage: (page: number) => void; hasMore: boolean }) {
  return <div className="actions"><button type="button" disabled={page === 0} onClick={() => setPage(page - 1)}>Назад</button><span>Страница {page + 1}</span><button type="button" disabled={!hasMore} onClick={() => setPage(page + 1)}>Далее</button></div>;
}
export function useAction() {
  const client = useQueryClient();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const run = async <T,>(fn: () => Promise<T>, success?: (result: T) => void) => {
    setError(''); setBusy(true);
    try { const result = await fn(); await client.invalidateQueries(); success?.(result); } catch (e) { setError(errorText(e)); } finally { setBusy(false); }
  };
  return { error, busy, run };
}
export function Notice({ error }: { error: unknown }) { return error ? <p className="error" role="alert">{typeof error === 'string' ? error : errorText(error)}</p> : null; }
export function Loading({ loading, error }: { loading: boolean; error: unknown }) { return <>{loading && <p>Загрузка…</p>}<Notice error={error} /></>; }
export function Field({ label: text, name, defaultValue = '', required = false, maxLength }: { label: string; name: string; defaultValue?: string; required?: boolean; maxLength?: number }) { return <label>{text}<input name={name} defaultValue={defaultValue} required={required} maxLength={maxLength} /></label>; }
export function value(form: FormData, name: string) { return String(form.get(name) || '').trim(); }
export function buttonAction(text: string, action: () => void, disabled = false) { return <button type="button" disabled={disabled} onClick={action}>{text}</button>; }
