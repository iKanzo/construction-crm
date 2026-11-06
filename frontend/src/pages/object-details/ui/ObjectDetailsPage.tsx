import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { objectTaskSummaries, rpc, type ObjectRow, type Profile, type Task } from '@/shared/api/supabase';
import { buttonAction, Loading, Notice, useAction, useRows } from '@/shared/lib/crm';
import { ObjectForm, ObjectTaskList, TaskForm } from '@/widgets/crm-forms';

export function ObjectDetailsPage({ profile }: { profile: Profile }) {
  const { objectId } = useParams();
  const objects = useRows<ObjectRow>('objects', 'id', objectId, !!objectId, true);
  const object = objects.data?.[0];
  const tasks = useRows<Task>('tasks', 'object_id', objectId, !!object, true);
  const profiles = useRows<Profile>('profiles', undefined, undefined, !!object);
  const summaries = useQuery({
    queryKey: ['object-task-summaries', objectId, profile.id],
    queryFn: () => objectTaskSummaries(objectId!),
    enabled: !!object && profile.role !== 'executor', refetchInterval: 5000,
  });
  const [edit, setEdit] = useState(false);
  const [create, setCreate] = useState(false);
  const action = useAction();
  const navigate = useNavigate();
  if (objects.isLoading || objects.error) return <Loading loading={objects.isLoading} error={objects.error} />;
  if (!object) return <p>Объект не найден или недоступен.</p>;
  const creator = profile.role === 'manager' && object.created_by === profile.id;
  // Statuses of other managers' tasks are intentionally unavailable. The RPC
  // enforces the all-tasks-finished rule if the creator attempts an edit.
  const knownOpenTasks = tasks.data?.some(t => !['accepted', 'closed'].includes(t.status));
  const fullTasks = (tasks.data || []).filter(t => profile.role === 'admin' || (profile.role === 'manager' ? t.responsible_manager_id === profile.id : t.assigned_to === profile.id));
  const brief = profile.role === 'executor' ? (tasks.data ? fullTasks : undefined) : summaries.data;
  return <><Link to="/">← Объекты</Link><div className="heading"><div><h1>{object.title}</h1><p>{object.address}</p></div>{creator && <div className="actions">{buttonAction('Изменить', () => setEdit(!edit), tasks.isLoading || !!tasks.error || !!knownOpenTasks)}{buttonAction('Удалить', () => {
    if (window.confirm('Удалить пустой объект?')) void action.run(() => rpc('delete_object', { p_object_id: object.id }), () => navigate('/'));
  }, !summaries.data || summaries.data.length > 0)}</div>}</div><Notice error={action.error} />{edit && creator && <ObjectForm object={object} done={() => setEdit(false)} />}<section className="panel"><h2>Информация</h2><p>{object.description || 'Описание не указано'}</p><p>Заказчик: {object.customer_name} · {object.customer_phone}</p>{creator && knownOpenTasks && <p>Редактирование доступно после завершения всех задач объекта.</p>}</section><div className="heading"><h2>Задачи</h2>{profile.role === 'manager' && buttonAction('Создать задачу', () => setCreate(!create))}</div>{create && profile.role === 'manager' && <TaskForm objectId={object.id} done={() => setCreate(false)} />}<Loading loading={tasks.isLoading || (profile.role !== 'executor' && summaries.isLoading)} error={tasks.error || summaries.error || profiles.error} />{brief && <ObjectTaskList summaries={brief} fullTasks={fullTasks} profiles={profiles.data || []} />}</>;
}
