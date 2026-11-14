<script lang="ts">
  import MagnifyingGlass from 'phosphor-svelte/lib/MagnifyingGlass';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { rise } from '../lib/motion';
  import { t } from '../lib/locale.svelte';
  import type { SearchHit } from '../lib/types';
  import Kbd from './ui/Kbd.svelte';

  let { width = '23.75rem' }: { width?: string } = $props();

  let query = $state('');
  let focused = $state(false);
  let hits = $state<SearchHit[] | null>(null);
  let input = $state<HTMLInputElement>();
  let request = 0;

  const open = $derived(focused && query.trim().length > 1 && hits !== null);

  const groups = $derived.by(() => {
    const list = hits ?? [];
    return [
      { label: t('ui.search.patients'), hits: list.filter((hit) => hit.kind === 'patient') },
      { label: t('ui.search.calls'), hits: list.filter((hit) => hit.kind === 'call') },
      { label: t('ui.search.reports'), hits: list.filter((hit) => hit.kind === 'report') },
    ].filter((group) => group.hits.length > 0);
  });

  $effect(() => {
    const text = query.trim();
    const current = ++request;
    if (text.length < 2) {
      hits = null;
      return;
    }

    const timer = setTimeout(async () => {
      const found = mdt.list(await fetchNui('search', { query: text }));
      if (found && current === request) hits = found;
    }, 200);

    return () => clearTimeout(timer);
  });

  $effect(() => {
    if (!open) return;
    return mdt.pushLayer(() => input?.blur());
  });

  function pick(hit: SearchHit) {
    if (hit.kind === 'patient') mdt.openPatient(hit.citizenid);
    else if (hit.kind === 'call') mdt.go('dispatch');
    else mdt.openReport(hit.id);

    query = '';
    input?.blur();
  }

  function key(hit: SearchHit): string {
    return hit.kind === 'patient' ? `p${hit.citizenid}` : `${hit.kind}${hit.id}`;
  }
</script>

<div class="relative shrink-0" style:width>
  <div class="flex h-9 items-center gap-2 rounded-md border border-input px-3 transition-colors focus-within:border-primary">
    <MagnifyingGlass size="0.875rem" class="text-muted-foreground" />
    <input
      id="global-search"
      bind:this={input}
      bind:value={query}
      onfocus={() => (focused = true)}
      onblur={() => setTimeout(() => (focused = false), 120)}
      placeholder={t('ui.search.placeholder')}
      aria-label={t('ui.search.label')}
      autocomplete="off"
      class="h-full min-w-0 flex-1 bg-transparent text-sm outline-none"
    />
    <Kbd>/</Kbd>
  </div>

  {#if open}
    <div class="absolute top-full right-0 left-0 z-40 mt-1 flex max-h-[28rem] flex-col overflow-y-auto rounded-lg border border-border bg-popover p-1 shadow-lg" transition:rise>
      {#if groups.length === 0}
        <p class="px-2 py-3 text-13 text-muted-foreground">{t('ui.search.no_match', query.trim())}</p>
      {/if}
      {#each groups as group (group.label)}
        <p class="px-2 pt-2 pb-1 text-xs text-muted-foreground">{group.label}</p>
        {#each group.hits as hit (key(hit))}
          <button type="button" class="flex flex-col rounded-md px-2 py-1.5 text-left hover:bg-muted" onclick={() => pick(hit)}>
            <span class="text-sm font-medium">{hit.title}</span>
            <span class="text-xs text-muted-foreground tabular-nums">{hit.detail}</span>
          </button>
        {/each}
      {/each}
    </div>
  {/if}
</div>
