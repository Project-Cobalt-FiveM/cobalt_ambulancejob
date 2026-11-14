<script lang="ts">
  import Field from '../ui/Field.svelte';
  import Select from '../ui/Select.svelte';
  import { freeBeds } from './beds';
  import { t } from '../../lib/locale.svelte';
  import type { Hospital } from '../../lib/types';

  let { hospitals, hospital = $bindable(), bed = $bindable() }: { hospitals: Hospital[]; hospital: string; bed: number | null } = $props();

  const hospitalOptions = $derived(hospitals.map((entry) => ({ value: entry.id, label: t('ui.beds.hospital_free', entry.label, freeBeds(entry).length) })));
  const bedOptions = $derived(freeBeds(hospitals.find((entry) => entry.id === hospital)).map((entry) => ({ value: entry.index, label: entry.label })));

  function pickHospital(id: string) {
    bed = freeBeds(hospitals.find((entry) => entry.id === id))[0]?.index ?? null;
  }
</script>

<div class="grid grid-cols-[1fr_9rem] gap-3">
  <Field label={t('ui.beds.hospital')}>
    <Select label={t('ui.beds.hospital')} options={hospitalOptions} bind:value={hospital} onchange={pickHospital} />
  </Field>
  <Field label={t('ui.beds.bed')}>
    {#if bed === null}
      <span class="field flex items-center text-muted-foreground">{t('ui.beds.no_free_beds')}</span>
    {:else}
      <Select label={t('ui.beds.bed')} options={bedOptions} value={bed} onchange={(index) => (bed = index)} />
    {/if}
  </Field>
</div>
