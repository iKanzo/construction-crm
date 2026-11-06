import { useState, type FormEvent } from 'react';
import { supabase } from '@/shared/api/supabase';
import { Notice, useAction, value } from '@/shared/lib/crm';

export function LoginPage() {
  const [reset, setReset] = useState(false); const [message, setMessage] = useState(''); const action = useAction();
  function submit(e: FormEvent<HTMLFormElement>) { e.preventDefault(); const f = new FormData(e.currentTarget); void action.run(async () => { if (reset) { const { error } = await supabase.auth.resetPasswordForEmail(value(f, 'email'), { redirectTo: window.location.origin }); if (error) throw error; } else { const { error } = await supabase.auth.signInWithPassword({ email: value(f, 'email'), password: value(f, 'password') }); if (error) throw error; } }, () => { if (reset) setMessage('Если адрес зарегистрирован, инструкция отправлена на почту.'); }); }
  return <main className="auth"><h1>Construction CRM</h1><h2>{reset ? 'Восстановление пароля' : 'Вход'}</h2><form onSubmit={submit}><label>Email<input name="email" type="email" required autoComplete="email" /></label>{!reset && <label>Пароль<input name="password" type="password" required autoComplete="current-password" /></label>}<Notice error={action.error} />{message && <p>{message}</p>}<button disabled={action.busy}>{reset ? 'Отправить ссылку' : 'Войти'}</button></form><button className="link" onClick={() => { setReset(!reset); setMessage(''); }}>{reset ? 'Вернуться ко входу' : 'Забыли пароль?'}</button></main>;
}
