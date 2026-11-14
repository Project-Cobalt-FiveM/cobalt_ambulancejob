<script lang="ts">
  import { untrack } from 'svelte';
  import Button from '../ui/Button.svelte';
  import Dialog from '../ui/Dialog.svelte';
  import BedPicker from './BedPicker.svelte';
  import { freeBeds } from './beds';
  import { fetchNui } from '../../lib/nui';
  import { mdt } from '../../lib/store.svelte';
  import { t } from '../../lib/locale.svelte';
  import type { Admission, Hospital } from '../../lib/types';

  type Props = { admission: Admission; hospitals: Hospital[]; onclose: () => void; onmove: (hospital: string, bed: number) => void };

  let { admission, hospitals, onclose, onmove }: Props = $props();

  const start = untrack(() => ({ hospital: admission.hospital, bed: freeBeds(hospitals.find((entry) => entry.id === admission.hospital))[0]?.index ?? null }));

  let hospital = $state(start.hospital);
  let bed = $state(start.bed);

  async function move() {
    if (bed === null) return;

    if (mdt.report(await fetchNui('moveBed', { id: admission.id, hospital, bed }), t('ui.beds.moved_toast', admission.patientName))) onmove(hospital, bed);
  }
</script>

<Dialog title={t('ui.beds.move_title', admission.patientName)} description={t('ui.beds.move_description')} {onclose}>
  <BedPicker {hospitals} bind:hospital bind:bed />
  {#snippet actions()}
    <Button onclick={onclose}>{t('ui.common.cancel')}</Button>
    <Button variant="primary" disabled={bed === null} onclick={move}>{t('ui.beds.move')}</Button>
  {/snippet}
</Dialog>
