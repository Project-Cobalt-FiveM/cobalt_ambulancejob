<script lang="ts">
  import { onMount } from 'svelte';
  import PlusSquare from 'phosphor-svelte/lib/PlusSquare';
  import Heartbeat from 'phosphor-svelte/lib/Heartbeat';
  import Broadcast from 'phosphor-svelte/lib/Broadcast';
  import Header from '../components/Header.svelte';
  import Button from '../components/ui/Button.svelte';
  import Badge from '../components/ui/Badge.svelte';
  import Tabs from '../components/ui/Tabs.svelte';
  import Dot from '../components/ui/Dot.svelte';
  import Empty from '../components/ui/Empty.svelte';
  import CallDetail from '../components/dispatch/CallDetail.svelte';
  import { bleed, responderLine } from '../components/dispatch/calls';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { age, ago, countdown, plural } from '../lib/format';
  import { crossfade } from '../lib/motion';
  import { t } from '../lib/locale.svelte';
  import type { Call, Dashboard, DispatchSummary } from '../lib/types';

  type Filter = 'open' | 'mine' | 'closed';

  let filter = $state<Filter>('open');
  let selectedId = $state<number | null>(null);
  let dashboard = $state<Dashboard | null>(null);
  let summary = $state<DispatchSummary | null>(null);

  const mine = $derived(mdt.openCalls.filter((call) => mdt.isResponding(call)));
  const closed = $derived(mdt.calls.filter((call) => call.status === 'closed'));
  const list = $derived(filter === 'open' ? mdt.openCalls : filter === 'mine' ? mine : closed);
  const selected = $derived(list.find((call) => call.id === selectedId) ?? list[0] ?? null);
  const quiet = $derived(filter === 'open' && mdt.openCalls.length === 0);
  const subtitle = $derived(
    mdt.openCalls.length
      ? dashboard
        ? t('ui.dispatch.subtitle', plural(mdt.openCalls.length, 'ui.plural.open_calls'), plural(dashboard.stats.medicsOnDuty, 'ui.plural.medics'))
        : plural(mdt.openCalls.length, 'ui.plural.open_calls')
      : t('ui.dispatch.no_open_calls'),
  );

  onMount(async () => {
    dashboard = mdt.single(await fetchNui('getDashboard')) ?? dashboard;
  });

  $effect(() => {
    if (quiet && !summary) void fetchNui('getDispatchSummary').then((reply) => (summary = mdt.single(reply) ?? summary));
  });

  async function refresh() {
    const calls = mdt.list(await fetchNui('getCalls'));
    if (calls) mdt.calls = calls;
  }

  function clock(call: Call): string {
    const bleeding = bleed(call, mdt.now);
    return bleeding ? countdown(bleeding.left) : age(call.createdAt, mdt.now);
  }
</script>

<Header title={t('ui.sidebar.dispatch')} {subtitle}>
  {#snippet action()}
    {#if mdt.can('writeReports')}
      <Button variant="primary" onclick={() => mdt.newReport()}><PlusSquare size="1rem" />{t('ui.common.new_report')}</Button>
    {/if}
  {/snippet}
</Header>

{#if quiet}
  <div class="flex min-h-0 flex-1 flex-col" in:crossfade>
    <Empty icon={Heartbeat} title={t('ui.dispatch.no_open_calls')} body={t('ui.dispatch.quiet_body')}>
      <div class="flex flex-col items-center gap-4">
        <Button onclick={() => (filter = 'closed')}>{t('ui.dispatch.view_closed')}</Button>
        {#if summary}
          <div class="flex items-center gap-4 pt-2 text-13 text-muted-foreground tabular-nums">
            <span class="flex items-center gap-1.5"><Dot class="bg-success" />{t('ui.dispatch.available', plural(summary.available, 'ui.plural.medics'))}</span>
            <span class="flex items-center gap-1.5"><Dot class="bg-warning" />{t('ui.dispatch.on_break', summary.onBreak)}</span>
            {#if summary.lastClosedAt}<span>{t('ui.dispatch.last_closed', ago(summary.lastClosedAt, mdt.now))}</span>{/if}
          </div>
        {/if}
      </div>
    </Empty>
  </div>
{:else}
  <div class="flex min-h-0 flex-1" in:crossfade>
    <section class="flex w-100 shrink-0 flex-col gap-3 overflow-y-auto border-r border-border p-5">
      <Tabs
        bind:value={filter}
        tabs={[
          { value: 'open', label: t('ui.dispatch.tab_open'), count: mdt.openCalls.length },
          { value: 'mine', label: t('ui.common.mine'), count: mine.length },
          { value: 'closed', label: t('ui.dispatch.tab_closed') },
        ]}
      />
      <div class="flex flex-col gap-1.5">
        {#each list as call (call.id)}
          {@const active = call.id === selected?.id}
          <button
            type="button"
            class="flex flex-col gap-1.5 rounded-lg border p-3 text-left transition-colors {active ? 'border-primary bg-primary' : 'border-border hover:bg-muted'}"
            onclick={() => (selectedId = call.id)}
          >
            <span class="flex items-center gap-2">
              <Badge tone={call.priority === 1 ? 'danger' : active ? 'onPrimary' : 'neutral'} strong>{call.code}</Badge>
              <span class="flex-1 truncate text-sm {active ? 'font-semibold' : 'font-medium'}">{call.title}</span>
              <span class="text-xs tabular-nums {active ? '' : 'text-muted-foreground'}">{clock(call)}</span>
            </span>
            <span class="truncate text-xs {active ? '' : 'text-muted-foreground'}">{call.location}. {responderLine(call)}</span>
          </button>
        {:else}
          <p class="px-1 py-6 text-sm text-muted-foreground">{filter === 'mine' ? t('ui.dispatch.none_mine') : t('ui.dispatch.none_closed')}</p>
        {/each}
      </div>
    </section>

    <section class="flex min-w-0 flex-1 flex-col">
      {#if selected}
        {#key selected.id}
          <CallDetail call={selected} onDuty={dashboard?.onDuty ?? []} onchange={refresh} />
        {/key}
      {:else}
        <Empty icon={Broadcast} title={t('ui.dispatch.none_selected')} body={t('ui.dispatch.none_selected_body')} />
      {/if}
    </section>
  </div>
{/if}
