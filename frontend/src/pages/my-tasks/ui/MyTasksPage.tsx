import type { Profile, Task } from '@/shared/api/supabase';
import { Loading, useRows } from '@/shared/lib/crm';
import { TaskList } from '@/widgets/crm-forms';

export function MyTasksPage({ profile }: { profile: Profile }) { const tasks = useRows<Task>('tasks'); const mine = tasks.data?.filter(t => profile.role === 'admin' || (profile.role === 'manager' ? t.responsible_manager_id === profile.id : t.assigned_to === profile.id)); return <><h1>{profile.role === 'admin' ? 'Все задачи' : 'Мои задачи'}</h1><Loading loading={tasks.isLoading} error={tasks.error} />{mine && <TaskList tasks={mine} />}</>; }
