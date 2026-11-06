import styles from './PageStub.module.scss';

interface PageStubProps {
  title: string;
  description?: string;
}

export function PageStub({ title, description }: PageStubProps) {
  return (
    <section className={styles.root}>
      <h1 className={styles.title}>{title}</h1>
      {description ? <p className={styles.description}>{description}</p> : null}
    </section>
  );
}
