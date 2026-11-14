<script lang="ts">
  import type { Component } from 'svelte';
  import FirstAidKit from 'phosphor-svelte/lib/FirstAidKit';
  import SquaresFour from 'phosphor-svelte/lib/SquaresFour';
  import Broadcast from 'phosphor-svelte/lib/Broadcast';
  import AddressBook from 'phosphor-svelte/lib/AddressBook';
  import FileText from 'phosphor-svelte/lib/FileText';
  import Pill from 'phosphor-svelte/lib/Pill';
  import Receipt from 'phosphor-svelte/lib/Receipt';
  import Bed from 'phosphor-svelte/lib/Bed';
  import IdentificationBadge from 'phosphor-svelte/lib/IdentificationBadge';
  import GearSix from 'phosphor-svelte/lib/GearSix';
  import Lock from 'phosphor-svelte/lib/Lock';
  import { mdt } from '../lib/store.svelte';
  import { t } from '../lib/locale.svelte';
  import type { Page } from '../lib/types';
  import MedicCard from './MedicCard.svelte';

  type Item = {
    page: Page;
    icon: Component<{ size?: string; class?: string }>;
    badge?: () => { count: number; urgent: boolean };
  };

  const groups: Item[][] = [
    [
      { page: 'dashboard', icon: SquaresFour },
      { page: 'dispatch', icon: Broadcast, badge: () => ({ count: mdt.openCalls.length, urgent: true }) },
    ],
    [
      { page: 'patients', icon: AddressBook },
      { page: 'reports', icon: FileText },
      { page: 'prescriptions', icon: Pill },
      { page: 'billing', icon: Receipt, badge: () => ({ count: mdt.unpaid, urgent: false }) },
    ],
    [
      { page: 'beds', icon: Bed },
      { page: 'roster', icon: IdentificationBadge },
      { page: 'management', icon: GearSix },
    ],
  ];

  const visible = $derived(
    groups
      .map((group) => group.filter((item) => mdt.has(item.page) || mdt.lockedRank(item.page) !== null))
      .filter((group) => group.length > 0),
  );

  const locked = $derived(mdt.medic?.locked ?? []);

  function label(page: Page): string {
    return t(`ui.sidebar.${page}`);
  }
</script>

<aside class="flex w-60 shrink-0 flex-col gap-4 border-r border-border bg-card px-3 pb-4">
  <div class="-mx-3 flex h-18 shrink-0 items-center gap-3 border-b border-border px-5">
    <div class="flex size-9 shrink-0 items-center justify-center rounded-md bg-secondary">
      <FirstAidKit size="1.25rem" class="text-foreground" />
    </div>
    <div class="flex min-w-0 flex-col gap-0.5">
      <span class="truncate text-15 font-semibold">{mdt.medic?.department.label}</span>
      <span class="truncate text-xs text-muted-foreground">{mdt.medic?.department.subtitle}</span>
    </div>
  </div>

  <nav class="flex flex-1 flex-col gap-0.5 overflow-y-auto">
    {#each visible as group, index (index)}
      {#if index > 0}<div class="px-2.5 py-1.5"><div class="h-px bg-border"></div></div>{/if}
      {#each group as item (item.page)}
        {@const active = mdt.route.page === item.page}
        {@const open = mdt.has(item.page)}
        {@const badge = item.badge?.()}
        {#if open}
          <button
            type="button"
            aria-current={active ? 'page' : undefined}
            class="flex h-9 shrink-0 items-center gap-2.5 rounded-md px-2.5 text-left text-sm font-medium transition-colors {active ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'}"
            onclick={() => mdt.go(item.page)}
          >
            <item.icon size="1rem" class={active ? 'text-primary-foreground' : 'text-muted-foreground'} />
            <span class="flex-1">{label(item.page)}</span>
            {#if badge && badge.count > 0}
              <span class="rounded-sm px-1.5 py-px text-xs font-semibold tabular-nums {badge.urgent ? 'bg-destructive-solid' : active ? 'bg-cobalt-hover' : 'bg-secondary'}">{badge.count}</span>
            {/if}
          </button>
        {:else}
          <div class="flex h-9 shrink-0 items-center gap-2.5 rounded-md px-2.5 text-sm font-medium text-disabled" aria-disabled="true" title={t('ui.sidebar.opens_at', mdt.lockedRank(item.page) ?? '')}>
            <Lock size="1rem" class="text-disabled-icon" />
            <span class="flex-1">{label(item.page)}</span>
          </div>
        {/if}
      {/each}
    {/each}

    {#if locked.length}
      <div class="mt-2 flex flex-col gap-1 rounded-md border border-border px-3 py-2.5 text-xs">
        <span class="font-medium">{t('ui.sidebar.locked_title')}</span>
        {#each locked as entry (entry.page)}
          <span class="text-muted-foreground">{t('ui.sidebar.locked_page', label(entry.page), entry.rank)}</span>
        {/each}
      </div>
    {/if}
  </nav>

  <MedicCard />
</aside>
