import { longDate, money } from '../../lib/format';
import { t } from '../../lib/locale.svelte';
import type { ReportSummary, Treatment } from '../../lib/types';

export const bloodTypes = ['O negative', 'O positive', 'A negative', 'A positive', 'B negative', 'B positive', 'AB negative', 'AB positive'];

export function shortBlood(bloodType: string | null): string {
  if (!bloodType) return t('ui.common.unknown');

  return bloodType.replace(/negative$/i, 'neg').replace(/positive$/i, 'pos');
}

export function bornOn(dob: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dob);
  if (!match) return dob;

  const [, year, month, day] = match;
  return longDate(new Date(Number(year), Number(month) - 1, Number(day)).getTime() / 1000);
}

export function billedLabel(report: Pick<ReportSummary, 'billing' | 'billed'>): string {
  if (report.billing === 'waived') return t('ui.reports.waived');
  if (report.billing === 'pending' || report.billed === null) return t('ui.reports.not_yet');
  return money(report.billed);
}

export function tally(ids: number[], catalogue: Map<number, Treatment>): { treatment: Treatment; count: number }[] {
  const counts = new Map<number, number>();
  for (const id of ids) counts.set(id, (counts.get(id) ?? 0) + 1);

  return [...counts].flatMap(([id, count]) => {
    const treatment = catalogue.get(id);
    return treatment ? [{ treatment, count }] : [];
  });
}

export function times(name: string, count: number): string {
  return count > 1 ? t('ui.common.times', name, count) : name;
}
