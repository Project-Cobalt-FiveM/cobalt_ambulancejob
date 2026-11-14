<script lang="ts">
  import { onMount } from 'svelte';
  import PlusSquare from 'phosphor-svelte/lib/PlusSquare';
  import Receipt from 'phosphor-svelte/lib/Receipt';
  import Clock from 'phosphor-svelte/lib/Clock';
  import Prohibit from 'phosphor-svelte/lib/Prohibit';
  import Trash from 'phosphor-svelte/lib/Trash';
  import Plus from 'phosphor-svelte/lib/Plus';
  import Header from '../components/Header.svelte';
  import PatientField from '../components/records/PatientField.svelte';
  import Button from '../components/ui/Button.svelte';
  import Tabs from '../components/ui/Tabs.svelte';
  import Dialog from '../components/ui/Dialog.svelte';
  import Field from '../components/ui/Field.svelte';
  import Dot from '../components/ui/Dot.svelte';
  import Empty from '../components/ui/Empty.svelte';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { invoiceNumber, invoiceStatusLabel, money, plural, shortDate } from '../lib/format';
  import { t } from '../lib/locale.svelte';
  import { crossfade } from '../lib/motion';
  import type { Billing, Created, Invoice, InvoiceLine, InvoiceStatus, PatientSummary, Result } from '../lib/types';

  type Filter = 'all' | InvoiceStatus;

  type Draft = { patient: PatientSummary | null; lines: InvoiceLine[] };

  const statusDots: Record<InvoiceStatus, string> = {
    overdue: 'bg-destructive',
    unpaid: 'bg-warning',
    paid: 'bg-success',
    void: 'bg-muted-foreground',
  };

  let billing = $state<Billing>({ stats: { billedWeek: 0, paidWeek: 0, overdue: 0 }, invoices: [] });
  let filter = $state<Filter>('unpaid');
  let selectedId = $state<number | null>(null);
  let draft = $state<Draft | null>(null);
  let voiding = $state<Invoice | null>(null);
  let reason = $state('');
  let busy = $state(false);

  const invoices = $derived(billing.invoices);
  const open = $derived(invoices.filter(isOpen));
  const unpaidTotal = $derived(open.reduce((sum, entry) => sum + entry.amount, 0));
  const list = $derived(invoices.filter((entry) => matches(entry, filter)));
  const selected = $derived(list.find((entry) => entry.id === selectedId) ?? list[0] ?? null);
  const send = $derived(mdt.can('sendInvoices'));
  const draftTotal = $derived(draft ? draft.lines.reduce((sum, line) => sum + (line.amount || 0), 0) : 0);
  const valid = $derived(draft !== null && draft.patient !== null && draft.lines.length > 0 && draft.lines.every(isFilled));
  const stats = $derived([
    { label: t('ui.billing.billed_week'), value: billing.stats.billedWeek },
    { label: t('ui.billing.paid_week'), value: billing.stats.paidWeek },
    { label: t('ui.invoice_status.overdue'), value: billing.stats.overdue },
  ]);

  async function load() {
    billing = mdt.single(await fetchNui('getBilling')) ?? billing;
  }

  onMount(load);

  function isFilled(line: InvoiceLine): boolean {
    return line.label.trim() !== '' && line.amount > 0;
  }

  function isOpen(entry: Invoice): boolean {
    return entry.status === 'unpaid' || entry.status === 'overdue';
  }

  function matches(entry: Invoice, value: Filter): boolean {
    if (value === 'all') return true;
    if (value === 'unpaid') return isOpen(entry);
    return entry.status === value;
  }

  function count(value: Filter): number {
    return invoices.filter((entry) => matches(entry, value)).length;
  }

  function daysOverdue(entry: Invoice): number {
    return Math.max(1, Math.floor((mdt.now - entry.dueAt) / 86400));
  }

  async function changed(result: Result | Created | null, text: string): Promise<boolean> {
    if (!mdt.report(result, text)) return false;

    await load();
    void mdt.refreshUnpaid();
    return true;
  }

  async function charge(entry: Invoice) {
    await changed(await fetchNui('chargeInvoice', { id: entry.id }), t('ui.billing.charged_toast', invoiceNumber(entry.id)));
  }

  async function markPaid(entry: Invoice) {
    await changed(await fetchNui('markInvoicePaid', { id: entry.id }), t('ui.billing.paid_toast', invoiceNumber(entry.id)));
  }

  function startVoid(entry: Invoice) {
    reason = '';
    voiding = entry;
  }

  async function confirmVoid(entry: Invoice) {
    if (!reason.trim()) return;

    const result = await fetchNui('voidInvoice', { id: entry.id, reason: reason.trim() });

    if (await changed(result, t('ui.billing.voided_toast', invoiceNumber(entry.id)))) voiding = null;
  }

  function startNew() {
    draft = { patient: null, lines: [{ label: '', amount: 0 }] };
  }

  async function create() {
    if (!draft?.patient || !valid || busy) return;
    busy = true;

    const lines = draft.lines.map((line) => ({ label: line.label.trim(), amount: Math.round(line.amount) }));
    const result = await fetchNui('createInvoice', { citizenid: draft.patient.citizenid, lines });

    busy = false;
    if (!mdt.report(result, t('ui.billing.sent_toast'))) return;

    draft = null;
    filter = 'unpaid';
    selectedId = result.id;
    await load();
    void mdt.refreshUnpaid();
  }
</script>

<Header title={t('ui.sidebar.billing')} subtitle={t('ui.billing.subtitle', money(unpaidTotal), plural(open.length, 'ui.plural.invoices'))}>
  {#snippet action()}
    {#if send}<Button variant="primary" onclick={startNew}><PlusSquare size="1rem" />{t('ui.billing.new')}</Button>{/if}
  {/snippet}
</Header>

<div class="flex min-h-0 flex-1" in:crossfade>
  <section class="flex min-w-0 flex-1 flex-col gap-4 overflow-y-auto p-6">
    <div class="flex gap-3">
      {#each stats as stat (stat.label)}
        <div class="flex flex-1 flex-col gap-1.5 rounded-lg border border-border px-4 py-3.5">
          <span class="text-13 text-muted-foreground">{stat.label}</span>
          <span class="text-[1.375rem] leading-7 font-semibold tabular-nums">{money(stat.value)}</span>
        </div>
      {/each}
    </div>
    <Tabs
      bind:value={filter}
      tabs={[
        { value: 'all', label: t('ui.common.all'), count: count('all') },
        { value: 'unpaid', label: t('ui.invoice_status.unpaid'), count: count('unpaid') },
        { value: 'overdue', label: t('ui.invoice_status.overdue'), count: count('overdue') },
        { value: 'paid', label: t('ui.invoice_status.paid'), count: count('paid') },
        { value: 'void', label: t('ui.invoice_status.void'), count: count('void') },
      ]}
    />
    <div class="overflow-hidden rounded-lg border border-border">
      <div class="flex items-center gap-4 border-b border-border bg-muted px-4 py-2.5 text-xs font-medium text-muted-foreground">
        <span class="w-20 shrink-0">{t('ui.reports.invoice')}</span>
        <span class="flex-1">{t('ui.common.patient')}</span>
        <span class="w-25 shrink-0">{t('ui.common.status')}</span>
        <span class="w-22.5 shrink-0">{t('ui.billing.due')}</span>
        <span class="w-20 shrink-0 text-right">{t('ui.billing.amount')}</span>
      </div>
      {#each list as entry (entry.id)}
        {@const active = entry.id === selected?.id}
        <button
          type="button"
          class="flex w-full items-center gap-4 border-b border-border px-4 py-3 text-left text-13 transition-colors last:border-b-0 {active ? 'bg-primary' : 'hover:bg-muted'}"
          onclick={() => (selectedId = entry.id)}
        >
          <span class="w-20 shrink-0 tabular-nums {active ? '' : 'text-muted-foreground'}">{invoiceNumber(entry.id)}</span>
          <span class="flex min-w-0 flex-1 flex-col gap-0.5">
            <span class="truncate text-sm {active ? 'font-semibold' : 'font-medium'}">{entry.patientName}</span>
            <span class="truncate text-xs {active ? '' : 'text-muted-foreground'}">{entry.summary}</span>
          </span>
          <span class="flex w-25 shrink-0 items-center gap-1.5">
            <Dot class={active ? 'bg-foreground' : statusDots[entry.status]} size="size-1.5" />
            {invoiceStatusLabel(entry.status)}
          </span>
          <span class="w-22.5 shrink-0 tabular-nums">{shortDate(entry.dueAt)}</span>
          <span class="w-20 shrink-0 text-right tabular-nums {active ? 'font-semibold' : ''}">{money(entry.amount)}</span>
        </button>
      {:else}
        <p class="px-4 py-8 text-center text-sm text-muted-foreground">{t('ui.billing.empty')}</p>
      {/each}
    </div>
  </section>

  <aside class="flex w-100 shrink-0 flex-col border-l border-border">
    {#if selected}
      {#key selected.id}
        <div class="flex min-h-0 flex-1 flex-col gap-4.5 overflow-y-auto p-6" in:crossfade>
          <div class="flex flex-col gap-1">
            <span class="text-13 text-muted-foreground tabular-nums">
              {selected.paidAt != null ? t('ui.billing.heading_paid', invoiceNumber(selected.id), shortDate(selected.createdAt), shortDate(selected.paidAt)) : t('ui.billing.heading', invoiceNumber(selected.id), shortDate(selected.createdAt))}
            </span>
            <button type="button" class="text-left text-xl font-semibold tracking-[-0.01em] hover:text-cobalt-foreground" onclick={() => selected && mdt.openPatient(selected.citizenid)}>{selected.patientName}</button>
          </div>
          {#if selected.status === 'overdue'}
            <div class="flex gap-2.5 rounded-lg border border-border p-3">
              <Clock size="1rem" class="shrink-0 text-destructive" />
              <div class="flex flex-col gap-0.5">
                <span class="text-sm font-medium">{t('ui.billing.overdue_by', plural(daysOverdue(selected), 'ui.plural.days'))}</span>
                {#if selected.declinedAt != null}
                  <span class="text-13 text-muted-foreground">{t('ui.billing.declined', shortDate(selected.declinedAt))}</span>
                {/if}
              </div>
            </div>
          {:else if selected.status === 'void'}
            <div class="flex gap-2.5 rounded-lg border border-border p-3">
              <Prohibit size="1rem" class="shrink-0 text-muted-foreground" />
              <div class="flex flex-col gap-0.5">
                <span class="text-sm font-medium">{t('ui.billing.voided')}</span>
                <span class="text-13 text-muted-foreground">{selected.voidReason ?? t('ui.billing.no_reason')}</span>
              </div>
            </div>
          {/if}
          <div class="flex flex-col">
            {#each selected.lines as line, index (index)}
              <div class="flex justify-between gap-4 border-b border-border py-2.5 text-13">
                <span>{line.label}</span>
                <span class="tabular-nums">{money(line.amount)}</span>
              </div>
            {/each}
            <div class="flex items-center justify-between py-3">
              <span class="text-sm font-medium text-muted-foreground">{t('ui.common.total')}</span>
              <span class="text-xl leading-6 font-semibold tabular-nums">{money(selected.amount)}</span>
            </div>
          </div>
        </div>
        {#if isOpen(selected) && (send || mdt.can('voidInvoices'))}
          <div class="flex flex-col gap-2 px-6 pb-6">
            {#if send}<Button variant="primary" onclick={() => selected && charge(selected)}>{t('ui.billing.charge_again')}</Button>{/if}
            <div class="flex gap-2">
              {#if send}<Button class="flex-1" onclick={() => selected && markPaid(selected)}>{t('ui.billing.mark_paid')}</Button>{/if}
              {#if mdt.can('voidInvoices')}<Button variant="destructive" class="flex-1" onclick={() => selected && startVoid(selected)}>{t('ui.billing.void')}</Button>{/if}
            </div>
          </div>
        {/if}
      {/key}
    {:else}
      <Empty icon={Receipt} title={t('ui.billing.none_selected')} body={t('ui.billing.none_selected_body')} />
    {/if}
  </aside>
</div>

{#if voiding}
  {@const target = voiding}
  <Dialog
    title={t('ui.billing.void_title', invoiceNumber(target.id))}
    description={t('ui.billing.void_description', target.patientName, money(target.amount))}
    width="w-110"
    onclose={() => (voiding = null)}
  >
    <Field label={t('ui.common.reason')}><input class="field" bind:value={reason} maxlength="120" placeholder={t('ui.billing.void_placeholder')} /></Field>
    {#snippet actions()}
      <Button onclick={() => (voiding = null)}>{t('ui.common.cancel')}</Button>
      <Button variant="destructive" disabled={!reason.trim()} onclick={() => confirmVoid(target)}>{t('ui.billing.void')}</Button>
    {/snippet}
  </Dialog>
{/if}

{#if draft}
  {@const current = draft}
  <Dialog title={t('ui.billing.new')} description={t('ui.billing.new_description')} width="w-[32rem]" onclose={() => (draft = null)}>
    <PatientField bind:patient={current.patient} />
    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium">{t('ui.billing.lines')}</span>
      {#each current.lines as line, index (index)}
        <div class="flex items-center gap-2">
          <input class="field flex-1" bind:value={line.label} maxlength="60" placeholder={t('ui.billing.line_placeholder')} aria-label={t('ui.billing.line_label', index + 1)} />
          <span class="field flex w-28 shrink-0 items-center gap-1 focus-within:border-primary">
            <span class="text-muted-foreground">$</span>
            <input class="h-full min-w-0 flex-1 bg-transparent tabular-nums outline-none" type="number" min="0" bind:value={line.amount} aria-label={t('ui.billing.line_amount', index + 1)} />
          </span>
          <Button variant="ghost" size="icon" aria-label={t('ui.billing.remove_line')} disabled={current.lines.length === 1} onclick={() => current.lines.splice(index, 1)}><Trash size="1rem" /></Button>
        </div>
      {/each}
      <div class="flex items-center justify-between">
        <Button variant="link" onclick={() => current.lines.push({ label: '', amount: 0 })}><Plus size="0.875rem" />{t('ui.billing.add_line')}</Button>
        <span class="text-sm font-semibold tabular-nums">{money(draftTotal)}</span>
      </div>
    </div>
    {#snippet actions()}
      <Button onclick={() => (draft = null)}>{t('ui.common.cancel')}</Button>
      <Button variant="primary" disabled={!valid || busy} onclick={create}>{t('ui.billing.send')}</Button>
    {/snippet}
  </Dialog>
{/if}
