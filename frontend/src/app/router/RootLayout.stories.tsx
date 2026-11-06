import type { Meta, StoryObj } from '@storybook/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { MyTasksPage } from '@/pages/my-tasks';
import { ObjectsPage } from '@/pages/objects';
import { ProfilePage } from '@/pages/profile';
import { TransfersPage } from '@/pages/transfers';
import { UsersPage } from '@/pages/users';
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
          <Route path={ROUTES.objects} element={<ObjectsPage />} />
          <Route path={ROUTES.myTasks} element={<MyTasksPage />} />
          <Route path={ROUTES.transfers} element={<TransfersPage />} />
          <Route path={ROUTES.users} element={<UsersPage />} />
          <Route path={ROUTES.profile} element={<ProfilePage />} />
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
