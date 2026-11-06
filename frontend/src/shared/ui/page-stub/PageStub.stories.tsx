import type { Meta, StoryObj } from '@storybook/react';
import { PageStub } from './PageStub';

const meta = {
  title: 'Shared/PageStub',
  component: PageStub,
  args: {
    title: 'Объекты',
    description: 'Список объектов (Этап 7).',
  },
} satisfies Meta<typeof PageStub>;

export default meta;
type Story = StoryObj<typeof meta>;

export const WithDescription: Story = {};

export const TitleOnly: Story = {
  args: { title: 'Мои задачи', description: undefined },
};
