import { lazy, Suspense, useEffect, useState, type ReactNode } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { NavLink, Outlet, useOutletContext } from 'react-router-dom';
import type { Session } from '@supabase/supabase-js';
import { authLinkError, configured, passwordLink, supabase, type Profile } from '@/shared/api/supabase';
import { Notice, roles } from '@/shared/lib/crm';
import { PasswordForm } from '@/shared/ui/PasswordForm';

const LoginPage = lazy(() => import('@/pages/login').then(module => ({ default: module.LoginPage })));

export function AuthGate() {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [authError, setAuthError] = useState<unknown>(authLinkError);
  const [passwordSetup, setPasswordSetup] = useState(passwordLink || sessionStorage.getItem('crm-password-setup') === 'pending');
  const client = useQueryClient();
  useEffect(() => {
    let live = true;
    let authEventReceived = false;
    let currentUser: string | undefined;
    let pendingLink = passwordLink;
    const { data } = supabase.auth.onAuthStateChange((event, next) => {
      if (!live) return;
      authEventReceived = true;
      if (event === 'SIGNED_OUT' || (currentUser && currentUser !== next?.user.id)) {
        client.clear();
        sessionStorage.removeItem('crm-password-setup'); setPasswordSetup(false);
      }
      currentUser = next?.user.id;
      setSession(next); setReady(true);
      if (next || event !== 'INITIAL_SESSION') setAuthError('');
      if (event === 'PASSWORD_RECOVERY' || next?.user.user_metadata?.password_setup_required === true || (pendingLink && next)) {
        pendingLink = false;
        sessionStorage.setItem('crm-password-setup', 'pending'); setPasswordSetup(true);
      }
      if (event === 'SIGNED_OUT') { sessionStorage.removeItem('crm-password-setup'); setPasswordSetup(false); }
    });
    void supabase.auth.getSession().then(({ data: initial, error }) => {
      if (!live || authEventReceived) return;
      if (error) { setAuthError(error); setReady(true); return; }
      currentUser = initial.session?.user.id;
      setSession(initial.session); setReady(true);
      if (initial.session && (pendingLink || initial.session.user.user_metadata?.password_setup_required === true)) {
        pendingLink = false;
        sessionStorage.setItem('crm-password-setup', 'pending'); setPasswordSetup(true);
      }
    }).catch(error => {
      if (live && !authEventReceived) { setAuthError(error); setReady(true); }
    });
    return () => { live = false; data.subscription.unsubscribe(); };
  }, [client]);
  const profile = useQuery({
    queryKey: ['profile', session?.user.id], enabled: Boolean(session), refetchInterval: 30000,
    queryFn: async () => {
      const { data, error } = await supabase.from('profiles').select('id,full_name,role,is_active').eq('id', session!.user.id).maybeSingle();
      if (error) throw error;
      return data as Profile | null;
    },
  });
  if (!configured) return <main className="auth"><h1>Construction CRM</h1><p>Укажите VITE_SUPABASE_URL и VITE_SUPABASE_ANON_KEY в окружении frontend.</p></main>;
  if (!ready) return <p>Загрузка…</p>;
  if (passwordSetup && session) return <main className="auth"><h1>Установка пароля</h1><PasswordForm setup done={() => { sessionStorage.removeItem('crm-password-setup'); setPasswordSetup(false); }} /></main>;
  if (!session) return <><Notice error={authError} /><Suspense fallback={<p>Загрузка…</p>}><LoginPage /></Suspense></>;
  if (profile.isLoading) return <p>Загрузка профиля…</p>;
  if (profile.error || !profile.data || !profile.data.is_active) return <main className="auth"><h1>Нет доступа</h1><p>Профиль отсутствует, недоступен или деактивирован. Обратитесь к администратору.</p><Notice error={profile.error} /><button onClick={() => { setAuthError(''); void supabase.auth.signOut().then(({ error }) => { if (error) setAuthError(error); }).catch(setAuthError); }}>Выйти</button><button onClick={() => void profile.refetch()}>Повторить</button><Notice error={authError} /></main>;
  return <Layout profile={profile.data} session={session} />;
}
function Layout({ profile, session }: { profile: Profile; session: Session }) {
  return <div className="shell"><header><strong>Construction CRM</strong><span>{profile.full_name} · {roles[profile.role]}</span></header><div className="shell-body"><nav aria-label="Основная навигация"><NavLink to="/" end>Объекты</NavLink><NavLink to="/my-tasks">Мои задачи</NavLink><NavLink to="/transfers">Передачи</NavLink>{profile.role === 'admin' && <NavLink to="/users">Сотрудники</NavLink>}<NavLink to="/profile">Профиль</NavLink></nav><main><Suspense fallback={<p>Загрузка…</p>}><Outlet context={{ profile, session }} /></Suspense></main></div></div>;
}
export type Context = { profile: Profile; session: Session };
export function WithContext({ children }: { children: (context: Context) => ReactNode }) { return <ContextConsumer>{children}</ContextConsumer>; }
function ContextConsumer({ children }: { children: (context: Context) => ReactNode }) { const context = useOutletContext<Context>(); return <>{children(context)}</>; }
