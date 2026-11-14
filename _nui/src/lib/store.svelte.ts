import { fetchNui, isFailure } from './nui';
import { nowSeconds } from './format';
import { setLocales, t } from './locale.svelte';
import type { AlertData, Call, Created, DeathScreen, HospitalBeds, Keybinds, Medic, MedicStatus, Messages, Page, Permission, Result, Session, Settings } from './types';

export type Route =
  | { page: Exclude<Page, 'patients' | 'reports'> }
  | { page: 'patients'; citizenid: string | null }
  | { page: 'reports'; editor: ReportEditor | null; selected: number | null };

export type ReportEditor = { id: number | null; citizenid: string | null; callId: number | null; templateId: number | null };

export type Alert = AlertData & { key: number };

export type Toast = { key: number; tone: 'error' | 'success'; text: string };

let sequence = 0;

function routeFor(page: Page, citizenid: string | null): Route {
  switch (page) {
    case 'patients':
      return { page, citizenid };
    case 'reports':
      return { page, editor: null, selected: null };
    default:
      return { page };
  }
}

class Mdt {
  visible = $state(false);
  medic = $state<Medic | null>(null);
  settings = $state<Settings>({ medicShare: 20, shareWithPolice: false });
  keybinds = $state<Keybinds>({ respond: 'E', waypoint: 'K' });
  route = $state<Route>({ page: 'dashboard' });
  calls = $state<Call[]>([]);
  unpaid = $state(0);
  alerts = $state<Alert[]>([]);
  toast = $state<Toast | null>(null);
  now = $state(nowSeconds());
  bleedoutSeconds = $state(0);
  death = $state<{ screen: DeathScreen; offset: number } | null>(null);
  deathHold = $state<{ ms: number; startedAt: number } | null>(null);
  beds = $state<HospitalBeds[] | null>(null);

  openCalls = $derived(this.calls.filter((call) => call.status === 'open'));

  #layers: (() => void)[] = [];
  #toastTimer: ReturnType<typeof setTimeout> | undefined;

  constructor() {
    $effect.root(() => {
      $effect(() => {
        if (!this.visible && this.alerts.length === 0 && !this.death) return;

        this.now = nowSeconds();
        const timer = setInterval(() => (this.now = nowSeconds()), 1000);
        return () => clearInterval(timer);
      });
    });
  }

  can(permission: Permission): boolean {
    const permissions = this.medic?.permissions;
    if (!permissions) return false;

    return permissions.administrator || permissions[permission];
  }

  has(page: Page): boolean {
    return this.medic?.pages.includes(page) ?? false;
  }

  lockedRank(page: Page): string | null {
    return this.medic?.locked.find((entry) => entry.page === page)?.rank ?? null;
  }

  navigate(route: Route): void {
    if (!this.has(route.page)) return;
    this.route = route;
  }

  go(page: Page): void {
    this.navigate(routeFor(page, null));
  }

  openPatient(citizenid: string): void {
    this.navigate({ page: 'patients', citizenid });
  }

  openReport(id: number): void {
    this.navigate({ page: 'reports', editor: null, selected: id });
  }

  editReport(editor: ReportEditor): void {
    this.navigate({ page: 'reports', editor, selected: null });
  }

  newReport(citizenid: string | null = null, callId: number | null = null): void {
    this.editReport({ id: null, citizenid, callId, templateId: null });
  }

  call(id: number): Call | null {
    return this.calls.find((call) => call.id === id) ?? null;
  }

  isResponding(call: Call): boolean {
    return call.responders.some((responder) => responder.citizenid === this.medic?.citizenid);
  }

  pushLayer(close: () => void): () => void {
    this.#layers.push(close);
    return () => {
      this.#layers = this.#layers.filter((layer) => layer !== close);
    };
  }

  escape(): void {
    const layer = this.#layers.at(-1);
    if (layer) {
      layer();
      return;
    }

    this.close();
  }

  close(): void {
    if (!this.visible) return;

    this.visible = false;
    void fetchNui('close');
  }

  #notify(text: string, tone: Toast['tone']): void {
    clearTimeout(this.#toastTimer);
    this.toast = { key: ++sequence, tone, text };
    this.#toastTimer = setTimeout(() => (this.toast = null), 5000);
  }

  #fail(reply: unknown): void {
    if (isFailure(reply)) this.#notify(reply.error, 'error');
  }

  report<R extends Result | Created>(result: R | null, success?: string): result is Extract<R, { ok: true }> {
    if (!result?.ok) {
      this.#notify(result?.error ?? t('ui.common.error'), 'error');
      return false;
    }

    if (success) this.#notify(success, 'success');
    return true;
  }

  list<T>(reply: T[] | null): T[] | null {
    if (Array.isArray(reply)) return reply;

    this.#fail(reply);
    return null;
  }

  single<T extends object>(reply: T | null): T | null {
    if (reply !== null && typeof reply === 'object' && !isFailure(reply)) return reply;

    this.#fail(reply);
    return null;
  }

  async boot(): Promise<void> {
    const reply = await fetchNui('boot');
    setLocales(reply?.locales);
    if (typeof reply?.bleedoutSeconds === 'number') this.bleedoutSeconds = reply.bleedoutSeconds;
  }

  async refreshUnpaid(): Promise<void> {
    if (!this.has('billing')) return;

    const dashboard = this.single(await fetchNui('getDashboard'));
    if (dashboard) this.unpaid = dashboard.stats.unpaidCount;
  }

  async setStatus(status: MedicStatus): Promise<void> {
    if (!this.medic) return;

    const previous = this.medic.status;
    this.medic.status = status;

    if (!this.report(await fetchNui('setStatus', { status }))) this.medic.status = previous;
  }

  #open(data: Session): void {
    this.medic = data.medic;
    this.settings = data.settings;
    this.keybinds = data.keybinds;
    this.visible = true;
    this.beds = null;

    const page = data.page && data.medic.pages.includes(data.page) ? data.page : (data.medic.pages[0] ?? 'dashboard');
    this.route = routeFor(page, data.citizenid);

    void this.refreshUnpaid();
    void fetchNui('getCalls').then((reply) => {
      const calls = this.list(reply);
      if (calls) this.calls = calls;
    });
  }

  #upsertCall(call: Call): void {
    const index = this.calls.findIndex((existing) => existing.id === call.id);

    if (index === -1) {
      this.calls = [call, ...this.calls];
      return;
    }

    this.calls[index] = call;
    this.alerts = this.alerts.map((alert) => (alert.call.id === call.id ? { ...alert, call } : alert));
  }

  handle(message: Messages): void {
    switch (message.action) {
      case 'open':
        this.#open(message.data);
        break;
      case 'close':
        this.visible = false;
        break;
      case 'callAdded':
      case 'callUpdated':
        this.#upsertCall(message.data);
        if (message.data.status === 'closed') this.alerts = this.alerts.filter((alert) => alert.call.id !== message.data.id);
        break;
      case 'alert': {
        const key = ++sequence;
        this.alerts = [{ ...message.data, key }, ...this.alerts.filter((alert) => alert.call.id !== message.data.call.id)];
        setTimeout(() => {
          this.alerts = this.alerts.filter((alert) => alert.key !== key);
        }, message.data.seconds * 1000);
        break;
      }
      case 'death':
        this.death = message.data ? { screen: message.data, offset: message.data.now - nowSeconds() } : null;
        if (!message.data) this.deathHold = null;
        break;
      case 'deathHold':
        this.deathHold = message.data ? { ms: message.data, startedAt: performance.now() } : null;
        break;
      case 'alertClear':
        this.alerts = this.alerts.filter((alert) => alert.call.id !== message.data.id);
        break;
      case 'bedsChanged':
        this.beds = message.data;
        break;
      default: {
        const exhaustive: never = message;
        return exhaustive;
      }
    }
  }
}

export const mdt = new Mdt();
