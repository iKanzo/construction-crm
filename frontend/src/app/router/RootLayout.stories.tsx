import type { Meta, StoryObj } from '@storybook/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { PageStub } from '@/shared/ui/page-stub/PageStub';
import { ROUTES } from '@/shared/config';
import { RootLayout } from './RootLayout';

const meta = {
  title: 'App/RootLayout',
  component: RootLayout,
  parameters: { layout: 'fullscreen' },
} satisfies Meta<typeof RootLayout>;

export default meta;
type Story = StoryObj<typeof meta>;

function LayoutExample({ initialPath }: { initialPath: string }) {
  return (
    <MemoryRouter initialEntries={[initialPath]}>
      <Routes>
        <Route element={<RootLayout />}>
          <Route path={ROUTES.objects} element={<PageStub title="Объекты" />} />
          <Route path={ROUTES.myTasks} element={<PageStub title="Мои задачи" />} />
          <Route path={ROUTES.transfers} element={<PageStub title="Передачи" />} />
          <Route path={ROUTES.users} element={<PageStub title="Сотрудники" />} />
          <Route path={ROUTES.profile} element={<PageStub title="Профиль" />} />
        </Route>
      </Routes>
    </MemoryRouter>
  );
}

export const Objects: Story = {
  render: () => <LayoutExample initialPath={ROUTES.objects} />,
};

export const Profile: Story = {
  render: () => <LayoutExample initialPath={ROUTES.profile} />,
};
