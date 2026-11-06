import { useState } from 'react';
import { supabase } from '@/shared/api/supabase';
import { Notice } from '@/shared/lib/crm';
import { errorText } from '@/shared/api/supabase';

export function PasswordForm({ title = 'Новый пароль', setup = false, done }: { title?: string; setup?: boolean; done?: () => void }) {
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  return <form className="panel" onSubmit={async e => {
    e.preventDefault();
    const form = e.currentTarget;
    const data = new FormData(form);
    // Passwords are not trimmed: whitespace may be part of the user's password.
    const password = String(data.get('password') || '');
    setError(''); setMessage('');
    if (password !== data.get('confirmation')) { setError('Пароли не совпадают.'); return; }
    setBusy(true);
    try {
      const { error: updateError } = await supabase.auth.updateUser({ password, ...(setup ? { data: { password_setup_required: false } } : {}) });
      if (updateError) throw updateError;
      form.reset(); setMessage('Пароль сохранён.'); done?.();
    } catch (err) { setError(errorText(err)); } finally { setBusy(false); }
  }}><h2>{title}</h2><p>Не менее 8 символов, строчная и заглавная латинские буквы и цифра.</p><label>Новый пароль<input name="password" type="password" required minLength={8} pattern="(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9]).{8,}" autoComplete="new-password" /></label><label>Повторите пароль<input name="confirmation" type="password" required autoComplete="new-password" /></label><Notice error={error} />{message && <p role="status">{message}</p>}<button disabled={busy}>Сохранить</button></form>;
}
