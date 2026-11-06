import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { RouterProvider, createMemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { routes } from '@/app/router/routes';
import type { Profile, Task } from '@/shared/api/supabase';

const mock = vi.hoisted(() => ({
  getSession: vi.fn(), onAuthStateChange: vi.fn(), signInWithPassword: vi.fn(),
  signOut: vi.fn(), resetPasswordForEmail: vi.fn(), updateUser: vi.fn(),
  from: vi.fn(), rows: vi.fn(), rpc: vi.fn(), unsubscribe: vi.fn(),
  objectTaskSummaries: vi.fn(), inviteEmployee: vi.fn(), taskPage: vi.fn(),
  passwordLink: false, authLinkError: '',
}));

vi.mock('@/shared/api/supabase', () => ({
  configured: true,
  get passwordLink() { return mock.passwordLink; },
  get authLinkError() { return mock.authLinkError; },
  objectTaskSummaries: mock.objectTaskSummaries,
  inviteEmployee: mock.inviteEmployee,
  taskPage: mock.taskPage,
  supabase: {
    auth: {
      getSession: mock.getSession, onAuthStateChange: mock.onAuthStateChange,
      signInWithPassword: mock.signInWithPassword, signOut: mock.signOut,
      resetPasswordForEmail: mock.resetPasswordForEmail, updateUser: mock.updateUser,
    },
    from: mock.from,
  },
  rows: mock.rows, rpc: mock.rpc,
  errorText: (error: unknown) => error && typeof error === 'object' && 'message' in error
    ? String(error.message) : 'Произошла ошибка. Попробуйте ещё раз.',
}));

const profiles: Record<'manager' | 'executor' | 'admin', Profile> = {
  manager: { id: 'manager-1', full_name: 'Мария Менеджер', role: 'manager', is_active: true },
  executor: { id: 'executor-1', full_name: 'Иван Исполнитель', role: 'executor', is_active: true },
  admin: { id: 'admin-1', full_name: 'Анна Администратор', role: 'admin', is_active: true },
};
const task: Task = {
  id: 'task-1', object_id: 'object-1', title: 'Установить двери', description: '',
  status: 'new', created_by: 'manager-1', responsible_manager_id: 'manager-1', assigned_to: 'executor-1',
};
const object = { id: 'object-1', title: 'Жилой дом', description: 'Новый корпус', address: 'ул. Лесная, 1', customer_name: 'ООО Строй', customer_phone: '123456789', created_by: 'manager-1' };
let profile: Profile | null;
let session: { user: { id: string; email: string; user_metadata?: Record<string, unknown> } } | null;
let authChange: (event: string, next: typeof session) => void;
let data: Record<string, object[]>;

beforeEach(() => {
  vi.resetAllMocks();
  sessionStorage.clear();
  mock.passwordLink = false; mock.authLinkError = '';
  profile = profiles.manager;
  session = null;
  data = { objects: [], tasks: [], profiles: Object.values(profiles), comments: [], task_history: [], transfers: [] };
  mock.getSession.mockImplementation(async () => ({ data: { session } }));
  mock.onAuthStateChange.mockImplementation((callback) => {
    authChange = callback;
    return { data: { subscription: { unsubscribe: mock.unsubscribe } } };
  });
  mock.from.mockImplementation((table: string) => {
    expect(table).toBe('profiles');
    return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: profile, error: null }) }) }) };
  });
  mock.rows.mockImplementation(async (table: string, column?: string, value?: string) =>
    (data[table] ?? []).filter((row) => !column || (row as Record<string, unknown>)[column] === value));
  mock.objectTaskSummaries.mockImplementation(async (objectId: string) =>
    (data.tasks as Task[]).filter(t => t.object_id === objectId).map(({ id, object_id, title, assigned_to }) => ({ id, object_id, title, assigned_to })));
  mock.taskPage.mockImplementation(async (viewer: Profile, completed: boolean, page: number) =>
    (data.tasks as Task[]).filter(t => (viewer.role === 'admin' || (viewer.role === 'manager' ? t.responsible_manager_id === viewer.id : t.assigned_to === viewer.id)) && completed === ['accepted', 'closed'].includes(t.status)).slice(page * 20, page * 20 + 21));
  mock.rpc.mockResolvedValue(null);
  mock.signInWithPassword.mockResolvedValue({ error: null });
  mock.resetPasswordForEmail.mockResolvedValue({ error: null });
  mock.signOut.mockResolvedValue({ error: null });
  mock.updateUser.mockResolvedValue({ error: null });
  mock.inviteEmployee.mockResolvedValue(undefined);
});

function signedIn(role: keyof typeof profiles) {
  profile = profiles[role];
  session = { user: { id: profile.id, email: `${role}@example.com` } };
}

function renderAt(path: string) {
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 }, mutations: { retry: false } } });
  const view = render(<QueryClientProvider client={client}><RouterProvider router={router} /></QueryClientProvider>);
  return { router, client, ...view };
}

describe('авторизация', () => {
  it('показывает вход без навигации и открывает запрошенную страницу после входа', async () => {
    const user = userEvent.setup();
    renderAt('/my-tasks');
    expect(await screen.findByRole('heading', { name: 'Вход' })).toBeInTheDocument();
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument();
    await user.type(screen.getByLabelText('Email'), 'manager@example.com');
    await user.type(screen.getByLabelText('Пароль'), 'secret123');
    await user.click(screen.getByRole('button', { name: 'Войти' }));
    expect(mock.signInWithPassword).toHaveBeenCalledWith({ email: 'manager@example.com', password: 'secret123' });
    signedIn('manager');
    act(() => authChange('SIGNED_IN', session));
    expect(await screen.findByRole('heading', { name: 'Мои задачи' })).toBeInTheDocument();
  });

  it('показывает ошибку входа и остаётся на форме', async () => {
    mock.signInWithPassword.mockResolvedValue({ error: { message: 'Неверный пароль' } });
    const user = userEvent.setup();
    renderAt('/');
    await user.type(await screen.findByLabelText('Email'), 'manager@example.com');
    await user.type(screen.getByLabelText('Пароль'), 'wrongpass');
    await user.click(screen.getByRole('button', { name: 'Войти' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Неверный пароль');
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument();
  });

  it('передаёт пароль без удаления значимых пробелов', async () => {
    const user = userEvent.setup(); renderAt('/');
    await user.type(await screen.findByLabelText('Email'), 'manager@example.com');
    await user.type(screen.getByLabelText('Пароль'), ' Pass123 ');
    await user.click(screen.getByRole('button', { name: 'Войти' }));
    expect(mock.signInWithPassword).toHaveBeenCalledWith({ email: 'manager@example.com', password: ' Pass123 ' });
  });

  it('отправляет ссылку восстановления пароля', async () => {
    const user = userEvent.setup();
    renderAt('/login');
    await user.click(await screen.findByRole('button', { name: 'Забыли пароль?' }));
    await user.type(screen.getByLabelText('Email'), 'manager@example.com');
    await user.click(screen.getByRole('button', { name: 'Отправить ссылку' }));
    expect(mock.resetPasswordForEmail).toHaveBeenCalledWith('manager@example.com', { redirectTo: window.location.origin });
    expect(await screen.findByText('Если адрес зарегистрирован, инструкция отправлена на почту.')).toBeInTheDocument();
  });

  it('не допускает деактивированного пользователя', async () => {
    signedIn('manager');
    profile = { ...profiles.manager, is_active: false };
    renderAt('/');
    expect(await screen.findByRole('heading', { name: 'Нет доступа' })).toBeInTheDocument();
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument();
  });

  it('выходит из аккаунта и очищает данные при событии SIGNED_OUT', async () => {
    signedIn('manager');
    const user = userEvent.setup();
    const { client } = renderAt('/profile');
    await user.click(await screen.findByRole('button', { name: 'Выйти' }));
    expect(mock.signOut).toHaveBeenCalled();
    act(() => authChange('SIGNED_OUT', null));
    expect(await screen.findByRole('heading', { name: 'Вход' })).toBeInTheDocument();
    expect(client.getQueryData(['profile', 'manager-1'])).toBeUndefined();
  });
});

describe('инициализация и установка пароля', () => {
  it('показывает ошибку getSession вместо бесконечной загрузки', async () => {
    mock.getSession.mockRejectedValue(new Error('Сессия недоступна'));
    renderAt('/');
    expect(await screen.findByRole('heading', { name: 'Вход' })).toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('Сессия недоступна');
  });

  it('не восстанавливает устаревшую сессию после выхода', async () => {
    signedIn('manager');
    const oldSession = session;
    let resolve!: (result: { data: { session: typeof session } }) => void;
    mock.getSession.mockReturnValue(new Promise(done => { resolve = done; }));
    const { client } = renderAt('/');
    await waitFor(() => expect(mock.onAuthStateChange).toHaveBeenCalled());
    client.setQueryData(['private-data'], ['stale']);
    act(() => authChange('SIGNED_OUT', null));
    await act(async () => { resolve({ data: { session: oldSession } }); });
    expect(await screen.findByRole('heading', { name: 'Вход' })).toBeInTheDocument();
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument();
    expect(client.getQueryData(['private-data'])).toBeUndefined();
  });

  it('сохраняет ошибку ссылки при INITIAL_SESSION без пользователя', async () => {
    mock.authLinkError = 'Ссылка истекла';
    renderAt('/');
    await screen.findByRole('heading', { name: 'Вход' });
    act(() => authChange('INITIAL_SESSION', null));
    expect(screen.getByRole('alert')).toHaveTextContent('Ссылка истекла');
  });

  it.each(['invite', 'recovery'])('устанавливает пароль по ссылке %s и открывает приложение', async kind => {
    signedIn('manager');
    if (kind === 'invite') session!.user.user_metadata = { password_setup_required: true };
    const user = userEvent.setup();
    renderAt('/');
    if (kind === 'recovery') {
      await screen.findByRole('heading', { name: 'Объекты' });
      act(() => authChange('PASSWORD_RECOVERY', session));
    }
    expect(await screen.findByRole('heading', { name: 'Установка пароля' })).toBeInTheDocument();
    await user.type(screen.getByLabelText('Новый пароль'), 'NewPass123');
    await user.type(screen.getByLabelText('Повторите пароль'), 'Different123');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(screen.getByRole('alert')).toHaveTextContent('Пароли не совпадают');
    expect(mock.updateUser).not.toHaveBeenCalled();
    await user.clear(screen.getByLabelText('Повторите пароль'));
    await user.type(screen.getByLabelText('Повторите пароль'), 'NewPass123');
    mock.updateUser.mockImplementation(async () => {
      session!.user.user_metadata = { password_setup_required: false };
      authChange('USER_UPDATED', session);
      return { error: null };
    });
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    await waitFor(() => expect(mock.updateUser).toHaveBeenCalledWith({ password: 'NewPass123', data: { password_setup_required: false } }));
    expect(await screen.findByRole('heading', { name: 'Объекты' })).toBeInTheDocument();
    expect(sessionStorage.getItem('crm-password-setup')).toBeNull();
    act(() => authChange('TOKEN_REFRESHED', session));
    expect(screen.queryByRole('heading', { name: 'Установка пароля' })).not.toBeInTheDocument();
  });

  it('показывает серверную ошибку сохранения пароля и позволяет повторить', async () => {
    signedIn('manager'); mock.passwordLink = true;
    mock.updateUser.mockResolvedValueOnce({ error: { message: 'Повторите позже' } });
    const user = userEvent.setup(); renderAt('/');
    await user.type(await screen.findByLabelText('Новый пароль'), 'NewPass123');
    await user.type(screen.getByLabelText('Повторите пароль'), 'NewPass123');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Повторите позже');
    expect(screen.getByRole('heading', { name: 'Установка пароля' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(await screen.findByRole('heading', { name: 'Объекты' })).toBeInTheDocument();
  });
});

describe('объект и краткие задачи', () => {
  it('показывает полную ссылку своей задачи и только название/исполнителя чужой', async () => {
    signedIn('manager'); data.objects = [object];
    data.tasks = [task, { ...task, id: 'foreign', title: 'Чужая задача', description: 'Скрытое описание', status: 'under_review', responsible_manager_id: 'manager-2' }];
    renderAt('/objects/object-1');
    expect(await screen.findByRole('link', { name: /Установить двери/ })).toHaveAttribute('href', '/tasks/task-1');
    const card = (await screen.findByText('Чужая задача')).closest('article')!;
    expect(within(card).getByText('Исполнитель: Иван Исполнитель')).toBeInTheDocument();
    expect(within(card).queryByRole('link')).not.toBeInTheDocument();
    expect(within(card).queryByText('На проверке')).not.toBeInTheDocument();
    expect(screen.queryByText('Скрытое описание')).not.toBeInTheDocument();
    expect(mock.objectTaskSummaries).toHaveBeenCalledWith('object-1');
  });

  it('исполнитель видит только свои задачи и не вызывает RPC краткого списка', async () => {
    signedIn('executor'); data.objects = [object];
    data.tasks = [task, { ...task, id: 'other', title: 'Задача другого исполнителя', assigned_to: 'executor-2' }];
    renderAt('/objects/object-1');
    expect(await screen.findByRole('link', { name: /Установить двери/ })).toBeInTheDocument();
    expect(screen.queryByText('Задача другого исполнителя')).not.toBeInTheDocument();
    expect(mock.objectTaskSummaries).not.toHaveBeenCalled();
    expect(screen.queryByRole('button', { name: 'Создать задачу' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Изменить' })).not.toBeInTheDocument();
  });

  it('удаляет пустой объект создателя и возвращается к списку', async () => {
    signedIn('manager'); data.objects = [object];
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    mock.rpc.mockImplementation(async name => { if (name === 'delete_object') data.objects = []; return null; });
    const user = userEvent.setup(); const { router } = renderAt('/objects/object-1');
    const remove = await screen.findByRole('button', { name: 'Удалить' });
    await waitFor(() => expect(remove).toBeEnabled()); await user.click(remove);
    expect(await screen.findByRole('heading', { name: 'Объекты' })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/');
    expect(mock.rpc).toHaveBeenCalledWith('delete_object', { p_object_id: 'object-1' });
  });

  it('не создатель не редактирует объект, но создаёт задачу с исполнителем', async () => {
    signedIn('manager'); data.objects = [{ ...object, created_by: 'manager-2' }];
    const user = userEvent.setup(); renderAt('/objects/object-1');
    await screen.findByRole('heading', { name: object.title });
    expect(screen.queryByRole('button', { name: 'Изменить' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Удалить' })).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Создать задачу' }));
    await user.type(await screen.findByLabelText('Название'), 'Новая задача');
    await user.selectOptions(screen.getByLabelText('Исполнитель'), 'executor-1');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('create_task', { p_object_id: 'object-1', p_title: 'Новая задача', p_description: '', p_assigned_to: 'executor-1' }));
  });

  it('сохраняет изменения объекта создателем и показывает отказ сервера', async () => {
    signedIn('manager'); data.objects = [object];
    mock.rpc.mockRejectedValueOnce(new Error('Не все задачи завершены'));
    const user = userEvent.setup(); renderAt('/objects/object-1');
    const edit = await screen.findByRole('button', { name: 'Изменить' });
    await waitFor(() => expect(edit).toBeEnabled()); await user.click(edit);
    await user.clear(screen.getByLabelText('Название')); await user.type(screen.getByLabelText('Название'), 'Изменённый дом');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Не все задачи завершены');
    expect(mock.rpc).toHaveBeenCalledWith('update_object', expect.objectContaining({ p_object_id: 'object-1', p_title: 'Изменённый дом' }));
  });
});

describe('задачи, чат и передачи', () => {
  it('редактирует содержание на доработке, показывает историю и закрывает новую неназначенную задачу', async () => {
    signedIn('manager'); data.tasks = [{ ...task, status: 'revision' }];
    data.task_history = [{ id: 'history-1', task_id: task.id, actor_name: 'Мария Менеджер', event_type: 'status_changed', old_status: 'under_review', new_status: 'revision', details: {}, created_at: '2026-11-07T10:00:00Z' }];
    const user = userEvent.setup(); const { client } = renderAt('/tasks/task-1');
    await user.click(await screen.findByRole('button', { name: 'Изменить' }));
    expect(await screen.findByText('Статус изменён')).toBeInTheDocument();
    await user.type(screen.getByLabelText('Описание'), 'Исправить крепления');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('update_task', { p_task_id: task.id, p_title: task.title, p_description: 'Исправить крепления' }));
    data.tasks = [{ ...task, status: 'new', assigned_to: null }];
    await act(async () => { await client.invalidateQueries(); });
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    await user.click(await screen.findByRole('button', { name: 'Закрыть' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('transition_task', { p_task_id: task.id, p_new_status: 'closed', p_comment: null }));
  });

  it('назначает исполнителя, обновляет карточку и сохраняет сообщение в чате', async () => {
    signedIn('manager'); data.tasks = [{ ...task, assigned_to: null }];
    mock.rpc.mockImplementation(async (name, args) => {
      if (name === 'assign_executor') data.tasks = [{ ...task, assigned_to: args.p_executor_id }];
      if (name === 'add_comment') data.comments = [{ id: 'comment-1', task_id: task.id, author_name: 'Мария Менеджер', content: args.p_content, created_at: '2026-11-07T10:00:00Z' }];
      return null;
    });
    const user = userEvent.setup(); renderAt('/tasks/task-1');
    await screen.findByRole('option', { name: profiles.executor.full_name });
    await user.selectOptions(screen.getByLabelText('Назначить исполнителя'), 'executor-1');
    await user.click(screen.getByRole('button', { name: 'Назначить' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('assign_executor', { p_task_id: 'task-1', p_executor_id: 'executor-1' }));
    await waitFor(() => expect(screen.queryByLabelText('Назначить исполнителя')).not.toBeInTheDocument());
    await user.type(screen.getByLabelText('Сообщение'), '  Двери доставлены  ');
    await user.click(screen.getByRole('button', { name: 'Отправить' }));
    expect(await screen.findByText('Двери доставлены')).toBeInTheDocument();
    expect(mock.rpc).toHaveBeenCalledWith('add_comment', { p_task_id: 'task-1', p_content: 'Двери доставлены' });
    expect(screen.getByLabelText('Сообщение')).toHaveValue('');
  });

  it('отказ исполнителя убирает доступ к задаче после обновления', async () => {
    signedIn('executor'); data.tasks = [task];
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    mock.rpc.mockImplementation(async name => { if (name === 'decline_assignment') data.tasks = []; return null; });
    const user = userEvent.setup(); renderAt('/tasks/task-1');
    await user.click(await screen.findByRole('button', { name: 'Отказаться от назначения' }));
    expect(await screen.findByText('Задача не найдена или недоступна.')).toBeInTheDocument();
    expect(mock.rpc).toHaveBeenCalledWith('decline_assignment', { p_task_id: 'task-1' });
    expect(screen.queryByRole('heading', { name: 'Чат' })).not.toBeInTheDocument();
  });

  it('скрывает детали, историю и чат, если текущий менеджер изменился', async () => {
    signedIn('manager'); data.tasks = [{ ...task, description: 'Полное описание' }];
    const { client } = renderAt('/tasks/task-1');
    expect(await screen.findByText('Полное описание')).toBeInTheDocument();
    data.tasks = [{ ...task, responsible_manager_id: 'manager-2' }];
    await act(async () => { await client.invalidateQueries(); });
    expect(await screen.findByText('Задача не найдена или недоступна.')).toBeInTheDocument();
    expect(screen.queryByText('Полное описание')).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'История' })).not.toBeInTheDocument();
    expect(screen.queryByLabelText('Сообщение')).not.toBeInTheDocument();
  });

  it.each(['in_progress', 'under_review', 'accepted'])('предлагает нужный переход из %s', async status => {
    signedIn(status === 'under_review' ? 'manager' : 'executor'); data.tasks = [{ ...task, status }];
    const user = userEvent.setup(); renderAt('/tasks/task-1');
    if (status === 'accepted') {
      await screen.findByRole('heading', { name: task.title });
      expect(screen.queryByRole('button', { name: 'Взять в работу' })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Отправить на проверку' })).not.toBeInTheDocument();
      expect(screen.getByRole('heading', { name: 'Чат' })).toBeInTheDocument();
    } else {
      await user.click(await screen.findByRole('button', { name: status === 'in_progress' ? 'Отправить на проверку' : 'Принять' }));
      await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('transition_task', { p_task_id: task.id, p_new_status: status === 'in_progress' ? 'under_review' : 'accepted', p_comment: null }));
    }
  });

  it('показывает завершённые задачи и переключает страницы активных', async () => {
    signedIn('manager');
    data.tasks = [...Array.from({ length: 21 }, (_, i) => ({ ...task, id: `task-${i}`, title: `Задача ${i}` })), { ...task, id: 'done', title: 'Завершённая задача', status: 'accepted' }];
    const user = userEvent.setup(); renderAt('/my-tasks');
    await screen.findByRole('link', { name: /Задача 0 / });
    expect(screen.queryByRole('link', { name: /Задача 20 / })).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Далее' }));
    expect(await screen.findByRole('link', { name: /Задача 20 / })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Завершённые' }));
    expect(await screen.findByRole('link', { name: /Завершённая задача/ })).toBeInTheDocument();
    expect(screen.getByText('Страница 1')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /Задача 20 / })).not.toBeInTheDocument();
  });

  it.each(['manager', 'executor'])('администратор предлагает передачу роли %s', async role => {
    signedIn('admin'); data.tasks = [task];
    data.profiles = [...(data.profiles || []), { id: 'recipient', full_name: 'Получатель', role, is_active: true }];
    const user = userEvent.setup(); renderAt('/tasks/task-1');
    await user.click(await screen.findByRole('button', { name: 'Предложить передачу' }));
    expect(screen.queryByRole('button', { name: 'Принять' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Изменить' })).not.toBeInTheDocument();
    await user.selectOptions(screen.getByLabelText('Ответственность'), role);
    await user.selectOptions(screen.getByLabelText('Получатель'), 'recipient');
    await user.click(screen.getByRole('button', { name: 'Предложить' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('create_transfer', { p_task_id: task.id, p_responsibility_type: role, p_to_user_id: 'recipient' }));
  });

  it.each([true, false])('получатель отвечает на передачу: %s', async accept => {
    signedIn('manager');
    data.transfers = [{ id: 'transfer-1', task_id: 'hidden', task_title_snapshot: 'Предложенная задача', responsibility_type: 'manager', from_user_id: 'manager-2', to_user_id: 'manager-1', status: 'pending', created_at: '2026-11-07T10:00:00Z' }];
    const user = userEvent.setup(); renderAt('/transfers');
    await user.click(await screen.findByRole('button', { name: accept ? 'Принять' : 'Отклонить' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('respond_to_transfer', { p_transfer_id: 'transfer-1', p_accept: accept }));
    expect(screen.queryByRole('link', { name: 'Предложенная задача' })).not.toBeInTheDocument();
  });

  it('показывает ошибку приглашения и запрет деактивации с открытыми задачами', async () => {
    signedIn('admin');
    mock.inviteEmployee.mockRejectedValue(new Error('Профиль не сохранён: employee-id'));
    mock.rpc.mockRejectedValue(new Error('Сначала передайте задачи'));
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    const user = userEvent.setup(); renderAt('/users');
    await user.type(await screen.findByLabelText('Имя'), 'Сотрудник');
    await user.type(screen.getByLabelText('Email'), 'new@example.com');
    await user.click(screen.getByRole('button', { name: 'Пригласить' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('employee-id');
    expect(screen.queryByText('Приглашение отправлено.')).not.toBeInTheDocument();
    const card = screen.getByText(profiles.executor.full_name).closest('article')!;
    await user.click(within(card).getByRole('button', { name: 'Деактивировать' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Сначала передайте задачи');
    expect(mock.rpc).toHaveBeenCalledWith('deactivate_user', { p_user_id: 'executor-1' });
  });
});

describe('маршруты и роли', () => {
  it('открывает объекты, навигацию и перенаправляет неизвестный путь', async () => {
    signedIn('manager');
    const user = userEvent.setup();
    const { router } = renderAt('/no-such-page');
    expect(await screen.findByRole('heading', { name: 'Объекты' })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/');
    await user.click(screen.getByRole('link', { name: 'Мои задачи' }));
    expect(await screen.findByRole('heading', { name: 'Мои задачи' })).toBeInTheDocument();
  });

  it('менеджер создаёт объект с заполненными данными', async () => {
    signedIn('manager');
    const objectId = 'f702e9be-f621-4567-a555-4588927a56da';
    mock.rpc.mockImplementation(async (name: string) => {
      if (name === 'create_object') {
        data.objects = [{ id: objectId, title: 'Жилой дом', description: 'Новый корпус', address: 'ул. Лесная, 1', customer_name: 'ООО Строй', customer_phone: '123456789', created_by: 'manager-1' }];
        return objectId;
      }
      return null;
    });
    const user = userEvent.setup();
    const { router } = renderAt('/');
    await user.click(await screen.findByRole('button', { name: 'Создать объект' }));
    await user.type(screen.getByLabelText('Название'), 'Жилой дом');
    await user.type(screen.getByLabelText('Описание'), 'Новый корпус');
    await user.type(screen.getByLabelText('Адрес'), 'ул. Лесная, 1');
    await user.type(screen.getByLabelText('Заказчик'), 'ООО Строй');
    await user.type(screen.getByLabelText('Телефон заказчика'), '123456789');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('create_object', {
      p_title: 'Жилой дом', p_description: 'Новый корпус', p_address: 'ул. Лесная, 1',
      p_customer_name: 'ООО Строй', p_customer_phone: '123456789',
    }));
    expect(await screen.findByRole('heading', { name: 'Жилой дом' })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe(`/objects/${objectId}`);
    expect(screen.queryByRole('heading', { name: 'Новый объект' })).not.toBeInTheDocument();
  });

  it('показывает снимок названия передачи и ссылается только на доступную задачу', async () => {
    signedIn('manager');
    data.tasks = [task];
    data.transfers = [
      { id: 'transfer-1', task_id: task.id, task_title_snapshot: 'Название на момент передачи', responsibility_type: 'manager', from_user_id: 'admin-1', to_user_id: 'manager-1', status: 'pending', created_at: '2025-01-02T00:00:00Z' },
      { id: 'transfer-2', task_id: 'hidden-task', task_title_snapshot: 'Недоступная задача из снимка', responsibility_type: 'manager', from_user_id: 'admin-1', to_user_id: 'manager-1', status: 'pending', created_at: '2025-01-01T00:00:00Z' },
    ];
    renderAt('/transfers');
    const visible = await screen.findByRole('link', { name: 'Название на момент передачи' });
    expect(visible).toHaveAttribute('href', '/tasks/task-1');
    expect(screen.queryByText(task.title)).not.toBeInTheDocument();
    const hidden = screen.getByText('Недоступная задача из снимка');
    const card = hidden.closest('article');
    expect(card).not.toBeNull();
    expect(within(card!).queryByRole('link')).not.toBeInTheDocument();
    expect(within(card!).getByRole('button', { name: 'Принять' })).toBeInTheDocument();
  });

  it('исполнитель берёт назначенную задачу в работу, но не управляет объектами', async () => {
    signedIn('executor');
    data.tasks = [task];
    const user = userEvent.setup();
    const { router } = renderAt('/');
    expect(await screen.findByRole('heading', { name: 'Объекты' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Создать объект' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Сотрудники' })).not.toBeInTheDocument();
    await user.click(screen.getByRole('link', { name: 'Мои задачи' }));
    await user.click(await screen.findByRole('link', { name: /Установить двери/ }));
    expect(router.state.location.pathname).toBe('/tasks/task-1');
    await user.click(await screen.findByRole('button', { name: 'Взять в работу' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('transition_task', {
      p_task_id: 'task-1', p_new_status: 'in_progress', p_comment: null,
    }));
    expect(screen.queryByRole('button', { name: 'Принять' })).not.toBeInTheDocument();
  });

  it('менеджер отправляет задачу на доработку с комментарием', async () => {
    signedIn('manager');
    data.tasks = [{ ...task, status: 'under_review' }];
    const user = userEvent.setup();
    renderAt('/tasks/task-1');
    await user.click(await screen.findByRole('button', { name: 'На доработку' }));
    await user.type(screen.getByLabelText('Комментарий для доработки'), 'Исправить крепление');
    await user.click(screen.getByRole('button', { name: 'Отправить на доработку' }));
    await waitFor(() => expect(mock.rpc).toHaveBeenCalledWith('transition_task', {
      p_task_id: 'task-1', p_new_status: 'revision', p_comment: 'Исправить крепление',
    }));
  });

  it('только администратор может открыть сотрудников и пригласить исполнителя', async () => {
    signedIn('admin');
    const user = userEvent.setup();
    renderAt('/');
    await user.click(await screen.findByRole('link', { name: 'Сотрудники' }));
    expect(await screen.findByRole('heading', { name: 'Сотрудники' })).toBeInTheDocument();
    await user.type(screen.getByLabelText('Имя'), 'Новый сотрудник');
    await user.type(screen.getByLabelText('Email'), 'new@example.com');
    await user.selectOptions(screen.getByLabelText('Роль'), 'executor');
    await user.click(screen.getByRole('button', { name: 'Пригласить' }));
    await waitFor(() => expect(mock.inviteEmployee).toHaveBeenCalledWith({ email: 'new@example.com', full_name: 'Новый сотрудник', role: 'executor' }));
    expect(await screen.findByText('Приглашение отправлено.')).toBeInTheDocument();
  });

  it('перенаправляет не администратора с прямого адреса сотрудников', async () => {
    signedIn('executor');
    const { router } = renderAt('/users');
    expect(await screen.findByRole('heading', { name: 'Объекты' })).toBeInTheDocument();
    expect(router.state.location.pathname).toBe('/');
    expect(screen.queryByRole('heading', { name: 'Сотрудники' })).not.toBeInTheDocument();
  });
});
