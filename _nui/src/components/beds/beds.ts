import { capitalise, clockTime, shortDate, toDate } from '../../lib/format';
import { t } from '../../lib/locale.svelte';
import type { Bed, Hospital } from '../../lib/types';

export function freeBeds(hospital: Hospital | undefined): Bed[] {
  return hospital?.beds.filter((bed) => !bed.admission && !bed.frontDesk) ?? [];
}

export function timeLeft(endsAt: number, now: number): string {
  const seconds = Math.max(0, endsAt - now);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

function dayOffset(seconds: number, now: number): number {
  const start = (value: number) => new Date(toDate(value).toDateString()).getTime();
  return Math.round((start(seconds) - start(now)) / 86400000);
}

const dayKeys: Record<number, string> = { [-1]: 'ui.date.yesterday', 0: 'ui.date.today', 1: 'ui.date.tomorrow' };

export function dayName(seconds: number, now: number): string {
  const key = dayKeys[dayOffset(seconds, now)];
  return key ? t(key) : shortDate(seconds);
}

export function dayAndTime(seconds: number, now: number): string {
  return t('ui.beds.day_at_time', capitalise(dayName(seconds, now)), clockTime(seconds));
}

export function since(seconds: number, now: number): string {
  return t('ui.beds.since', dayOffset(seconds, now) === 0 ? clockTime(seconds) : dayName(seconds, now));
}

export function doctorName(name: string): string {
  return name.startsWith('Dr. ') ? `Dr. ${name.split(' ').at(-1)}` : name;
}
