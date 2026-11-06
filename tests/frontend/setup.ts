import '@testing-library/jest-dom/vitest';
import { cleanup, configure } from '@testing-library/react';
import { afterEach, vi } from 'vitest';

// Node's built-in Request rejects jsdom's AbortSignal during React Router navigation.
// These route tests don't execute loaders/actions, so keep only the request fields
// React Router needs for its navigation lifecycle.
class TestRequest {
  readonly url: string;
  readonly method: string;
  readonly signal: AbortSignal | null;

  constructor(input: string | URL, init?: RequestInit) {
    this.url = String(input);
    this.method = init?.method ?? 'GET';
    this.signal = init?.signal ?? null;
  }
}

vi.stubGlobal('Request', TestRequest);
// The first lazy route also loads its form modules on slower CI/Windows hosts.
configure({ asyncUtilTimeout: 3000 });

afterEach(() => cleanup());
