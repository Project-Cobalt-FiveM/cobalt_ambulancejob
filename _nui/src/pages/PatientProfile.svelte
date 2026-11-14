<script lang="ts">
  import { onMount } from 'svelte';
  import ArrowLeft from 'phosphor-svelte/lib/ArrowLeft';
  import PlusSquare from 'phosphor-svelte/lib/PlusSquare';
  import UserCircle from 'phosphor-svelte/lib/UserCircle';
  import X from 'phosphor-svelte/lib/X';
  import Header from '../components/Header.svelte';
  import Button from '../components/ui/Button.svelte';
  import Badge from '../components/ui/Badge.svelte';
  import Tabs from '../components/ui/Tabs.svelte';
  import Row from '../components/ui/Row.svelte';
  import { bloodLabel, bornOn } from '../components/records/format';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { bodyPartLabel, bodyParts, injuryLabel, invoiceNumber, invoiceStatusLabel, money, outcomeLabel, prescriptionNumber, prescriptionStatusLabel, reportNumber, shortDate } from '../lib/format';
  import { t } from '../lib/locale.svelte';
  import { crossfade } from '../lib/motion';
  import type { BodyPart, Injury, InjuryKind, Patient, PatientInput, ReportSummary } from '../lib/types';

  type TabKey = 'treatments' | 'prescriptions' | 'invoices' | 'notes';

  let { citizenid }: { citizenid: string } = $props();

  let patient = $state<Patient | null>(null);
  let missing = $state(false);
  let tab = $state<TabKey>('treatments');
  let editing = $state(false);
  let emergencyContact = $state('');
  let notes = $state('');
  let addingCondition = $state(false);
  let condition = $state('');

  const editable = $derived(mdt.can('editPatients'));
  const down = $derived(patient?.state === 'down' || patient?.state === 'dead');

  const injuryBorders: Record<InjuryKind, string> = {
    bleeding: 'border-destructive',
    severed: 'border-destructive',
    fracture: 'border-warning',
    burn: 'border-warning',
  };

  async function load() {
    const result = mdt.single(await fetchNui('getPatient', { citizenid }));
    patient = result;
    missing = result === null;
    notes = result?.notes ?? '';
  }

  onMount(load);

  function input(current: Patient, changes: Partial<PatientInput>): PatientInput {
    return {
      citizenid,
      conditions: [...current.conditions],
      emergencyContact: current.emergencyContact,
      notes: current.notes,
      ...changes,
    };
  }

  async function save(changes: Partial<PatientInput>, success: string): Promise<boolean> {
    if (!patient) return false;

    const saved = mdt.report(await fetchNui('savePatient', input(patient, changes)), success);
    if (saved) await load();
    return saved;
  }

  function startEditing() {
    if (!patient) return;

    emergencyContact = patient.emergencyContact;
    editing = true;
  }

  async function saveDetails() {
    if (await save({ emergencyContact: emergencyContact.trim() }, t('ui.patient.details_saved'))) editing = false;
  }

  async function addCondition() {
    const text = condition.trim();
    if (!patient || !text || patient.conditions.includes(text)) return;

    if (await save({ conditions: [...patient.conditions, text] }, t('ui.patient.condition_added'))) {
      condition = '';
      addingCondition = false;
    }
  }

  async function removeCondition(name: string) {
    if (!patient) return;

    await save({ conditions: patient.conditions.filter((entry) => entry !== name) }, t('ui.patient.condition_removed'));
  }

  async function saveNotes() {
    if (!patient || notes === patient.notes) return;

    await save({ notes }, t('ui.patient.notes_saved'));
  }

  function injuryAt(injuries: Injury[], part: BodyPart): Injury | undefined {
    return injuries.find((injury) => injury.bodyPart === part);
  }

  function reportDetail(report: ReportSummary): string {
    if (report.status === 'draft') return t('ui.patient.draft_not_filed');
    if (report.detail) return report.detail;
    if (report.billing === 'waived') return t('ui.patient.bill_waived');
    if (report.billing === 'pending' || report.billed === null) return t('ui.patient.not_billed');

    return t('ui.patient.billed', money(report.billed));
  }

  function cancelCondition() {
    addingCondition = false;
    condition = '';
  }

  function onConditionKey(event: KeyboardEvent) {
    if (event.key === 'Enter') void addCondition();
  }

  function focus(node: HTMLInputElement) {
    node.focus();
  }

  $effect(() => {
    if (!addingCondition) return;
    return mdt.pushLayer(cancelCondition);
  });
</script>

<Header title={patient?.name ?? (missing ? t('ui.patient.not_found') : t('ui.common.loading'))} subtitle={t('ui.patient.breadcrumb', citizenid)}>
  {#snippet action()}
    <Button variant="ghost" onclick={() => mdt.navigate({ page: 'patients', citizenid: null })}><ArrowLeft size="1rem" />{t('ui.sidebar.patients')}</Button>
    {#if patient && mdt.can('writeReports')}
      <Button variant="primary" onclick={() => mdt.newReport(citizenid)}><PlusSquare size="1rem" />{t('ui.patient.new_report')}</Button>
    {/if}
  {/snippet}
</Header>

{#if patient}
  <div class="flex min-h-0 flex-1" in:crossfade>
    <aside class="flex w-85 shrink-0 flex-col gap-5 overflow-y-auto border-r border-border p-6">
      <div class="flex flex-col gap-3">
        <div class="flex h-35 w-30 items-center justify-center rounded-lg bg-secondary">
          <UserCircle size="3rem" class="text-disabled-icon" />
        </div>
        <div class="flex flex-wrap gap-1">
          {#if down}<Badge tone="danger">{t('ui.patient.down_now')}</Badge>{/if}
        </div>
      </div>

      {#if editing}
        <div class="flex flex-col gap-3" in:crossfade>
          <label class="flex flex-col gap-1.5 text-13">
            <span class="text-muted-foreground">{t('ui.patient.emergency_contact')}</span>
            <input class="field" bind:value={emergencyContact} maxlength="80" placeholder={t('ui.patient.contact_placeholder')} />
          </label>
          <div class="flex gap-2">
            <Button size="sm" onclick={() => (editing = false)}>{t('ui.common.cancel')}</Button>
            <Button size="sm" variant="primary" class="flex-1" onclick={saveDetails}>{t('ui.patient.save_details')}</Button>
          </div>
        </div>
      {:else}
        <div class="flex flex-col">
          <Row label={t('ui.patient.born')}>{bornOn(patient.dob)}</Row>
          <Row label={t('ui.common.blood_type')}><span class="font-semibold">{bloodLabel(patient.bloodType)}</span></Row>
          <Row label={t('ui.patient.phone')}>{patient.phone || t('ui.common.none')}</Row>
          <Row label={t('ui.patient.emergency_contact')}>{patient.emergencyContact || t('ui.common.none')}</Row>
          {#if editable}
            <button type="button" class="self-start pt-2.5 text-13 text-muted-foreground hover:text-foreground" onclick={startEditing}>{t('ui.patient.edit_details')}</button>
          {/if}
        </div>
      {/if}

      <div class="flex flex-col gap-2">
        <h2 class="text-sm font-semibold">{t('ui.patients.conditions')}</h2>
        <div class="flex flex-wrap items-center gap-1.5">
          {#each patient.conditions as name (name)}
            <span class="inline-flex items-center gap-1 rounded-sm bg-secondary py-0.75 pr-1 pl-2 text-13 font-medium">
              {name}
              {#if editable}
                <button type="button" class="rounded-sm p-0.5 text-muted-foreground hover:bg-secondary-hover hover:text-foreground" aria-label={t('ui.common.remove', name)} onclick={() => removeCondition(name)}>
                  <X size="0.625rem" />
                </button>
              {/if}
            </span>
          {:else}
            {#if !editable}<span class="text-13 text-muted-foreground">{t('ui.patient.none_recorded')}</span>{/if}
          {/each}
          {#if editable}
            {#if addingCondition}
              <input
                use:focus
                class="h-6.5 w-40 rounded-sm border border-primary bg-transparent px-2 text-13 outline-none"
                bind:value={condition}
                maxlength="60"
                placeholder={t('ui.patient.condition')}
                aria-label={t('ui.patient.new_condition')}
                onkeydown={onConditionKey}
                onblur={cancelCondition}
              />
            {:else}
              <button type="button" class="rounded-sm border border-dashed border-input px-2 py-0.5 text-13 font-medium text-muted-foreground hover:text-foreground" onclick={() => (addingCondition = true)}>{t('ui.common.add')}</button>
            {/if}
          {/if}
        </div>
      </div>
    </aside>

    <section class="flex min-w-0 flex-1 flex-col gap-5 overflow-y-auto p-6">
      <div class="border-b border-border pb-4">
        <Tabs
          bind:value={tab}
          tabs={[
            { value: 'treatments', label: t('ui.patient.tab_treatments'), count: patient.reports.length },
            { value: 'prescriptions', label: t('ui.sidebar.prescriptions'), count: patient.prescriptions.length },
            { value: 'invoices', label: t('ui.patient.tab_invoices'), count: patient.invoices.length },
            { value: 'notes', label: t('ui.patient.tab_notes') },
          ]}
        />
      </div>

      <div class="flex flex-col gap-2.5 rounded-lg border border-border p-4">
        <div class="flex justify-between">
          <h2 class="text-sm font-semibold">{t('ui.patient.current_injuries')}</h2>
          <span class="text-xs text-muted-foreground">{t('ui.patient.live')}</span>
        </div>
        <div class="flex gap-2">
          {#each bodyParts as part (part)}
            {@const injury = injuryAt(patient.injuries, part)}
            <div class="flex flex-1 flex-col gap-0.5 rounded-md border bg-muted p-2.5 {injury ? injuryBorders[injury.kind] : 'border-muted'}">
              <span class="text-xs text-muted-foreground">{bodyPartLabel(part)}</span>
              <span class="text-13 font-medium">{injury ? injuryLabel(injury.kind) : t('ui.common.none')}</span>
            </div>
          {/each}
        </div>
      </div>

      {#key tab}
        <div class="flex flex-col" in:crossfade>
          {#if tab === 'treatments'}
            <div class="overflow-hidden rounded-lg border border-border">
              <div class="grid grid-cols-[5.625rem_1fr_8.125rem_6.875rem_4.375rem] gap-4 border-b border-border bg-muted px-4 py-2.5 text-xs font-medium text-muted-foreground">
                <span>{t('ui.common.date')}</span><span>{t('ui.common.injuries_and_treatment')}</span><span>{t('ui.common.medic')}</span><span>{t('ui.common.outcome')}</span><span class="text-right">{t('ui.common.report')}</span>
              </div>
              {#each patient.reports as report (report.id)}
                <div class="grid grid-cols-[5.625rem_1fr_8.125rem_6.875rem_4.375rem] items-center gap-4 border-b border-border px-4 py-3 last:border-b-0">
                  <span class="text-13 text-muted-foreground tabular-nums">{shortDate(report.createdAt)}</span>
                  <span class="flex min-w-0 flex-col gap-0.5">
                    <span class="truncate text-sm font-medium">{report.summary}</span>
                    <span class="truncate text-xs {report.status === 'draft' ? 'text-warning' : 'text-muted-foreground'}">{reportDetail(report)}</span>
                  </span>
                  <span class="truncate text-13">{report.medic}</span>
                  <span class="truncate text-13">{outcomeLabel(report.outcome)}</span>
                  <button type="button" class="text-right text-13 text-cobalt-foreground tabular-nums hover:text-foreground" onclick={() => mdt.openReport(report.id)}>{reportNumber(report.id)}</button>
                </div>
              {:else}
                <p class="px-4 py-6 text-center text-sm text-muted-foreground">{t('ui.patient.no_reports')}</p>
              {/each}
            </div>
          {:else if tab === 'prescriptions'}
            {#each patient.prescriptions as prescription (prescription.id)}
              <div class="flex items-center gap-4 border-b border-border py-3">
                <span class="w-20 text-13 text-muted-foreground tabular-nums">{prescriptionNumber(prescription.id)}</span>
                <span class="flex min-w-0 flex-1 flex-col gap-0.5">
                  <span class="truncate text-sm font-medium">{prescription.medication}</span>
                  <span class="truncate text-xs text-muted-foreground">{t('ui.patient.dose_for', prescription.dose, prescription.reason.toLowerCase())}</span>
                </span>
                <span class="text-13 text-muted-foreground tabular-nums">{t('ui.patient.refills', prescription.refillsUsed, prescription.refills)}</span>
                <Badge tone={prescription.status === 'active' ? 'neutral' : 'quiet'}>{prescriptionStatusLabel(prescription.status)}</Badge>
              </div>
            {:else}
              <p class="py-6 text-sm text-muted-foreground">{t('ui.patient.no_prescriptions')}</p>
            {/each}
          {:else if tab === 'invoices'}
            {#each patient.invoices as invoice (invoice.id)}
              <button type="button" class="flex items-center gap-4 border-b border-border py-3 text-left hover:bg-muted" onclick={() => mdt.go('billing')}>
                <span class="w-20 text-13 text-muted-foreground tabular-nums">{invoiceNumber(invoice.id)}</span>
                <span class="min-w-0 flex-1 truncate text-sm font-medium">{invoice.summary}</span>
                <span class="text-13 font-medium tabular-nums">{money(invoice.amount)}</span>
                <Badge tone={invoice.status === 'overdue' ? 'danger' : invoice.status === 'unpaid' ? 'neutral' : 'quiet'}>{invoiceStatusLabel(invoice.status)}</Badge>
              </button>
            {:else}
              <p class="py-6 text-sm text-muted-foreground">{t('ui.patient.no_invoices')}</p>
            {/each}
          {:else if tab === 'notes'}
            {#if editable}
              <textarea class="field min-h-40 resize-none py-3 text-13 leading-5" bind:value={notes} onblur={saveNotes} maxlength="2000" placeholder={t('ui.patient.notes_placeholder')}></textarea>
            {:else}
              <p class="rounded-md border border-border px-3 py-3 text-13 whitespace-pre-line">{patient.notes || t('ui.patient.no_notes')}</p>
            {/if}
          {/if}
        </div>
      {/key}
    </section>
  </div>
{:else if missing}
  <p class="p-6 text-sm text-muted-foreground">{t('ui.patient.missing', citizenid)}</p>
{/if}
