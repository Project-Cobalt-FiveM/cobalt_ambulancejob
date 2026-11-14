<script lang="ts">
  import { onMount } from 'svelte';
  import PlusSquare from 'phosphor-svelte/lib/PlusSquare';
  import BedIcon from 'phosphor-svelte/lib/Bed';
  import Header from '../components/Header.svelte';
  import Button from '../components/ui/Button.svelte';
  import Tabs from '../components/ui/Tabs.svelte';
  import Row from '../components/ui/Row.svelte';
  import Empty from '../components/ui/Empty.svelte';
  import AdmitDialog from '../components/beds/AdmitDialog.svelte';
  import MoveDialog from '../components/beds/MoveDialog.svelte';
  import { dayAndTime, doctorName, freeBeds, since, timeLeft } from '../components/beds/beds';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { age, plural, reportNumber } from '../lib/format';
  import { crossfade } from '../lib/motion';
  import { t } from '../lib/locale.svelte';
  import type { Admission, Beds, WaitingPatient } from '../lib/types';

  type AdmitTarget = { hospital: string; bed: number | null };

  let data = $state<Beds | null>(null);
  let hospitalId = $state('');
  let selectedBed = $state<number | null>(null);
  let admitting = $state<AdmitTarget | null>(null);
  let moving = $state(false);

  const canAdmit = $derived(mdt.can('admitDischarge'));
  const hospitals = $derived(data?.hospitals ?? []);
  const hospital = $derived(hospitals.find((entry) => entry.id === hospitalId) ?? hospitals[0]);
  const occupied = $derived(hospital?.beds.filter((bed) => bed.admission) ?? []);
  const bed = $derived(occupied.find((entry) => entry.index === selectedBed) ?? occupied[0] ?? null);
  const admission = $derived(bed?.admission ?? null);
  const free = $derived(hospitals.reduce((sum, entry) => sum + freeBeds(entry).length, 0));
  const total = $derived(hospitals.reduce((sum, entry) => sum + entry.beds.length, 0));
  const subtitle = $derived(data ? t('ui.beds.subtitle', free, total, plural(hospitals.length, 'ui.plural.hospitals')) : '');

  let notes = $derived(admission?.notes ?? '');

  onMount(load);

  $effect(() => {
    if (mdt.bedsVersion > 0) void load();
  });

  async function load() {
    data = mdt.single(await fetchNui('getBeds')) ?? data;
  }

  async function show(hospital: string, index: number) {
    await load();
    hospitalId = hospital;
    selectedBed = index;
    admitting = null;
    moving = false;
  }

  function admitAnywhere() {
    const target = hospital && freeBeds(hospital).length ? hospital : hospitals.find((entry) => freeBeds(entry).length);
    if (!target) return;

    admitting = { hospital: target.id, bed: freeBeds(target)[0]?.index ?? null };
  }

  async function saveNotes(current: Admission) {
    if (notes === current.notes) return;

    if (mdt.report(await fetchNui('saveWardNotes', { id: current.id, notes }), t('ui.beds.notes_saved'))) current.notes = notes;
  }

  async function discharge(current: Admission) {
    if (mdt.report(await fetchNui('discharge', { id: current.id }), t('ui.beds.discharged_toast', current.patientName))) {
      selectedBed = null;
      await load();
    }
  }

  async function see(patient: WaitingPatient) {
    if (mdt.report(await fetchNui('seePatient', { id: patient.id }))) mdt.openPatient(patient.citizenid);
  }
</script>

<Header title={t('ui.sidebar.beds')} {subtitle}>
  {#snippet action()}
    {#if canAdmit}
      <Button variant="primary" disabled={!free} onclick={admitAnywhere}><PlusSquare size="1rem" />{t('ui.beds.admit_patient')}</Button>
    {/if}
  {/snippet}
</Header>

<div class="flex min-h-0 flex-1" in:crossfade>
  <section class="flex min-w-0 flex-1 flex-col gap-4 overflow-y-auto p-6">
    {#if hospital}
      <Tabs
        value={hospital.id}
        tabs={hospitals.map((entry) => ({ value: entry.id, label: t('ui.beds.hospital_free', entry.short, freeBeds(entry).length) }))}
        onchange={(id) => {
          hospitalId = id;
          selectedBed = null;
        }}
      />
      <div class="flex flex-wrap gap-3">
        {#each hospital.beds as entry (entry.index)}
          {#if entry.admission}
            {@const active = entry.index === bed?.index}
            <button
              type="button"
              class="flex w-74.5 shrink-0 flex-col gap-2 rounded-lg border p-3.5 text-left transition-colors {active ? 'border-primary bg-primary' : 'border-border hover:bg-muted'}"
              onclick={() => (selectedBed = entry.index)}
            >
              <span class="flex justify-between gap-2">
                <span class="text-13 font-semibold">{entry.label}</span>
                <span class="text-xs tabular-nums {active ? '' : 'text-muted-foreground'}">{since(entry.admission.admittedAt, mdt.now)}</span>
              </span>
              <span class="truncate text-15 font-semibold">{entry.admission.patientName}</span>
              <span class="truncate text-xs {active ? '' : 'text-muted-foreground'}">{entry.admission.reason}, {doctorName(entry.admission.attending)}</span>
            </button>
          {:else if entry.frontDesk}
            {@const patient = entry.frontDesk}
            <button
              type="button"
              class="flex w-74.5 shrink-0 flex-col gap-2 rounded-lg border border-border p-3.5 text-left transition-colors hover:bg-muted"
              onclick={() => mdt.openPatient(patient.citizenid)}
            >
              <span class="flex justify-between gap-2">
                <span class="text-13 font-semibold">{entry.label}</span>
                <span class="text-xs text-muted-foreground tabular-nums">{t('ui.beds.front_desk_left', timeLeft(patient.endsAt, mdt.now))}</span>
              </span>
              <span class="truncate text-15 font-semibold">{patient.patientName}</span>
              <span class="truncate text-xs text-muted-foreground">{t('ui.beds.front_desk_status')}</span>
            </button>
          {:else}
            <button
              type="button"
              class="flex w-74.5 shrink-0 flex-col gap-2 rounded-lg border border-dashed border-input p-3.5 text-left transition-colors enabled:hover:bg-muted"
              disabled={!canAdmit}
              onclick={() => (admitting = { hospital: hospital.id, bed: entry.index })}
            >
              <span class="flex justify-between gap-2">
                <span class="text-13 font-semibold">{entry.label}</span>
                <span class="text-xs text-success">{t('ui.beds.free')}</span>
              </span>
              <span class="text-15 font-medium text-muted-foreground">{t('ui.beds.empty')}</span>
              {#if canAdmit}<span class="text-xs font-medium text-cobalt-foreground">{t('ui.beds.admit_title')}</span>{/if}
            </button>
          {/if}
        {/each}
      </div>
    {/if}

    <div class="flex flex-col gap-2.5 pt-2">
      <h2 class="text-base font-semibold">{t('ui.beds.waiting_title')}</h2>
      <div class="flex flex-col rounded-lg border border-border">
        {#each data?.waiting ?? [] as patient (patient.id)}
          <div class="flex items-center gap-4 border-b border-border px-4 py-3 last:border-b-0">
            <div class="flex min-w-0 flex-1 flex-col gap-0.5">
              <span class="truncate text-sm font-medium">{patient.name}</span>
              <span class="truncate text-xs text-muted-foreground">{patient.reason}</span>
            </div>
            <span class="shrink-0 text-13 text-muted-foreground tabular-nums">{t('ui.beds.waiting', age(patient.since, mdt.now))}</span>
            <Button size="sm" onclick={() => see(patient)}>{t('ui.beds.see_patient')}</Button>
          </div>
        {:else}
          <p class="px-4 py-6 text-center text-sm text-muted-foreground">{t('ui.beds.nobody_waiting')}</p>
        {/each}
      </div>
    </div>
  </section>

  <aside class="flex w-95 shrink-0 flex-col border-l border-border">
    {#if admission && bed && hospital}
      {#key admission.id}
        <div class="flex min-h-0 flex-1 flex-col gap-4.5 overflow-y-auto p-6" in:crossfade>
          <div class="flex flex-col gap-1">
            <span class="text-13 text-muted-foreground">{hospital.short}, {bed.label.toLowerCase()}</span>
            <button type="button" class="text-left text-xl font-semibold tracking-[-0.01em] hover:text-cobalt-foreground" onclick={() => mdt.openPatient(admission.citizenid)}>
              {admission.patientName}
            </button>
          </div>
          <div class="flex flex-col">
            <Row label={t('ui.common.reason')}>{admission.reason}</Row>
            <Row label={t('ui.beds.admitted')}>{dayAndTime(admission.admittedAt, mdt.now)}</Row>
            <Row label={t('ui.beds.attending')}>{admission.attending}</Row>
            <Row label={t('ui.beds.planned_discharge')}>{admission.plannedDischargeAt ? dayAndTime(admission.plannedDischargeAt, mdt.now) : t('ui.beds.not_set')}</Row>
            {#if admission.reportId !== null}
              {@const reportId = admission.reportId}
              <Row label={t('ui.common.report')} tone="link">
                <button type="button" class="hover:text-foreground" onclick={() => mdt.openReport(reportId)}>{reportNumber(reportId)}</button>
              </Row>
            {/if}
          </div>
          <label class="flex flex-col gap-1.5">
            <span class="text-sm font-medium">{t('ui.beds.ward_notes')}</span>
            <textarea
              class="field min-h-24 resize-none py-2.5 text-13 leading-5"
              bind:value={notes}
              maxlength="1000"
              placeholder={t('ui.beds.notes_placeholder')}
              onblur={() => saveNotes(admission)}
            ></textarea>
          </label>
        </div>
        {#if canAdmit}
          <div class="flex gap-2 px-6 pb-6">
            <Button variant="primary" class="flex-1" onclick={() => discharge(admission)}>{t('ui.beds.discharge')}</Button>
            <Button onclick={() => (moving = true)}>{t('ui.beds.move_bed')}</Button>
          </div>
        {/if}
      {/key}
    {:else}
      <Empty icon={BedIcon} title={t('ui.beds.none_selected')} body={t('ui.beds.none_selected_body')} />
    {/if}
  </aside>
</div>

{#if admitting}
  <AdmitDialog {hospitals} hospital={admitting.hospital} bed={admitting.bed} onclose={() => (admitting = null)} onadmit={show} />
{/if}

{#if moving && admission}
  <MoveDialog {admission} {hospitals} onclose={() => (moving = false)} onmove={show} />
{/if}
