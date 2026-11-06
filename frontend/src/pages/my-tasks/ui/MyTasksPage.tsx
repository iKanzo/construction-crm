import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { taskPage, type Profile } from '@/shared/api/supabase';
import { Loading, Pagination } from '@/shared/lib/crm';
import { TaskList } from '@/widgets/crm-forms';

export function MyTasksPage({ profile }: { profile: Profile }) {
  const [completed, setCompleted] = useState(false);
  const [page, setPage] = useState(0);
  const tasks = useQuery({
    queryKey: ['task-page', profile.id, profile.role, completed, page],
    queryFn: () => taskPage(profile, completed, page),
    refetchInterval: 5000,
  });
  const mine = tasks.data?.slice(0, 20).filter(t => profile.role === 'admin' || (profile.role === 'manager' ? t.responsible_manager_id === profile.id : t.assigned_to === profile.id));
  return <><h1>{profile.role === 'admin' ? 'Все задачи' : 'Мои задачи'}</h1><div className="actions">{[false, true].map(done => <button key={String(done)} type="button" aria-pressed={completed === done} onClick={() => { setCompleted(done); setPage(0); }}>{done ? 'Завершённые' : 'Активные'}</button>)}</div><Loading loading={tasks.isLoading} error={tasks.error} />{!tasks.error && mine && <TaskList tasks={mine} />}<Pagination page={page} setPage={setPage} hasMore={!tasks.isFetching && !tasks.error && (tasks.data?.length || 0) > 20} /></>;
}
