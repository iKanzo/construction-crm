import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { rpc, type ObjectRow, type Profile, type Task, type TaskSummary } from '@/shared/api/supabase';
import { ObjectForm as ValidatedObjectForm } from '@/features/object-form';
import { TaskForm as ValidatedTaskForm } from '@/features/task-form';
import { buttonAction, label, Loading, Notice, useAction, useRows, value } from '@/shared/lib/crm';

export function ObjectForm({ object, done }: { object?: ObjectRow; done: (id?: string) => void }) {
  const client = useQueryClient();
  return <ValidatedObjectForm initialValues={object} onCancel={() => done()} onSubmit={async values => {
    const args = { p_title: values.title, p_description: values.description, p_address: values.address, p_customer_name: values.customer_name, p_customer_phone: values.customer_phone };
    const id = await rpc(object ? 'update_object' : 'create_object', object ? { p_object_id: object.id, ...args } : args);
    await client.invalidateQueries();
    done(object ? undefined : id);
  }} />;
}
export function TaskList({ tasks }: { tasks: Task[] }) {
  return <div className="list">{tasks.map(t => <Link className="card" key={t.id} to={`/tasks/${t.id}`}><strong>{t.title}</strong><span className="badge">{label(t.status)}</span></Link>)}{tasks.length === 0 && <p>Задач пока нет.</p>}</div>;
}
export function ObjectTaskList({ summaries, fullTasks, profiles }: { summaries: TaskSummary[]; fullTasks: Task[]; profiles: Profile[] }) {
  return <div className="list">{summaries.map(summary => {
    const full = fullTasks.find(task => task.id === summary.id);
    const executor = summary.assigned_to ? profiles.find(p => p.id === summary.assigned_to)?.full_name || summary.assigned_to : 'Не назначен';
    const content = <><strong>{summary.title}</strong><span>Исполнитель: {executor}</span>{full && <span className="badge">{label(full.status)}</span>}</>;
    return full ? <Link className="card" key={summary.id} to={`/tasks/${summary.id}`}>{content}</Link> : <article className="card" key={summary.id}>{content}</article>;
  })}{summaries.length === 0 && <p>Задач пока нет.</p>}</div>;
}
export function TaskForm({ objectId, task, done }: { objectId?: string; task?: Task; done: () => void }) {
  const client = useQueryClient();
  const profiles = useRows<Profile>('profiles', undefined, undefined, !task);
  if (task) return <ValidatedTaskForm mode="edit" initialValues={task} onCancel={done} onSubmit={async values => {
    await rpc('update_task', { p_task_id: task.id, p_title: values.title, p_description: values.description });
    await client.invalidateQueries(); done();
  }} />;
  return <><Loading loading={profiles.isLoading} error={profiles.error} />{profiles.data && <ValidatedTaskForm mode="create" executors={profiles.data} onCancel={done} onSubmit={async values => {
    await rpc('create_task', { p_object_id: objectId, p_title: values.title, p_description: values.description, p_assigned_to: values.assigned_to });
    await client.invalidateQueries(); done();
  }} />}</>;
}
export function TransferForm({ task, profiles, done }: { task: Task; profiles: Profile[]; done: () => void }) {
  const action = useAction();
  const [type, setType] = useState<'manager' | 'executor'>('manager');
  return <form className="panel" onSubmit={e => {
    e.preventDefault(); const f = new FormData(e.currentTarget);
    void action.run(() => rpc('create_transfer', { p_task_id: task.id, p_responsibility_type: type, p_to_user_id: value(f, 'recipient') }), done);
  }}><h2>Предложить передачу</h2><label>Ответственность<select value={type} onChange={e => setType(e.target.value as 'manager' | 'executor')}><option value="manager">Менеджер</option>{task.assigned_to && <option value="executor">Исполнитель</option>}</select></label><label>Получатель<select key={type} name="recipient" required defaultValue=""><option value="" disabled>Выберите сотрудника</option>{profiles.filter(p => p.role === type && p.is_active && p.id !== (type === 'manager' ? task.responsible_manager_id : task.assigned_to)).map(p => <option key={p.id} value={p.id}>{p.full_name}</option>)}</select></label><Notice error={action.error} /><div className="actions"><button disabled={action.busy}>Предложить</button>{buttonAction('Отмена', done)}</div></form>;
}
