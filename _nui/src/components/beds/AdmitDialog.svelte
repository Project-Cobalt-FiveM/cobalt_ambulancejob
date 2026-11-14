<script lang="ts">
  import { untrack } from 'svelte';
  import Button from '../ui/Button.svelte';
  import Dialog from '../ui/Dialog.svelte';
  import Field from '../ui/Field.svelte';
  import Picker from '../ui/Picker.svelte';
  import BedPicker from './BedPicker.svelte';
  import { fetchNui } from '../../lib/nui';
  import { mdt } from '../../lib/store.svelte';
  import { t } from '../../lib/locale.svelte';
  import type { Hospital, PatientSummary } from '../../lib/types';

  type Props = { hospitals: Hospital[]; hospital: string; bed: number | null; onclose: () => void; onadmit: (hospital: string, bed: number) => void };

  let { hospitals, hospital: initialHospital, bed: initialBed, onclose, onadmit }: Props = $props();

  let patient = $state<PatientSummary | null>(null);
  let hospital = $state(untrack(() => initialHospital));
  let bed = $state(untrack(() => initialBed));
  let reason = $state('');
  let hours = $state<number | null>(null);

  const dischargeHours = $derived(hours ? Math.max(1, Math.round(hours)) : null);
  const ready = $derived(patient !== null && bed !== null && reason.trim() !== '');

  async function search(query: string) {
    const found = mdt.list(await fetchNui('searchPatients', { query })) ?? [];
    return found.map((entry) => ({ key: entry.citizenid, label: entry.name, detail: `${entry.citizenid}${entry.admission ? `, ${entry.admission}` : ''}`, value: entry }));
  }

  async function admit() {
    if (!patient || bed === null) return;

    const result = await fetchNui('admit', { citizenid: patient.citizenid, hospital, bed, reason: reason.trim(), dischargeHours, reportId: null });
    if (mdt.report(result, t('ui.beds.admitted_toast', patient.name))) onadmit(hospital, bed);
  }
</script>

<Dialog title={t('ui.beds.admit_title')} description={t('ui.beds.admit_description')} width="w-[32rem]" {onclose}>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium">{t('ui.common.patient')}</span>
    <div class="flex items-center gap-3">
      <Picker label={patient ? t('ui.common.change') : t('ui.beds.find_patient')} placeholder={t('ui.common.search_patients_placeholder')} {search} onpick={(value) => (patient = value)} />
      <span class="flex-1 truncate text-sm {patient ? 'font-medium' : 'text-muted-foreground'}">{patient ? `${patient.name}, ${patient.citizenid}` : t('ui.beds.no_patient')}</span>
    </div>
  </div>
  <BedPicker {hospitals} bind:hospital bind:bed />
  <Field label={t('ui.common.reason')}><input class="field" bind:value={reason} maxlength="120" placeholder={t('ui.beds.reason_placeholder')} /></Field>
  <Field label={t('ui.beds.planned_discharge')} hint={t('ui.beds.discharge_hint')}>
    <input class="field tabular-nums" type="number" min="1" max="168" bind:value={hours} placeholder="24" />
  </Field>
  {#snippet actions()}
    <Button onclick={onclose}>{t('ui.common.cancel')}</Button>
    <Button variant="primary" disabled={!ready} onclick={admit}>{t('ui.beds.admit')}</Button>
  {/snippet}
</Dialog>
