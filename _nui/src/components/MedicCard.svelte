<script lang="ts">
  import { mdt } from '../lib/store.svelte';
  import { initials, medicStatuses, statusDots, statusLabel } from '../lib/format';
  import { t } from '../lib/locale.svelte';
  import Select from './ui/Select.svelte';

  const options = $derived(medicStatuses.map((value) => ({ value, label: statusLabel(value), dot: statusDots[value] })));
  const status = $derived(mdt.medic?.status ?? 'available');
</script>

{#if mdt.medic}
  <div class="flex flex-col gap-2.5 rounded-lg border border-border bg-muted p-3">
    <div class="flex items-center gap-2.5">
      <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-secondary text-xs font-semibold">{initials(mdt.medic.name)}</div>
      <div class="flex min-w-0 flex-1 flex-col gap-0.5">
        <span class="truncate text-sm font-medium">{mdt.medic.name}</span>
        <span class="truncate text-xs text-muted-foreground tabular-nums">{mdt.medic.gradeName}{mdt.medic.callsign ? `, ${mdt.medic.callsign}` : ''}</span>
      </div>
    </div>
    <Select class="[&_.field]:h-8 [&_.field]:bg-secondary [&_.field]:text-13" label={t('ui.sidebar.your_status')} {options} value={status} onchange={(next) => mdt.setStatus(next)} />
  </div>
{/if}
