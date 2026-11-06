import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ObjectForm } from '@/features/object-form';
import { TaskForm } from '@/features/task-form';

const object = { title: 'Дом', description: '', address: 'Адрес', customer_name: 'Заказчик', customer_phone: '12345' };
const executors = [
  { id: 'one', full_name: 'Исполнитель', role: 'executor', is_active: true },
  { id: 'two', full_name: 'Неактивный', role: 'executor', is_active: false },
  { id: 'three', full_name: 'Менеджер', role: 'manager', is_active: true },
];

describe('переиспользуемые формы', () => {
  it('проверяет обязательные поля и длину телефона объекта', async () => {
    const submit = vi.fn(); const user = userEvent.setup();
    render(<ObjectForm onSubmit={submit} onCancel={vi.fn()} />);
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(await screen.findAllByRole('alert')).toHaveLength(4);
    expect(submit).not.toHaveBeenCalled();
    await user.type(screen.getByLabelText('Название'), 'Дом');
    await user.type(screen.getByLabelText('Адрес'), 'Адрес');
    await user.type(screen.getByLabelText('Заказчик'), 'Имя');
    await user.type(screen.getByLabelText('Телефон заказчика'), '1234');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(submit).not.toHaveBeenCalled();
    expect(screen.getByLabelText('Телефон заказчика')).toHaveAttribute('aria-invalid', 'true');
  });

  it('считает длину по Unicode-символам, как PostgreSQL', async () => {
    const submit = vi.fn(); const user = userEvent.setup();
    render(<ObjectForm initialValues={object} onSubmit={submit} onCancel={vi.fn()} />);
    fireEvent.change(screen.getByLabelText('Название'), { target: { value: '😀'.repeat(201) } });
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('200');
    expect(submit).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText('Название'), { target: { value: '😀'.repeat(200) } });
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    await waitFor(() => expect(submit).toHaveBeenCalledWith({ ...object, title: '😀'.repeat(200) }));
  });

  it('редактирует объект, нормализует значения и показывает ошибку сервера', async () => {
    const submit = vi.fn().mockRejectedValueOnce(new Error('Нет доступа')); const cancel = vi.fn(); const user = userEvent.setup();
    render(<ObjectForm initialValues={object} onSubmit={submit} onCancel={cancel} />);
    await user.clear(screen.getByLabelText('Название'));
    await user.type(screen.getByLabelText('Название'), ' Дом 2 ');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Нет доступа');
    expect(submit).toHaveBeenCalledWith({ ...object, title: 'Дом 2' });
    await user.click(screen.getByRole('button', { name: 'Отмена' }));
    expect(cancel).toHaveBeenCalledOnce();
  });

  it('создаёт задачу с активным исполнителем или без него', async () => {
    const submit = vi.fn(); const user = userEvent.setup();
    render(<TaskForm mode="create" executors={executors} onSubmit={submit} onCancel={vi.fn()} />);
    expect(screen.queryByRole('option', { name: 'Менеджер' })).not.toBeInTheDocument();
    expect(screen.queryByRole('option', { name: 'Неактивный' })).not.toBeInTheDocument();
    await user.type(screen.getByLabelText('Название'), '  Задача  ');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    await waitFor(() => expect(submit).toHaveBeenCalledWith({ title: 'Задача', description: '', assigned_to: null }));
    await user.selectOptions(screen.getByLabelText('Исполнитель'), 'one');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    await waitFor(() => expect(submit).toHaveBeenLastCalledWith({ title: 'Задача', description: '', assigned_to: 'one' }));
  });

  it('редактирует только содержимое задачи и проверяет длину описания', async () => {
    const submit = vi.fn(); const user = userEvent.setup();
    render(<TaskForm mode="edit" initialValues={{ title: 'Текущая', description: 'Описание' }} onSubmit={submit} onCancel={vi.fn()} />);
    expect(screen.queryByLabelText('Исполнитель')).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('Описание'), { target: { value: 'а'.repeat(10001) } });
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('10000');
    expect(submit).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText('Описание'), { target: { value: 'а'.repeat(10000) } });
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    await waitFor(() => expect(submit).toHaveBeenCalledWith({ title: 'Текущая', description: 'а'.repeat(10000) }));
  });
});
