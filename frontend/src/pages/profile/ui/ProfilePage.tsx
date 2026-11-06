import type { Session } from '@supabase/supabase-js';
import { supabase, type Profile } from '@/shared/api/supabase';
import { Notice, roles, useAction } from '@/shared/lib/crm';
import { PasswordForm } from '@/shared/ui/PasswordForm';

type Context = { profile: Profile; session: Session };
export function ProfilePage({ profile, session }: Context) {
  const action = useAction();
  return <><h1>Профиль</h1><section className="panel"><p>{profile.full_name}</p><p>{roles[profile.role]}</p><p>{session.user.email}</p><button disabled={action.busy} onClick={() => void action.run(async () => { const { error } = await supabase.auth.signOut(); if (error) throw error; })}>Выйти</button><Notice error={action.error} /></section><PasswordForm title="Сменить пароль" /></>;
}
