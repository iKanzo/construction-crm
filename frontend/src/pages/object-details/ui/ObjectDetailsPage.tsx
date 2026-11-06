import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { rpc, type ObjectRow, type Profile, type Task } from '@/shared/api/supabase';
import { buttonAction, Loading, Notice, useAction, useRows } from '@/shared/lib/crm';
import { ObjectForm, TaskForm, TaskList } from '@/widgets/crm-forms';

export function ObjectDetailsPage({ profile }: { profile: Profile }) {
  const { objectId } = useParams(); const objects = useRows<ObjectRow>('objects', 'id', objectId, !!objectId); const tasks = useRows<Task>('tasks', 'object_id', objectId, !!objectId); const object = objects.data?.[0]; const [edit, setEdit] = useState(false); const [create, setCreate] = useState(false); const action = useAction(); const navigate = useNavigate();
  if (objects.isLoading || objects.error) return <Loading loading={objects.isLoading} error={objects.error} />;
  if (!object) return <p>Объект не найден или недоступен.</p>;
  return <><Link to="/">← Объекты</Link><div className="heading"><div><h1>{object.title}</h1><p>{object.address}</p></div>{profile.role === 'manager' && <div className="actions">{buttonAction('Изменить', () => setEdit(!edit))}{buttonAction('Удалить', () => { if (window.confirm('Удалить объект? Это возможно только если у него нет задач.')) void action.run(() => rpc('delete_object', { p_object_id: object.id }), () => navigate('/')); })}</div>}</div><Notice error={action.error} />{edit && <ObjectForm object={object} done={() => setEdit(false)} />}<section className="panel"><h2>Информация</h2><p>{object.description || 'Описание не указано'}</p><p>Заказчик: {object.customer_name} · {object.customer_phone}</p></section><div className="heading"><h2>Задачи</h2>{profile.role === 'manager' && buttonAction('Создать задачу', () => setCreate(!create))}</div>{create && <TaskForm objectId={object.id} done={() => setCreate(false)} />}<Loading loading={tasks.isLoading} error={tasks.error} />{tasks.data && <TaskList tasks={tasks.data} />}</>;
}
