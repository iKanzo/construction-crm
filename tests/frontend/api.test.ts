import { beforeEach, describe, expect, it, vi } from 'vitest';
import { inviteEmployee, objectTaskSummaries, rows, taskPage, type Profile } from '@/shared/api/supabase';

const mock = vi.hoisted(() => ({ from: vi.fn(), rpc: vi.fn(), invoke: vi.fn() }));
vi.mock('@supabase/supabase-js', () => ({
  createClient: () => ({ from: mock.from, rpc: mock.rpc, functions: { invoke: mock.invoke } }),
}));

beforeEach(() => { vi.resetAllMocks(); });

describe('загрузка данных и ошибки приглашений', () => {
  it('читает краткие задачи через разрешённый RPC и загружает следующие страницы', async () => {
    const summary = { id: 'task-1', object_id: 'object-1', title: 'Задача', assigned_to: null };
    const range = vi.fn().mockResolvedValueOnce({ data: Array.from({ length: 500 }, () => summary), error: null }).mockResolvedValueOnce({ data: [summary], error: null });
    mock.rpc.mockReturnValue({ order: () => ({ range }) });
    const result = await objectTaskSummaries('object-1');
    expect(mock.rpc).toHaveBeenCalledWith('get_object_task_summaries', { p_object_id: 'object-1' });
    expect(mock.from).not.toHaveBeenCalled();
    expect(range.mock.calls).toEqual([[0, 499], [500, 999]]);
    expect(result).toHaveLength(501);
    expect(Object.keys(result[0]!).sort()).toEqual(['assigned_to', 'id', 'object_id', 'title']);
  });

  it('не превращает отказ RPC в пустой список задач', async () => {
    const error = { message: 'Object inaccessible', hint: 'object_forbidden' };
    mock.rpc.mockReturnValue({ order: () => ({ range: async () => ({ data: null, error }) }) });
    await expect(objectTaskSummaries('object-1')).rejects.toBe(error);
  });

  it('загружает весь справочник порциями без ограничения первыми 1000 строками', async () => {
    const range = vi.fn().mockResolvedValueOnce({ data: Array.from({ length: 500 }, () => ({ id: 'profile' })), error: null }).mockResolvedValueOnce({ data: [{ id: 'last' }], error: null });
    mock.from.mockReturnValue({ select: () => ({ order: () => ({ range }) }) });
    expect(await rows('profiles')).toHaveLength(501);
    expect(range.mock.calls).toEqual([[0, 499], [500, 999]]);
  });

  it('ограничивает страницу задач текущей ответственностью и выбранными статусами', async () => {
    const query = { eq: vi.fn(), in: vi.fn(), not: vi.fn(), order: vi.fn(), range: vi.fn().mockResolvedValue({ data: [], error: null }) };
    query.eq.mockReturnValue(query); query.in.mockReturnValue(query); query.not.mockReturnValue(query); query.order.mockReturnValue(query);
    mock.from.mockReturnValue({ select: () => query });
    const profile: Profile = { id: 'executor-1', full_name: 'Исполнитель', role: 'executor', is_active: true };
    await taskPage(profile, false, 1);
    expect(query.eq).toHaveBeenCalledWith('assigned_to', 'executor-1');
    expect(query.not).toHaveBeenCalledWith('status', 'in', '(accepted,closed)');
    expect(query.range).toHaveBeenCalledWith(20, 40);
    await taskPage({ ...profile, role: 'manager' }, true, 0);
    expect(query.eq).toHaveBeenCalledWith('responsible_manager_id', 'executor-1');
    expect(query.in).toHaveBeenCalledWith('status', ['accepted', 'closed']);
  });

  it('показывает ID для восстановления частично созданного приглашения', async () => {
    mock.invoke.mockResolvedValue({ error: { context: new Response(JSON.stringify({ error: 'profile_creation_failed', user_id: 'employee-id' })) } });
    const input = { email: 'employee@example.com', full_name: 'Сотрудник', role: 'manager' };
    await expect(inviteEmployee(input)).rejects.toThrow('ID employee-id');
    expect(mock.invoke).toHaveBeenCalledWith('invite-user', { body: input });
  });

  it('сохраняет сетевую ошибку приглашения при ответе без JSON', async () => {
    mock.invoke.mockResolvedValue({ error: { message: 'Сеть недоступна', context: new Response('unavailable') } });
    await expect(inviteEmployee({ email: 'employee@example.com', full_name: 'Сотрудник', role: 'executor' })).rejects.toThrow('Сеть недоступна');
  });
});
