import { t } from './locale.svelte';
import type { BodyPart, InjuryKind, InvoiceStatus, MedicStatus, PrescriptionStatus, ReportOutcome, StaffStatus } from './types';

const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

const weekdays = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

export function toDate(seconds: number): Date {
  return new Date(seconds * 1000);
}

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export function pad(value: number): string {
  return value.toString().padStart(2, '0');
}

export function clockTime(seconds: number): string {
  const date = toDate(seconds);
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function monthShort(date: Date): string {
  return t(`ui.date.month_short.${months[date.getMonth()]}`);
}

export function shortDate(seconds: number): string {
  const date = toDate(seconds);
  return t('ui.date.short', date.getDate(), monthShort(date));
}

export function longDate(seconds: number): string {
  const date = toDate(seconds);
  return t('ui.date.long', date.getDate(), monthShort(date), date.getFullYear());
}

export function shiftLabel(seconds: number): string {
  const date = toDate(seconds);
  const hour = date.getHours();
  const shift = hour >= 6 && hour < 18 ? 'ui.date.day_shift' : 'ui.date.night_shift';
  return t(shift, t(`ui.date.weekday.${weekdays[date.getDay()]}`), date.getDate(), t(`ui.date.month.${months[date.getMonth()]}`));
}

export function age(seconds: number, now: number): string {
  const diff = Math.max(0, now - seconds);

  if (diff < 60) return t('ui.time.now');
  if (diff < 3600) return t('ui.time.minutes', Math.floor(diff / 60));
  if (diff < 86400) return t('ui.time.hours', Math.floor(diff / 3600));
  return t('ui.time.days', Math.floor(diff / 86400));
}

export function ago(seconds: number, now: number): string {
  return now - seconds < 60 ? t('ui.time.just_now') : t('ui.time.ago', age(seconds, now));
}

export function money(value: number): string {
  return `$${value.toLocaleString('en-US')}`;
}

export function distance(meters: number): string {
  if (meters < 1000) return t('ui.common.meters', Math.round(meters));
  return t('ui.common.kilometers', (meters / 1000).toFixed(1));
}

export function initials(name: string): string {
  const parts = name.replace(/^Dr\.\s+/, '').split(/\s+/);
  return parts
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join('');
}

export function plural(count: number, key: string): string {
  return t(`${key}.${count === 1 ? 'one' : 'other'}`, count);
}

export function statusLabel(status: StaffStatus): string {
  return t(`ui.status.${status}`);
}

export const statusDots: Record<StaffStatus, string> = {
  available: 'bg-success',
  busy: 'bg-destructive',
  enroute: 'bg-primary',
  onscene: 'bg-warning',
  break: 'bg-warning',
  offduty: 'bg-muted-foreground',
};

export const medicStatuses: MedicStatus[] = ['available', 'enroute', 'onscene', 'busy', 'break'];

export function bodyPartLabel(part: BodyPart): string {
  return t(`ui.body_part.${part}`);
}

export const bodyParts: BodyPart[] = ['head', 'torso', 'left_arm', 'right_arm', 'left_leg', 'right_leg'];

export const injuryKinds: InjuryKind[] = ['bleeding', 'fracture', 'burn', 'severed'];

export function injuryLabel(kind: InjuryKind): string {
  return t(`ui.injury.${kind}`);
}

export const injuryDots: Record<InjuryKind, string> = {
  bleeding: 'bg-destructive',
  fracture: 'bg-warning',
  burn: 'bg-warning',
  severed: 'bg-destructive',
};

export function outcomeLabel(outcome: ReportOutcome): string {
  return t(`ui.outcome.${outcome}`);
}

export function invoiceStatusLabel(status: InvoiceStatus): string {
  return t(`ui.invoice_status.${status}`);
}

export function prescriptionStatusLabel(status: PrescriptionStatus): string {
  return t(`ui.prescription_status.${status}`);
}

export function reportNumber(id: number): string {
  return t('ui.common.report_number', id);
}

export function invoiceNumber(id: number): string {
  return t('ui.common.invoice_number', id);
}

export function prescriptionNumber(id: number): string {
  return t('ui.common.prescription_number', id);
}

export function countdown(seconds: number): string {
  const value = Math.max(0, Math.floor(seconds));
  return `${Math.floor(value / 60)}:${pad(value % 60)}`;
}

export function capitalise(value: string): string {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
