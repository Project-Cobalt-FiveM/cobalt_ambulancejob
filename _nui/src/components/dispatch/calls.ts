import { age, capitalise } from '../../lib/format';
import { t } from '../../lib/locale.svelte';
import { mdt } from '../../lib/store.svelte';
import type { Call, ReviveState } from '../../lib/types';

export function stateLabel(state: ReviveState): string {
  return t(`ui.revive_state.${state}`);
}

export type Bleed = { left: number; share: number };

export function bleed(call: Call, now: number): Bleed | null {
  const at = call.patient?.bleedsOutAt;
  if (at == null) return null;

  const left = Math.max(0, at - now);
  return { left, share: Math.min(1, left / Math.max(1, mdt.bleedoutSeconds)) };
}

export function since(call: Call, now: number): string {
  return capitalise(age(call.createdAt, now));
}

export function units(call: Call): string | null {
  const [first, ...rest] = call.responders;
  if (!first) return null;

  return rest.length ? t('ui.dispatch.units_more', first.callsign, rest.length) : first.callsign;
}

export function responderLine(call: Call): string {
  const unit = units(call);
  return unit ? t('ui.dispatch.responding', unit) : t('ui.dispatch.no_unit');
}
