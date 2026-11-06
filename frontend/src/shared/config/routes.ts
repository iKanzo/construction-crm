export const ROUTES = {
  login: '/login',
  objects: '/',
  objectDetails: (objectId: string = ':objectId') => `/objects/${objectId}`,
  taskDetails: (taskId: string = ':taskId') => `/tasks/${taskId}`,
  myTasks: '/my-tasks',
  transfers: '/transfers',
  users: '/users',
  profile: '/profile',
} as const;
