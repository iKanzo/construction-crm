import { useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase, type Profile } from '@/shared/api/supabase';
import { Notice, roles, useAction, value } from '@/shared/lib/crm';

type Context = { profile: Profile; session: Session };

export function ProfilePage({ profile, session }: Context) { const action = useAction(); const [message, setMessage] = useState(''); return <><h1>Профиль</h1><section className="panel"><p>{profile.full_name}</p><p>{roles[profile.role]}</p><p>{session.user.email}</p><button onClick={() => void supabase.auth.signOut()}>Выйти</button></section><form className="panel" onSubmit={e => { e.preventDefault(); const form = e.currentTarget; const f = new FormData(form); void action.run(async () => { const { error } = await supabase.auth.updateUser({ password: value(f, 'password') }); if (error) throw error; }, () => { form.reset(); setMessage('Пароль изменён.'); }); }}><h2>Сменить пароль</h2><label>Новый пароль<input name="password" type="password" minLength={6} required autoComplete="new-password" /></label><Notice error={action.error} />{message && <p>{message}</p>}<button disabled={action.busy}>Сохранить</button></form></>; }
