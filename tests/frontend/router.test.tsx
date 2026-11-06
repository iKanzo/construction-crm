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
  from: vi.fn(), invoke: vi.fn(), rows: vi.fn(), rpc: vi.fn(), unsubscribe: vi.fn(),
}));

vi.mock('@/shared/api/supabase', () => ({
  configured: true,
  supabase: {
    auth: {
      getSession: mock.getSession, onAuthStateChange: mock.onAuthStateChange,
      signInWithPassword: mock.signInWithPassword, signOut: mock.signOut,
      resetPasswordForEmail: mock.resetPasswordForEmail, updateUser: mock.updateUser,
    },
    from: mock.from, functions: { invoke: mock.invoke },
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
let profile: Profile | null;
let session: { user: { id: string; email: string } } | null;
let authChange: (event: string, next: typeof session) => void;
let data: Record<string, object[]>;

beforeEach(() => {
  vi.resetAllMocks();
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
  mock.rpc.mockResolvedValue(null);
  mock.signInWithPassword.mockResolvedValue({ error: null });
  mock.resetPasswordForEmail.mockResolvedValue({ error: null });
  mock.invoke.mockResolvedValue({ error: null });
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
    await waitFor(() => expect(mock.invoke).toHaveBeenCalledWith('invite-user', {
      body: { email: 'new@example.com', full_name: 'Новый сотрудник', role: 'executor' },
    }));
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
