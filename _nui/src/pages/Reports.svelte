<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import PlusSquare from 'phosphor-svelte/lib/PlusSquare';
  import MagnifyingGlass from 'phosphor-svelte/lib/MagnifyingGlass';
  import FileText from 'phosphor-svelte/lib/FileText';
  import Header from '../components/Header.svelte';
  import Button from '../components/ui/Button.svelte';
  import Tabs from '../components/ui/Tabs.svelte';
  import Row from '../components/ui/Row.svelte';
  import Empty from '../components/ui/Empty.svelte';
  import { billedLabel, tally, times } from '../components/records/format';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { clockTime, invoiceNumber, invoiceStatusLabel, outcomeLabel, reportNumber, shortDate } from '../lib/format';
  import { t } from '../lib/locale.svelte';
  import { crossfade } from '../lib/motion';
  import type { Report, ReportSummary, Treatment } from '../lib/types';

  type Filter = 'all' | 'mine' | 'drafts' | 'deaths';

  let { initial }: { initial: number | null } = $props();

  let all = $state<ReportSummary[]>([]);
  let catalogue = $state.raw(new Map<number, Treatment>());
  let filter = $state<Filter>('all');
  let query = $state('');
  let selectedId = $state<number | null>(untrack(() => initial));
  let detail = $state<Report | null>(null);

  const matches: Record<Filter, (report: ReportSummary) => boolean> = {
    all: () => true,
    mine: (report) => report.medicCitizenid !== null && report.medicCitizenid === mdt.medic?.citizenid,
    drafts: (report) => report.status === 'draft',
    deaths: (report) => report.outcome === 'deceased',
  };

  const list = $derived(all.filter((report) => matches[filter](report) && matchesQuery(report, query.trim().toLowerCase())));

  const count = (value: Filter) => all.filter(matches[value]).length;

  function matchesQuery(report: ReportSummary, text: string): boolean {
    if (!text) return true;

    return [report.patientName, report.summary, reportNumber(report.id)].some((field) => field.toLowerCase().includes(text));
  }

  async function load() {
    const reports = mdt.list(await fetchNui('getReports'));
    if (!reports) return;

    all = reports;
    if (!all.some((report) => report.id === selectedId)) selectedId = all[0]?.id ?? null;
  }

  async function loadDetail(id: number) {
    const report = mdt.single(await fetchNui('getReport', { id }));
    if (selectedId === id) detail = report;
  }

  onMount(() => {
    void load();
    void fetchNui('getTreatments').then((reply) => {
      const treatments = mdt.list(reply);
      if (treatments) catalogue = new Map(treatments.map((treatment) => [treatment.id, treatment]));
    });
  });

  $effect(() => {
    const id = selectedId;
    detail = null;
    if (id !== null) void loadDetail(id);
  });

  function summaryLine(report: ReportSummary): string {
    if (report.status !== 'draft') return report.summary;
    return t('ui.reports.draft_summary', `${report.summary.charAt(0).toLowerCase()}${report.summary.slice(1)}`);
  }

  function treatmentsGiven(report: Report): string {
    const ids = report.injuries.flatMap((injury) => injury.treatments);
    return tally(ids, catalogue).map(({ treatment, count }) => times(treatment.name, count)).join(', ') || t('ui.common.none');
  }

  function medicationsGiven(report: Report): string {
    return tally(report.medications, catalogue).map(({ treatment, count }) => times(treatment.name, count)).join(', ') || t('ui.common.none');
  }

  async function toggleShare(report: Report) {
    const shared = !report.sharedWithPolice;
    const result = await fetchNui('shareReport', { id: report.id, shared });

    if (mdt.report(result, shared ? t('ui.reports.shared_toast') : t('ui.reports.unshared_toast'))) await loadDetail(report.id);
  }

  function open(report: ReportSummary) {
    mdt.editReport({ id: report.id, citizenid: report.citizenid, callId: null, templateId: null });
  }
</script>

<Header title={t('ui.sidebar.reports')} subtitle={t('ui.reports.subtitle')}>
  {#snippet action()}
    {#if mdt.can('writeReports')}
      <Button variant="primary" onclick={() => mdt.newReport()}><PlusSquare size="1rem" />{t('ui.common.new_report')}</Button>
    {/if}
  {/snippet}
</Header>

<div class="flex min-h-0 flex-1" in:crossfade>
  <section class="flex min-w-0 flex-1 flex-col gap-4 overflow-y-auto p-6">
    <div class="flex items-center gap-4">
      <div class="flex-1">
        <Tabs
          bind:value={filter}
          tabs={[
            { value: 'all', label: t('ui.common.all'), count: all.length },
            { value: 'mine', label: t('ui.common.mine'), count: count('mine') },
            { value: 'drafts', label: t('ui.reports.drafts'), count: count('drafts') },
            { value: 'deaths', label: t('ui.reports.deaths'), count: count('deaths') },
          ]}
        />
      </div>
      <label class="flex h-8 w-65 shrink-0 items-center gap-2 rounded-md border border-input px-3 focus-within:border-primary">
        <MagnifyingGlass size="0.875rem" class="text-muted-foreground" />
        <input bind:value={query} placeholder={t('ui.reports.filter_placeholder')} aria-label={t('ui.reports.filter')} class="h-full min-w-0 flex-1 bg-transparent text-13 outline-none" />
      </label>
    </div>

    <div class="overflow-hidden rounded-lg border border-border">
      <div class="grid grid-cols-[3.75rem_1fr_7.5rem_7.5rem_5rem] gap-4 border-b border-border bg-muted px-4 py-2.5 text-xs font-medium text-muted-foreground">
        <span>{t('ui.common.report')}</span><span>{t('ui.reports.patient_and_injuries')}</span><span>{t('ui.common.medic')}</span><span>{t('ui.common.outcome')}</span><span class="text-right">{t('ui.reports.billed')}</span>
      </div>
      {#each list as report (report.id)}
        {@const active = report.id === selectedId}
        {@const quiet = active ? '' : 'text-muted-foreground'}
        <button
          type="button"
          class="grid w-full grid-cols-[3.75rem_1fr_7.5rem_7.5rem_5rem] items-center gap-4 border-b border-border px-4 py-3 text-left transition-colors last:border-b-0 {active ? 'bg-primary' : 'hover:bg-muted'}"
          onclick={() => (selectedId = report.id)}
          ondblclick={() => open(report)}
        >
          <span class="text-13 tabular-nums {quiet}">{reportNumber(report.id)}</span>
          <span class="flex min-w-0 flex-col gap-0.5">
            <span class="truncate text-sm {active ? 'font-semibold' : 'font-medium'}">{report.patientName}</span>
            <span class="truncate text-xs {report.status === 'draft' && !active ? 'text-warning' : quiet}">{summaryLine(report)}</span>
          </span>
          <span class="truncate text-13 {report.medicCitizenid === null ? quiet : ''}">{report.medic}</span>
          <span class="truncate text-13">{outcomeLabel(report.outcome)}</span>
          <span class="text-right text-13 tabular-nums {report.billing === 'billed' ? '' : quiet}">{billedLabel(report)}</span>
        </button>
      {:else}
        <p class="px-4 py-8 text-center text-sm text-muted-foreground">{t('ui.reports.empty')}</p>
      {/each}
    </div>
  </section>

  <aside class="flex w-100 shrink-0 flex-col border-l border-border">
    {#if detail}
      {@const report = detail}
      {#key report.id}
        <div class="flex min-h-0 flex-1 flex-col gap-4.5 overflow-y-auto p-6" in:crossfade>
          <div class="flex flex-col gap-1">
            <span class="text-13 text-muted-foreground tabular-nums">{t('ui.reports.heading', reportNumber(report.id), shortDate(report.occurredAt), clockTime(report.occurredAt))}</span>
            <h2 class="text-xl font-semibold tracking-[-0.01em]">{report.patientName}</h2>
          </div>
          <p class="text-sm leading-5.5 whitespace-pre-line">{report.narrative || t('ui.reports.no_narrative')}</p>
          <div class="flex flex-col">
            <Row label={t('ui.reports.treatment')}>{treatmentsGiven(report)}</Row>
            <Row label={t('ui.reports.medication')}>{medicationsGiven(report)}</Row>
            {#if report.invoice}
              {@const invoice = report.invoice}
              <Row label={t('ui.reports.invoice')} tone="link">
                <button type="button" class="hover:text-foreground" onclick={() => mdt.go('billing')}>{invoiceNumber(invoice.id)}, {invoiceStatusLabel(invoice.status).toLowerCase()}</button>
              </Row>
            {:else}
              <Row label={t('ui.reports.invoice')}>{report.billing === 'waived' ? t('ui.reports.waived') : t('ui.common.none')}</Row>
            {/if}
            <Row label={t('ui.reports.shared_with_police')}>{report.sharedWithPolice ? t('ui.common.yes') : t('ui.common.no')}</Row>
          </div>
        </div>
        <div class="flex gap-2 px-6 pb-6">
          <Button variant="primary" class="flex-1" onclick={() => open(report)}>{report.status === 'draft' ? t('ui.reports.continue_draft') : t('ui.reports.open_report')}</Button>
          {#if mdt.settings.shareWithPolice && mdt.can('shareReports') && report.status === 'filed'}
            <Button onclick={() => toggleShare(report)}>{report.sharedWithPolice ? t('ui.reports.stop_sharing') : t('ui.reports.share')}</Button>
          {/if}
        </div>
      {/key}
    {:else}
      <Empty icon={FileText} title={t('ui.reports.none_selected')} body={t('ui.reports.none_selected_body')} />
    {/if}
  </aside>
</div>
