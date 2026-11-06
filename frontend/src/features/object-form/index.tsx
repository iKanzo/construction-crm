import { useId, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { objectFormSchema, type ObjectFormValues } from '../form-ui/schemas';
import styles from '../form-ui/Form.module.scss';

export type { ObjectFormValues } from '../form-ui/schemas';
export type ObjectFormProps = {
  initialValues?: ObjectFormValues;
  onSubmit: (values: ObjectFormValues) => void | Promise<void>;
  onCancel: () => void;
};

export function ObjectForm({ initialValues, onSubmit, onCancel }: ObjectFormProps) {
  const id = useId();
  const [submitError, setSubmitError] = useState('');
  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<ObjectFormValues>({
    resolver: zodResolver(objectFormSchema),
    defaultValues: initialValues ?? { title: '', description: '', address: '', customer_name: '', customer_phone: '' },
  });
  const fields = [
    ['title', 'Название'], ['description', 'Описание'], ['address', 'Адрес'],
    ['customer_name', 'Заказчик'], ['customer_phone', 'Телефон заказчика'],
  ] as const;
  return <form className={styles.form} noValidate onSubmit={handleSubmit(async (values) => {
    setSubmitError('');
    try { await onSubmit(values); } catch (error) {
      setSubmitError(error && typeof error === 'object' && 'message' in error ? String(error.message) : 'Произошла ошибка. Попробуйте ещё раз.');
    }
  })}>
    <h2>{initialValues ? 'Изменить объект' : 'Новый объект'}</h2>
    {fields.map(([name, label]) => <div className={styles.field} key={name}>
      <label htmlFor={`${id}-${name}`}>{label}</label>
      {name === 'description'
        ? <textarea id={`${id}-${name}`} {...register(name)} aria-invalid={!!errors[name]} aria-describedby={errors[name] ? `${id}-${name}-error` : undefined} />
        : <input id={`${id}-${name}`} {...register(name)} aria-required="true" aria-invalid={!!errors[name]} aria-describedby={errors[name] ? `${id}-${name}-error` : undefined} />}
      {errors[name] && <p className={styles.error} id={`${id}-${name}-error`} role="alert">{errors[name]?.message}</p>}
    </div>)}
    {submitError && <p className={styles.error} role="alert">{submitError}</p>}
    <div className={styles.actions}><button type="submit" disabled={isSubmitting}>Сохранить</button><button type="button" disabled={isSubmitting} onClick={onCancel}>Отмена</button></div>
  </form>;
}
