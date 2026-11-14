<script lang="ts">
  import Header from '../../components/Header.svelte';
  import { mdt } from '../../lib/store.svelte';
  import { crossfade } from '../../lib/motion';
  import { t } from '../../lib/locale.svelte';
  import type { Permission } from '../../lib/types';
  import Ranks from './Ranks.svelte';
  import Treatments from './Treatments.svelte';
  import Templates from './Templates.svelte';
  import Settings from './Settings.svelte';

  type Section = 'ranks' | 'treatments' | 'templates' | 'settings';

  const sections: { value: Section; permission: Permission }[] = [
    { value: 'ranks', permission: 'manageRoster' },
    { value: 'treatments', permission: 'manageTreatments' },
    { value: 'templates', permission: 'manageTemplates' },
    { value: 'settings', permission: 'manageSettings' },
  ];

  const allowed = $derived(sections.filter((entry) => mdt.can(entry.permission)));

  let section = $state<Section | null>(null);

  const current = $derived(allowed.find((entry) => entry.value === section) ?? allowed[0] ?? null);

  function label(value: Section): string {
    return t(`ui.management.${value}`);
  }
</script>

<Header title={t('ui.sidebar.management')} subtitle={current ? label(current.value) : t('ui.management.senior_only')} />

<div class="flex min-h-0 flex-1">
  <nav class="flex w-55 shrink-0 flex-col gap-0.5 border-r border-border px-3 py-5">
    {#each allowed as entry (entry.value)}
      {@const active = entry.value === current?.value}
      <button
        type="button"
        aria-current={active ? 'page' : undefined}
        class="flex h-8.5 shrink-0 items-center rounded-md px-2.5 text-left text-sm font-medium transition-colors {active ? 'bg-secondary text-foreground' : 'text-muted-foreground hover:bg-muted hover:text-foreground'}"
        onclick={() => (section = entry.value)}
      >
        {label(entry.value)}
      </button>
    {/each}
  </nav>

  {#if current}
    {#key current.value}
      <div class="flex min-w-0 flex-1" in:crossfade>
        {#if current.value === 'ranks'}
          <Ranks />
        {:else if current.value === 'treatments'}
          <Treatments />
        {:else if current.value === 'templates'}
          <Templates />
        {:else}
          <Settings />
        {/if}
      </div>
    {/key}
  {:else}
    <p class="p-6 text-sm text-muted-foreground">{t('ui.management.no_access')}</p>
  {/if}
</div>
