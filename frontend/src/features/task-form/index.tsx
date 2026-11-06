import { useId, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { taskFormSchema, type TaskFormValues } from '../form-ui/schemas';
import styles from '../form-ui/Form.module.scss';

export type TaskContent = { title: string; description: string };
export type ExecutorOption = { id: string; full_name: string; role: string; is_active: boolean };
type CommonProps = { onCancel: () => void };
export type TaskFormProps = CommonProps & (
  | { mode: 'create'; executors: ExecutorOption[]; onSubmit: (values: TaskContent & { assigned_to: string | null }) => void | Promise<void> }
  | { mode: 'edit'; initialValues: TaskContent; onSubmit: (values: TaskContent) => void | Promise<void> }
);

export function TaskForm(props: TaskFormProps) {
  const id = useId();
  const [submitError, setSubmitError] = useState('');
  const executors = props.mode === 'create' ? props.executors.filter((profile) => profile.role === 'executor' && profile.is_active) : [];
  const { register, handleSubmit, setError, formState: { errors, isSubmitting } } = useForm<TaskFormValues>({
    resolver: zodResolver(taskFormSchema),
    defaultValues: { title: props.mode === 'edit' ? props.initialValues.title : '', description: props.mode === 'edit' ? props.initialValues.description : '', assigned_to: '' },
  });
  return <form className={styles.form} noValidate onSubmit={handleSubmit(async (values) => {
    setSubmitError('');
    if (props.mode === 'create' && values.assigned_to && !executors.some((executor) => executor.id === values.assigned_to)) {
      setError('assigned_to', { message: 'Выберите активного исполнителя' });
      return;
    }
    try {
      if (props.mode === 'create') await props.onSubmit({ title: values.title, description: values.description, assigned_to: values.assigned_to || null });
      else await props.onSubmit({ title: values.title, description: values.description });
    } catch (error) {
      setSubmitError(error && typeof error === 'object' && 'message' in error ? String(error.message) : 'Произошла ошибка. Попробуйте ещё раз.');
    }
  })}>
    <h2>{props.mode === 'edit' ? 'Изменить задачу' : 'Новая задача'}</h2>
    <div className={styles.field}><label htmlFor={`${id}-title`}>Название</label><input id={`${id}-title`} {...register('title')} aria-required="true" aria-invalid={!!errors.title} aria-describedby={errors.title ? `${id}-title-error` : undefined} />{errors.title && <p className={styles.error} role="alert" id={`${id}-title-error`}>{errors.title.message}</p>}</div>
    <div className={styles.field}><label htmlFor={`${id}-description`}>Описание</label><textarea id={`${id}-description`} {...register('description')} aria-invalid={!!errors.description} aria-describedby={errors.description ? `${id}-description-error` : undefined} />{errors.description && <p className={styles.error} role="alert" id={`${id}-description-error`}>{errors.description.message}</p>}</div>
    {props.mode === 'create' && <div className={styles.field}><label htmlFor={`${id}-assigned_to`}>Исполнитель</label><select id={`${id}-assigned_to`} {...register('assigned_to')} aria-invalid={!!errors.assigned_to} aria-describedby={errors.assigned_to ? `${id}-assigned-error` : undefined}><option value="">Не назначен</option>{executors.map((executor) => <option key={executor.id} value={executor.id}>{executor.full_name}</option>)}</select>{errors.assigned_to && <p className={styles.error} role="alert" id={`${id}-assigned-error`}>{errors.assigned_to.message}</p>}</div>}
    {submitError && <p className={styles.error} role="alert">{submitError}</p>}
    <div className={styles.actions}><button type="submit" disabled={isSubmitting}>Сохранить</button><button type="button" disabled={isSubmitting} onClick={props.onCancel}>Отмена</button></div>
  </form>;
}
