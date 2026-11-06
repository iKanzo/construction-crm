import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import type { ObjectRow, Profile } from '@/shared/api/supabase';
import { buttonAction, Loading, Pagination, useRows } from '@/shared/lib/crm';
import { ObjectForm } from '@/widgets/crm-forms';

export function ObjectsPage({ profile }: { profile: Profile }) {
  const [page, setPage] = useState(0); const objects = useRows<ObjectRow>('objects', undefined, undefined, true, false, page); const [create, setCreate] = useState(false); const navigate = useNavigate();
  return <><div className="heading"><div><h1>Объекты</h1><p>Доступные вам строительные объекты</p></div>{profile.role === 'manager' && buttonAction('Создать объект', () => setCreate(!create))}</div>{create && <ObjectForm done={(id) => { setCreate(false); if (id) navigate(`/objects/${id}`); }} />}<Loading loading={objects.isLoading} error={objects.error} /><div className="list">{objects.data?.slice(0, 20).map(o => <Link className="card" key={o.id} to={`/objects/${o.id}`}><strong>{o.title}</strong><span>{o.address}</span><span>{o.customer_name}</span></Link>)}{objects.data?.length === 0 && <p>Объектов пока нет.</p>}</div>{objects.data && <Pagination page={page} setPage={setPage} hasMore={objects.data.length > 20} />}</>;
}
