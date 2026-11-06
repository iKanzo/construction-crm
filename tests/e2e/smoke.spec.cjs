const { test, expect } = require('@playwright/test');

test('неавторизованный пользователь видит форму входа, а не данные CRM', async ({ page }) => {
  await page.goto('/objects/example');
  await expect(page.getByRole('heading', { name: 'Вход' })).toBeVisible();
  await expect(page.getByRole('navigation')).toHaveCount(0);
  await expect(page.getByLabel('Email')).toBeVisible();
  await expect(page.getByLabel('Пароль')).toBeVisible();
});

test('форма восстановления пароля доступна со страницы входа', async ({ page }) => {
  await page.goto('/login');
  await page.getByRole('button', { name: 'Забыли пароль?' }).click();
  await expect(page.getByRole('heading', { name: 'Восстановление пароля' })).toBeVisible();
  await expect(page.getByLabel('Email')).toBeVisible();
  await expect(page.getByLabel('Пароль')).toHaveCount(0);
  await page.getByRole('button', { name: 'Вернуться ко входу' }).click();
  await expect(page.getByRole('heading', { name: 'Вход' })).toBeVisible();
});
