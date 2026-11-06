import { lazy, Suspense, useEffect, useState, type ReactNode } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { NavLink, Outlet, useOutletContext } from 'react-router-dom';
import type { Session } from '@supabase/supabase-js';
import { configured, supabase, type Profile } from '@/shared/api/supabase';
import { Notice, roles, useAction, value } from '@/shared/lib/crm';

const LoginPage = lazy(() => import('@/pages/login').then(module => ({ default: module.LoginPage })));

export function AuthGate() {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [recovery, setRecovery] = useState(false);
  const client = useQueryClient();
  useEffect(() => {
    let live = true;
    supabase.auth.getSession().then(({ data }) => { if (live) { setSession(data.session); setReady(true); } });
    const { data } = supabase.auth.onAuthStateChange((event, next) => { if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') client.clear(); setSession(next); setReady(true); if (event === 'PASSWORD_RECOVERY') setRecovery(true); if (event === 'SIGNED_OUT') setRecovery(false); });
    return () => { live = false; data.subscription.unsubscribe(); };
  }, [client]);
  const profile = useQuery({ queryKey: ['profile', session?.user.id], queryFn: async () => { const { data, error } = await supabase.from('profiles').select('id,full_name,role,is_active').eq('id', session!.user.id).maybeSingle(); if (error) throw error; return data as Profile | null; }, enabled: Boolean(session), refetchInterval: 30000 });
  if (!configured) return <main className="auth"><h1>Construction CRM</h1><p>Укажите VITE_SUPABASE_URL и VITE_SUPABASE_ANON_KEY в окружении frontend.</p></main>;
  if (!ready) return <p>Загрузка…</p>;
  if (recovery && session) return <PasswordRecovery done={() => setRecovery(false)} />;
  if (!session) return <Suspense fallback={<p>Загрузка…</p>}><LoginPage /></Suspense>;
  if (profile.isLoading) return <p>Загрузка профиля…</p>;
  if (profile.error || !profile.data || !profile.data.is_active) return <main className="auth"><h1>Нет доступа</h1><p>Профиль отсутствует, недоступен или деактивирован. Обратитесь к администратору.</p><Notice error={profile.error} /><button onClick={() => void supabase.auth.signOut()}>Выйти</button></main>;
  return <Layout profile={profile.data} session={session} />;
}
function PasswordRecovery({ done }: { done: () => void }) { const action = useAction(); return <main className="auth"><h1>Новый пароль</h1><form onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); void action.run(async () => { const { error } = await supabase.auth.updateUser({ password: value(f, 'password') }); if (error) throw error; }, done); }}><label>Новый пароль<input name="password" type="password" minLength={6} required /></label><Notice error={action.error} /><button disabled={action.busy}>Сохранить</button></form></main>; }
function Layout({ profile, session }: { profile: Profile; session: Session }) {
  return <div className="shell"><header><strong>Construction CRM</strong><span>{profile.full_name} · {roles[profile.role]}</span></header><div className="shell-body"><nav aria-label="Основная навигация"><NavLink to="/" end>Объекты</NavLink><NavLink to="/my-tasks">Мои задачи</NavLink><NavLink to="/transfers">Передачи</NavLink>{profile.role === 'admin' && <NavLink to="/users">Сотрудники</NavLink>}<NavLink to="/profile">Профиль</NavLink></nav><main><Suspense fallback={<p>Загрузка…</p>}><Outlet context={{ profile, session }} /></Suspense></main></div></div>;
}
export type Context = { profile: Profile; session: Session };
export function WithContext({ children }: { children: (context: Context) => ReactNode }) { return <ContextConsumer>{children}</ContextConsumer>; }
function ContextConsumer({ children }: { children: (context: Context) => ReactNode }) { const context = useOutletContext<Context>(); return <>{children(context)}</>; }
