<script lang="ts">
  import { onMount } from 'svelte';
  import PlusSquare from 'phosphor-svelte/lib/PlusSquare';
  import Pill from 'phosphor-svelte/lib/Pill';
  import Header from '../components/Header.svelte';
  import PatientField from '../components/records/PatientField.svelte';
  import Button from '../components/ui/Button.svelte';
  import Tabs from '../components/ui/Tabs.svelte';
  import Row from '../components/ui/Row.svelte';
  import Dialog from '../components/ui/Dialog.svelte';
  import Field from '../components/ui/Field.svelte';
  import Toggle from '../components/ui/Toggle.svelte';
  import Empty from '../components/ui/Empty.svelte';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { longDate, prescriptionNumber, shortDate } from '../lib/format';
  import { crossfade } from '../lib/motion';
  import { t } from '../lib/locale.svelte';
  import type { PatientSummary, Prescription, PrescriptionInput } from '../lib/types';

  type Filter = 'active' | 'ending' | 'expired' | 'cancelled';

  type Draft = Omit<PrescriptionInput, 'citizenid'> & { patient: PatientSummary | null };

  const week = 7 * 86400;

  let prescriptions = $state<Prescription[]>([]);
  let filter = $state<Filter>('active');
  let selectedId = $state<number | null>(null);
  let draft = $state<Draft | null>(null);
  let cancelling = $state<Prescription | null>(null);
  let busy = $state(false);

  const write = $derived(mdt.can('writePrescriptions'));
  const list = $derived(prescriptions.filter((entry) => matches(entry, filter)));
  const selected = $derived(list.find((entry) => entry.id === selectedId) ?? list[0] ?? null);
  const valid = $derived(draft !== null && isComplete(draft));

  async function load() {
    prescriptions = mdt.list(await fetchNui('getPrescriptions')) ?? prescriptions;
  }

  onMount(load);

  function isComplete(value: Draft): boolean {
    if (!value.patient || !value.medication.trim() || !value.dose.trim()) return false;

    return value.refills >= 0 && value.days >= 1;
  }

  function endingSoon(entry: Prescription): boolean {
    return entry.status === 'active' && entry.endsAt - mdt.now <= week;
  }

  function matches(entry: Prescription, value: Filter): boolean {
    return value === 'ending' ? endingSoon(entry) : entry.status === value;
  }

  function count(value: Filter): number {
    return prescriptions.filter((entry) => matches(entry, value)).length;
  }

  function startNew() {
    draft = { patient: null, medication: '', dose: '', reason: '', refills: 0, days: 30, controlled: false };
  }

  async function create() {
    if (!draft?.patient || !valid || busy) return;
    busy = true;

    const result = await fetchNui('createPrescription', {
      citizenid: draft.patient.citizenid,
      medication: draft.medication.trim(),
      dose: draft.dose.trim(),
      reason: draft.reason.trim(),
      refills: draft.refills,
      days: draft.days,
      controlled: draft.controlled && mdt.can('prescribeControlled'),
    });

    busy = false;
    if (!mdt.report(result, t('ui.prescriptions.written_toast'))) return;

    draft = null;
    filter = 'active';
    selectedId = result.id;
    await load();
  }

  async function renew(entry: Prescription) {
    if (mdt.report(await fetchNui('renewPrescription', { id: entry.id }), t('ui.prescriptions.renewed_toast', prescriptionNumber(entry.id)))) await load();
  }

  async function cancel(entry: Prescription) {
    if (!mdt.report(await fetchNui('cancelPrescription', { id: entry.id }), t('ui.prescriptions.cancelled_toast', prescriptionNumber(entry.id)))) return;

    cancelling = null;
    await load();
  }
</script>

<Header title={t('ui.sidebar.prescriptions')} subtitle={t('ui.prescriptions.subtitle')}>
  {#snippet action()}
    {#if write}<Button variant="primary" onclick={startNew}><PlusSquare size="1rem" />{t('ui.prescriptions.new')}</Button>{/if}
  {/snippet}
</Header>

<div class="flex min-h-0 flex-1" in:crossfade>
  <section class="flex min-w-0 flex-1 flex-col gap-4 overflow-y-auto p-6">
    <Tabs
      bind:value={filter}
      tabs={[
        { value: 'active', label: t('ui.prescription_status.active'), count: count('active') },
        { value: 'ending', label: t('ui.prescriptions.ending'), count: count('ending') },
        { value: 'expired', label: t('ui.prescription_status.expired'), count: count('expired') },
        { value: 'cancelled', label: t('ui.prescription_status.cancelled'), count: count('cancelled') },
      ]}
    />
    <div class="overflow-hidden rounded-lg border border-border">
      <div class="flex items-center gap-4 border-b border-border bg-muted px-4 py-2.5 text-xs font-medium text-muted-foreground">
        <span class="w-37.5 shrink-0">{t('ui.common.patient')}</span>
        <span class="flex-1">{t('ui.prescriptions.medication_and_dose')}</span>
        <span class="w-20 shrink-0">{t('ui.prescriptions.refills')}</span>
        <span class="w-35 shrink-0">{t('ui.prescriptions.prescriber')}</span>
        <span class="w-20 shrink-0 text-right">{t('ui.prescriptions.ends')}</span>
      </div>
      {#each list as entry (entry.id)}
        {@const active = entry.id === selected?.id}
        <button
          type="button"
          class="flex w-full items-center gap-4 border-b border-border px-4 py-3 text-left transition-colors last:border-b-0 {active ? 'bg-primary' : 'hover:bg-muted'}"
          onclick={() => (selectedId = entry.id)}
        >
          <span class="w-37.5 shrink-0 truncate text-sm {active ? 'font-semibold' : 'font-medium'}">{entry.patientName}</span>
          <span class="flex min-w-0 flex-1 flex-col gap-0.5">
            <span class="truncate text-sm font-medium">{entry.medication}</span>
            <span class="truncate text-xs {active ? '' : 'text-muted-foreground'}">{entry.dose}</span>
          </span>
          <span class="w-20 shrink-0 text-13 tabular-nums">{t('ui.common.x_of_y', entry.refillsUsed, entry.refills)}</span>
          <span class="w-35 shrink-0 truncate text-13">{entry.prescriber}</span>
          <span class="w-20 shrink-0 text-right text-13 tabular-nums {active ? '' : endingSoon(entry) ? 'text-warning' : 'text-muted-foreground'}">{shortDate(entry.endsAt)}</span>
        </button>
      {:else}
        <p class="px-4 py-8 text-center text-sm text-muted-foreground">{t('ui.prescriptions.empty')}</p>
      {/each}
    </div>
  </section>

  <aside class="flex w-100 shrink-0 flex-col border-l border-border">
    {#if selected}
      {#key selected.id}
        <div class="flex min-h-0 flex-1 flex-col gap-4.5 overflow-y-auto p-6" in:crossfade>
          <div class="flex flex-col gap-1">
            <span class="text-13 text-muted-foreground tabular-nums">
              {t('ui.prescriptions.heading', prescriptionNumber(selected.id))}
              <button type="button" class="hover:text-foreground" onclick={() => selected && mdt.openPatient(selected.citizenid)}>{selected.patientName}</button>
            </span>
            <h2 class="text-xl font-semibold tracking-[-0.01em]">{selected.medication}</h2>
          </div>
          <div class="flex flex-col">
            <Row label={t('ui.prescriptions.dose')}>{selected.dose}</Row>
            <Row label={t('ui.common.reason')}>{selected.reason || t('ui.prescriptions.no_reason')}</Row>
            <Row label={t('ui.prescriptions.written')}>{shortDate(selected.createdAt)}, {selected.prescriber}</Row>
            <Row label={t('ui.prescriptions.valid_until')} tone={endingSoon(selected) ? 'warning' : 'default'}>{longDate(selected.endsAt)}</Row>
            <Row label={t('ui.prescriptions.refills_used')}>{t('ui.common.x_of_y', selected.refillsUsed, selected.refills)}</Row>
            <Row label={t('ui.prescriptions.last_filled')}>
              {#if selected.lastFill}
                {shortDate(selected.lastFill.at)}, {selected.lastFill.pharmacy}
              {:else}
                <span class="text-muted-foreground">{t('ui.prescriptions.not_filled')}</span>
              {/if}
            </Row>
          </div>
        </div>
        {#if write && selected.status !== 'cancelled'}
          <div class="flex gap-2 px-6 pb-6">
            <Button variant="primary" class="flex-1" onclick={() => selected && renew(selected)}>{t('ui.prescriptions.renew')}</Button>
            {#if selected.status === 'active'}
              <Button class="flex-1" onclick={() => (cancelling = selected)}>{t('ui.prescriptions.cancel')}</Button>
            {/if}
          </div>
        {/if}
      {/key}
    {:else}
      <Empty icon={Pill} title={t('ui.prescriptions.none_selected')} body={t('ui.prescriptions.none_selected_body')} />
    {/if}
  </aside>
</div>

{#if draft}
  {@const current = draft}
  <Dialog title={t('ui.prescriptions.new')} description={t('ui.prescriptions.new_description')} width="w-[32rem]" onclose={() => (draft = null)}>
    <PatientField bind:patient={current.patient} />
    <div class="grid grid-cols-2 gap-3">
      <Field label={t('ui.prescriptions.medication')}><input class="field" bind:value={current.medication} maxlength="60" placeholder={t('ui.prescriptions.medication_placeholder')} /></Field>
      <Field label={t('ui.common.reason')}><input class="field" bind:value={current.reason} maxlength="80" placeholder={t('ui.prescriptions.reason_placeholder')} /></Field>
    </div>
    <Field label={t('ui.prescriptions.dose')}><input class="field" bind:value={current.dose} maxlength="120" placeholder={t('ui.prescriptions.dose_placeholder')} /></Field>
    <div class="grid grid-cols-2 gap-3">
      <Field label={t('ui.prescriptions.refills')}><input class="field tabular-nums" type="number" min="0" max="12" bind:value={current.refills} /></Field>
      <Field label={t('ui.prescriptions.valid_days')}><input class="field tabular-nums" type="number" min="1" max="90" bind:value={current.days} /></Field>
    </div>
    <div class="flex items-center gap-3 rounded-lg border border-border px-4 py-3">
      <div class="flex flex-1 flex-col gap-0.5">
        <span class="text-sm font-medium">{t('ui.prescriptions.controlled')}</span>
        {#if !mdt.can('prescribeControlled')}<span class="text-xs text-muted-foreground">{t('ui.prescriptions.controlled_locked')}</span>{/if}
      </div>
      <Toggle label={t('ui.prescriptions.controlled')} bind:checked={current.controlled} disabled={!mdt.can('prescribeControlled')} />
    </div>
    {#snippet actions()}
      <Button onclick={() => (draft = null)}>{t('ui.common.cancel')}</Button>
      <Button variant="primary" disabled={!valid || busy} onclick={create}>{t('ui.prescriptions.write')}</Button>
    {/snippet}
  </Dialog>
{/if}

{#if cancelling}
  {@const target = cancelling}
  <Dialog title={t('ui.prescriptions.cancel_title', prescriptionNumber(target.id))} description={t('ui.prescriptions.cancel_description', target.medication, target.patientName)} onclose={() => (cancelling = null)}>
    {#snippet actions()}
      <Button onclick={() => (cancelling = null)}>{t('ui.prescriptions.keep')}</Button>
      <Button variant="destructive" onclick={() => cancel(target)}>{t('ui.prescriptions.cancel')}</Button>
    {/snippet}
  </Dialog>
{/if}
