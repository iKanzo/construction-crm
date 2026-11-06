import { lazy } from 'react';
import { Navigate, type RouteObject } from 'react-router-dom';
import { AuthGate, WithContext } from '../Crm';

const ObjectsPage = lazy(() => import('@/pages/objects').then(module => ({ default: module.ObjectsPage })));
const ObjectDetailsPage = lazy(() => import('@/pages/object-details').then(module => ({ default: module.ObjectDetailsPage })));
const TaskDetailsPage = lazy(() => import('@/pages/task-details').then(module => ({ default: module.TaskDetailsPage })));
const MyTasksPage = lazy(() => import('@/pages/my-tasks').then(module => ({ default: module.MyTasksPage })));
const TransfersPage = lazy(() => import('@/pages/transfers').then(module => ({ default: module.TransfersPage })));
const UsersPage = lazy(() => import('@/pages/users').then(module => ({ default: module.UsersPage })));
const ProfilePage = lazy(() => import('@/pages/profile').then(module => ({ default: module.ProfilePage })));

export const routes: RouteObject[] = [{
  element: <AuthGate />,
  children: [
    { index: true, element: <WithContext>{({ profile }) => <ObjectsPage profile={profile} />}</WithContext> },
    { path: 'login', element: <Navigate to="/" replace /> },
    { path: 'objects/:objectId', element: <WithContext>{({ profile }) => <ObjectDetailsPage profile={profile} />}</WithContext> },
    { path: 'tasks/:taskId', element: <WithContext>{({ profile }) => <TaskDetailsPage profile={profile} />}</WithContext> },
    { path: 'my-tasks', element: <WithContext>{({ profile }) => <MyTasksPage profile={profile} />}</WithContext> },
    { path: 'transfers', element: <WithContext>{({ profile }) => <TransfersPage profile={profile} />}</WithContext> },
    { path: 'users', element: <WithContext>{({ profile }) => <UsersPage profile={profile} />}</WithContext> },
    { path: 'profile', element: <WithContext>{context => <ProfilePage {...context} />}</WithContext> },
    { path: '*', element: <Navigate to="/" replace /> },
  ],
}];
