import type { Messages, Requests } from './types';

type Payload<K extends keyof Requests> = Requests[K][0];
type Reply<K extends keyof Requests> = Requests[K][1];
type Args<K extends keyof Requests> = Payload<K> extends void ? [] : [Payload<K>];

export type MockHandlers = { [K in keyof Requests]: (payload: Payload<K>) => Reply<K> };

export type Failure = { ok: false; error: string };

export const inGame = 'GetParentResourceName' in window;

const resourceName = 'cobalt_ambulancejob';

export function isFailure(value: unknown): value is Failure {
  return typeof value === 'object' && value !== null && 'ok' in value && value.ok === false && 'error' in value && typeof value.error === 'string';
}

async function fetchMock<K extends keyof Requests>(name: K, payload: Payload<K>): Promise<Reply<K> | null> {
  if (!import.meta.env.DEV) return null;

  const { handlers } = await import('./mock');
  const handler = handlers[name] as (payload: Payload<K>) => Reply<K>;
  return structuredClone(handler(payload));
}

export async function fetchNui<K extends keyof Requests>(name: K, ...args: Args<K>): Promise<Reply<K> | null> {
  const payload = args[0] as Payload<K>;

  if (!inGame) return fetchMock(name, payload);

  try {
    const response = await fetch(`https://${resourceName}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload ?? {}),
    });
    if (!response.ok) return null;

    return (await response.json()) as Reply<K>;
  } catch {
    return null;
  }
}

const actions: ReadonlySet<string> = new Set<Messages['action']>(['open', 'close', 'callAdded', 'callUpdated', 'alert', 'alertClear', 'death', 'deathHold', 'bedsChanged']);

function isMessage(value: unknown): value is Messages {
  if (typeof value !== 'object' || value === null || !('action' in value)) return false;

  return typeof value.action === 'string' && actions.has(value.action);
}

export function onMessage(handler: (message: Messages) => void): () => void {
  const listener = (event: MessageEvent<unknown>) => {
    if (isMessage(event.data)) handler(event.data);
  };

  window.addEventListener('message', listener);
  return () => window.removeEventListener('message', listener);
}

export async function sendMockOpen(): Promise<void> {
  if (inGame || !import.meta.env.DEV) return;

  const module = await import('./mock');
  if (['#laststand', '#dead', '#respawn'].includes(location.hash)) return module.startDeath();
  if (location.hash !== '#popup') window.postMessage(module.openMessage, '*');
  module.startAlerts();
  module.startBedUpdates();
}
