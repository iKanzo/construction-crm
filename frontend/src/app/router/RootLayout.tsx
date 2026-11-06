import { NavLink, Outlet } from 'react-router-dom';
import { ROUTES } from '@/shared/config';
import styles from './RootLayout.module.scss';

// Временный каркас навигации. Полноценный AppLayout (по ролям) — Этап 7.
export function RootLayout() {
  return (
    <div className={styles.root}>
      <nav className={styles.nav} aria-label="Основная навигация">
        <NavLink to={ROUTES.objects} end>
          Объекты
        </NavLink>
        <NavLink to={ROUTES.myTasks}>Мои задачи</NavLink>
        <NavLink to={ROUTES.transfers}>Передачи</NavLink>
        <NavLink to={ROUTES.users}>Сотрудники</NavLink>
        <NavLink to={ROUTES.profile}>Профиль</NavLink>
      </nav>
      <main className={styles.main}>
        <Outlet />
      </main>
    </div>
  );
}
