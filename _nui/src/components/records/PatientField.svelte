<script lang="ts">
  import MagnifyingGlass from 'phosphor-svelte/lib/MagnifyingGlass';
  import { fetchNui } from '../../lib/nui';
  import { rise } from '../../lib/motion';
  import { mdt } from '../../lib/store.svelte';
  import { t } from '../../lib/locale.svelte';
  import type { PatientSummary } from '../../lib/types';

  let { patient = $bindable() }: { patient: PatientSummary | null } = $props();

  let query = $state('');
  let results = $state<PatientSummary[]>([]);
  let request = 0;

  $effect(() => {
    const text = query.trim();
    const current = ++request;

    if (!text) {
      results = [];
      return;
    }

    const timer = setTimeout(async () => {
      const found = mdt.list(await fetchNui('searchPatients', { query: text }));
      if (found && current === request) results = found.slice(0, 5);
    }, 150);

    return () => clearTimeout(timer);
  });

  function choose(next: PatientSummary) {
    patient = next;
    query = '';
  }
</script>

<div class="flex flex-col gap-2">
  <span class="text-sm font-medium">{t('ui.common.patient')}</span>
  {#if patient}
    <div class="flex h-9 items-center gap-3 rounded-md border border-input px-3">
      <span class="flex-1 truncate text-sm font-medium">{patient.name}</span>
      <span class="text-xs text-muted-foreground tabular-nums">{patient.citizenid}</span>
      <button type="button" class="text-13 font-medium text-cobalt-foreground hover:text-foreground" onclick={() => (patient = null)}>{t('ui.common.change')}</button>
    </div>
  {:else}
    <label class="flex h-9 items-center gap-2 rounded-md border border-input px-3 transition-colors focus-within:border-primary">
      <MagnifyingGlass size="0.875rem" class="shrink-0 text-muted-foreground" />
      <input bind:value={query} placeholder={t('ui.common.search_patients_placeholder')} aria-label={t('ui.common.search_patients')} autocomplete="off" class="h-full min-w-0 flex-1 bg-transparent text-sm outline-none" />
    </label>
    {#if query.trim()}
      <ul class="flex flex-col overflow-hidden rounded-md border border-border" transition:rise>
        {#each results as result (result.citizenid)}
          <li class="border-b border-border last:border-b-0">
            <button type="button" class="flex w-full items-center gap-3 px-3 py-2 text-left hover:bg-muted" onclick={() => choose(result)}>
              <span class="flex-1 truncate text-sm font-medium">{result.name}</span>
              <span class="text-xs text-muted-foreground tabular-nums">{result.citizenid}</span>
            </button>
          </li>
        {:else}
          <li class="px-3 py-2.5 text-13 text-muted-foreground">{t('ui.common.no_patients_match')}</li>
        {/each}
      </ul>
    {/if}
  {/if}
</div>
