import { useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { inviteEmployee, rpc, type Profile } from '@/shared/api/supabase';
import { buttonAction, Field, Loading, Notice, roles, useAction, useRows, value } from '@/shared/lib/crm';

export function UsersPage({ profile }: { profile: Profile }) {
  const profiles = useRows<Profile>('profiles', undefined, undefined, profile.role === 'admin', true);
  const action = useAction();
  const [message, setMessage] = useState('');
  if (profile.role !== 'admin') return <Navigate to="/" replace />;
  return <><h1>Сотрудники</h1><p>Перед деактивацией передайте все незавершённые задачи и дождитесь принятия. <Link to="/my-tasks">Открыть задачи</Link></p><form className="panel form-grid" onSubmit={e => {
    e.preventDefault(); const form = e.currentTarget; const f = new FormData(form); setMessage('');
    void action.run(() => inviteEmployee({ email: value(f, 'email'), full_name: value(f, 'full_name'), role: value(f, 'role') }), () => { form.reset(); setMessage('Приглашение отправлено.'); });
  }}><h2>Пригласить сотрудника</h2><Field name="full_name" label="Имя" required maxLength={200} /><label>Email<input name="email" type="email" required maxLength={254} /></label><label>Роль<select name="role"><option value="manager">Менеджер</option><option value="executor">Исполнитель</option></select></label><button disabled={action.busy}>Пригласить</button>{message && <p role="status">{message}</p>}</form><Notice error={action.error} /><Loading loading={profiles.isLoading} error={profiles.error} /><div className="list">{profiles.data?.map(p => <article className="card" key={p.id}><strong>{p.full_name}</strong><span>{roles[p.role]} · {p.is_active ? 'Активен' : 'Деактивирован'}</span>{p.role !== 'admin' && p.is_active && buttonAction('Деактивировать', () => {
    setMessage(''); if (window.confirm(`Деактивировать ${p.full_name}?`)) void action.run(() => rpc('deactivate_user', { p_user_id: p.id }));
  }, action.busy)}</article>)}</div></>;
}
