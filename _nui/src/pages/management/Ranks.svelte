<script lang="ts">
  import { onMount } from 'svelte';
  import Button from '../../components/ui/Button.svelte';
  import Toggle from '../../components/ui/Toggle.svelte';
  import { fetchNui } from '../../lib/nui';
  import { mdt } from '../../lib/store.svelte';
  import { plural } from '../../lib/format';
  import { t } from '../../lib/locale.svelte';
  import type { Permission, Permissions, Rank } from '../../lib/types';

  const groups: { title: string; items: Permission[] }[] = [
    {
      title: 'patient_care',
      items: ['writeReports', 'editOtherReports', 'editPatients', 'writePrescriptions', 'prescribeControlled', 'admitDischarge', 'useDefib'],
    },
    {
      title: 'department',
      items: ['sendInvoices', 'voidInvoices', 'shareReports', 'manageTreatments', 'manageRoster', 'manageTemplates', 'manageSettings', 'administrator'],
    },
  ];

  const total = groups.reduce((sum, group) => sum + group.items.length, 0);

  function label(key: Permission): string {
    return t(`ui.ranks.permission.${key}`);
  }

  let ranks = $state<Rank[]>([]);
  let selectedGrade = $state<number | null>(null);
  let permissions = $state<Permissions | null>(null);

  const selected = $derived(ranks.find((rank) => rank.grade === selectedGrade) ?? null);
  const readOnly = $derived(selected?.isBoss ?? false);

  async function load() {
    const reply = mdt.list(await fetchNui('getRanks'));
    if (!reply) return;

    ranks = reply.sort((a, b) => b.grade - a.grade);
    const current = ranks.find((rank) => rank.grade === selectedGrade) ?? ranks.find((rank) => !rank.isBoss) ?? ranks[0];
    if (current) pick(current);
  }

  onMount(load);

  function pick(rank: Rank) {
    selectedGrade = rank.grade;
    permissions = { ...rank.permissions };
  }

  function access(rank: Rank): string {
    if (rank.isBoss || rank.permissions.administrator) return t('ui.ranks.all_access');
    return t('ui.common.x_of_y', Object.values(rank.permissions).filter(Boolean).length, total);
  }

  function locked(current: Permissions, key: Permission): boolean {
    return readOnly || (current.administrator && key !== 'administrator');
  }

  async function save() {
    if (!selected || !permissions || readOnly) return;

    if (mdt.report(await fetchNui('saveRank', { grade: selected.grade, permissions: $state.snapshot(permissions) }), t('ui.common.saved_toast', selected.name))) await load();
  }
</script>

<section class="flex w-65 shrink-0 flex-col gap-3 overflow-y-auto border-r border-border p-5">
  <h2 class="text-sm font-semibold">{t('ui.ranks.title', mdt.medic?.department.label ?? t('ui.ranks.ems'))}</h2>
  <div class="flex flex-col gap-1">
    {#each ranks as rank (rank.grade)}
      {@const active = rank.grade === selectedGrade}
      <button
        type="button"
        class="flex h-9 shrink-0 items-center justify-between gap-2 rounded-md px-3 text-left text-sm transition-colors {active ? 'bg-primary font-medium' : 'border border-border hover:bg-muted'}"
        onclick={() => pick(rank)}
      >
        <span class="truncate">{rank.name}</span>
        <span class="text-xs tabular-nums {active ? 'font-medium' : 'text-muted-foreground'}">{access(rank)}</span>
      </button>
    {/each}
  </div>
</section>

<section class="flex min-w-0 flex-1 flex-col gap-5 overflow-y-auto p-6">
  {#if selected && permissions}
    {@const current = permissions}
    <div class="flex items-end gap-3">
      <div class="flex flex-1 flex-col gap-0.5">
        <h2 class="text-xl font-semibold tracking-[-0.01em]">{selected.name}</h2>
        <p class="text-13 text-muted-foreground">
          {plural(selected.holders, readOnly ? 'ui.ranks.holders_boss' : 'ui.ranks.holders')}
        </p>
      </div>
      {#if !readOnly}<Button variant="primary" onclick={save}>{t('ui.ranks.save')}</Button>{/if}
    </div>
    <div class="flex items-start gap-6">
      {#each groups as group (group.title)}
        <div class="flex flex-1 flex-col gap-2">
          <h3 class="text-13 font-semibold text-muted-foreground">{t(`ui.ranks.group.${group.title}`)}</h3>
          <div class="flex flex-col rounded-lg border border-border">
            {#each group.items as key (key)}
              {@const checked = readOnly || current[key]}
              <div class="flex items-center gap-3 border-b border-border px-3.5 py-2.75 last:border-b-0">
                <div class="flex flex-1 flex-col gap-0.5">
                  <span class="text-sm {current.administrator && key !== 'administrator' ? 'text-muted-foreground' : ''}">{label(key)}</span>
                  {#if key === 'administrator'}<span class="text-xs text-muted-foreground">{t('ui.ranks.administrator_note')}</span>{/if}
                </div>
                <Toggle label={label(key)} {checked} disabled={locked(current, key)} onchange={(value) => (current[key] = value)} />
              </div>
            {/each}
          </div>
        </div>
      {/each}
    </div>
  {/if}
</section>
