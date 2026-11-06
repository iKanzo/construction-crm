import { z } from 'zod';

// PostgreSQL char_length counts Unicode code points, not UTF-16 code units.
const length = (value: string) => Array.from(value).length;
const requiredText = (max: number, min = 1) => z.string().trim()
  .refine((value) => length(value) >= min && length(value) <= max, `Введите от ${min} до ${max} символов`);
const optionalText = (max: number) => z.string().trim()
  .refine((value) => length(value) <= max, `Максимум ${max} символов`);

export const objectFormSchema = z.object({
  title: requiredText(200),
  description: optionalText(5000),
  address: requiredText(500),
  customer_name: requiredText(200),
  customer_phone: requiredText(32, 5),
});

export const taskFormSchema = z.object({
  title: requiredText(200),
  description: optionalText(10000),
  assigned_to: z.string(),
});

export type ObjectFormValues = z.infer<typeof objectFormSchema>;
export type TaskFormValues = z.infer<typeof taskFormSchema>;
