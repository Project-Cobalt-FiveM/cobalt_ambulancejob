<script lang="ts">
  import { onMount } from 'svelte';
  import PlusSquare from 'phosphor-svelte/lib/PlusSquare';
  import Header from '../components/Header.svelte';
  import Button from '../components/ui/Button.svelte';
  import Badge from '../components/ui/Badge.svelte';
  import Dot from '../components/ui/Dot.svelte';
  import { bleed, stateLabel, units } from '../components/dispatch/calls';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { age, countdown, money, plural, shiftLabel, statusDots, statusLabel } from '../lib/format';
  import { t } from '../lib/locale.svelte';
  import { crossfade } from '../lib/motion';
  import type { BedOccupant, Call, Dashboard, DashboardStats, HospitalBeds, Page } from '../lib/types';

  type Stat = { label: string; value: string; note: string; tone: string; page: Page | null };

  type OccupantLine = { text: string; tone: string; dot: string | null };

  let data = $state<Dashboard | null>(null);

  const calls = $derived(mdt.openCalls.slice(0, 3));
  const hospitals = $derived((mdt.beds ?? []).filter((hospital) => hospital.total > 0));
  const stats = $derived(data ? statCards(data.stats, hospitals) : []);

  onMount(async () => {
    const reply = mdt.single(await fetchNui('getDashboard'));
    if (!reply) return;

    data = reply;
    mdt.beds = reply.hospitals;
  });

  function fourthCard(stats: DashboardStats): Stat {
    if (mdt.medic?.trainee && stats.training) {
      return {
        label: t('ui.dashboard.training'),
        value: t('ui.common.x_of_y', stats.training.done, stats.training.total),
        note: t('ui.dashboard.training_note'),
        tone: 'text-muted-foreground',
        page: 'reports',
      };
    }

    return {
      label: t('ui.dashboard.unpaid_invoices'),
      value: money(stats.unpaidTotal),
      note: t('ui.dashboard.unpaid_note', plural(stats.unpaidCount, 'ui.plural.invoices'), stats.overdueCount),
      tone: stats.overdueCount ? 'text-warning' : 'text-muted-foreground',
      page: 'billing',
    };
  }

  function bedsCard(hospitals: HospitalBeds[]): Stat {
    const total = hospitals.reduce((sum, hospital) => sum + hospital.total, 0);
    const occupied = hospitals.reduce((sum, hospital) => sum + hospital.occupied, 0);
    const full = total > 0 && occupied >= total;

    return {
      label: t('ui.dashboard.beds_free'),
      value: t('ui.common.x_of_y', total - occupied, total),
      note: total === 0 ? t('ui.dashboard.no_beds') : full ? t('ui.dashboard.beds_full') : t('ui.dashboard.beds_in_use', occupied),
      tone: full ? 'text-warning' : 'text-muted-foreground',
      page: null,
    };
  }

  function statCards(stats: DashboardStats, hospitals: HospitalBeds[]): Stat[] {
    return [
      {
        label: t('ui.dashboard.open_calls'),
        value: `${stats.openCalls}`,
        note: stats.patientsDown ? t('ui.dashboard.patients_down', plural(stats.patientsDown, 'ui.plural.patients')) : t('ui.dashboard.nobody_down'),
        tone: stats.patientsDown ? 'text-destructive' : 'text-muted-foreground',
        page: 'dispatch',
      },
      {
        label: t('ui.dashboard.medics_on_duty'),
        value: `${stats.medicsOnDuty}`,
        note: t('ui.dashboard.medics_note', stats.medicsAvailable, stats.medicsOnCalls),
        tone: 'text-muted-foreground',
        page: 'roster',
      },
      bedsCard(hospitals),
      fourthCard(stats),
    ];
  }

  function detail(call: Call): string {
    if (call.patient) return `${call.location}, ${call.patient.name}`;
    if (call.caller) return t('ui.dashboard.caller_detail', call.location, call.caller.number);
    return call.location;
  }

  function occupantLine(occupant: BedOccupant): OccupantLine {
    switch (occupant.state) {
      case 'down':
      case 'dead':
        return { text: stateLabel(occupant.state), tone: 'text-destructive', dot: 'bg-destructive' };
      case 'knocked_out':
        return { text: stateLabel(occupant.state), tone: 'text-warning', dot: 'bg-warning' };
      case 'alive':
        return { text: t(`ui.dashboard.bed_use.${occupant.use}`), tone: 'text-muted-foreground', dot: null };
      default: {
        const exhaustive: never = occupant.state;
        return exhaustive;
      }
    }
  }
</script>

{#snippet statBody(stat: Stat)}
  <span class="text-13 text-muted-foreground">{stat.label}</span>
  <span class="text-28 font-semibold tracking-[-0.02em] tabular-nums">{stat.value}</span>
  <span class="text-xs {stat.tone}">{stat.note}</span>
{/snippet}

<Header title={t('ui.sidebar.dashboard')} subtitle={shiftLabel(mdt.now)}>
  {#snippet action()}
    {#if mdt.can('writeReports')}
      <Button variant="primary" onclick={() => mdt.newReport()}><PlusSquare size="1rem" />{t('ui.common.new_report')}</Button>
    {/if}
  {/snippet}
</Header>

<div class="flex min-h-0 flex-1" in:crossfade>
  <section class="flex min-w-0 flex-1 flex-col gap-6 overflow-y-auto p-6">
    <div class="grid grid-cols-4 gap-3">
      {#each stats as stat (stat.label)}
        {#if stat.page}
          {@const page = stat.page}
          <button type="button" class="flex flex-col gap-2 rounded-lg border border-border p-4 text-left transition-colors hover:bg-muted" onclick={() => mdt.go(page)}>
            {@render statBody(stat)}
          </button>
        {:else}
          <div class="flex flex-col gap-2 rounded-lg border border-border p-4">{@render statBody(stat)}</div>
        {/if}
      {/each}
    </div>

    <div class="flex flex-col gap-3">
      <div class="flex items-center gap-2">
        <Dot class="bg-primary" />
        <h2 class="flex-1 text-base font-semibold">{t('ui.dashboard.live_calls')}</h2>
        {#if mdt.has('dispatch')}<Button variant="link" onclick={() => mdt.go('dispatch')}>{t('ui.dashboard.open_dispatch')}</Button>{/if}
      </div>
      <div class="flex flex-col overflow-hidden rounded-lg border border-border">
        {#each calls as call (call.id)}
          {@const bleeding = bleed(call, mdt.now)}
          <button type="button" class="flex items-center gap-4 border-b border-border px-4 py-3 text-left transition-colors last:border-b-0 hover:bg-muted" onclick={() => mdt.go('dispatch')}>
            <span class="flex w-12 shrink-0"><Badge tone={call.priority === 1 ? 'danger' : 'neutral'} strong>{call.code}</Badge></span>
            <span class="flex min-w-0 flex-1 flex-col gap-0.5">
              <span class="truncate text-sm font-medium">{call.title}</span>
              <span class="truncate text-xs text-muted-foreground">{detail(call)}</span>
            </span>
            {#if bleeding}
              <span class="w-30 shrink-0 text-13 text-destructive tabular-nums">{t('ui.dashboard.bleeds_out', countdown(bleeding.left))}</span>
            {:else}
              <span class="w-30 shrink-0 text-13 text-muted-foreground">{stateLabel(call.patient?.state ?? 'alive')}</span>
            {/if}
            <span class="w-27.5 shrink-0 truncate text-13 tabular-nums {call.responders.length ? '' : 'text-muted-foreground'}">{units(call) ?? t('ui.dashboard.unassigned')}</span>
            <span class="w-14 shrink-0 text-right text-13 text-muted-foreground tabular-nums">{age(call.createdAt, mdt.now)}</span>
          </button>
        {:else}
          <p class="px-4 py-6 text-center text-sm text-muted-foreground">{t('ui.dashboard.no_open_calls')}</p>
        {/each}
      </div>
    </div>

    {#each hospitals as hospital (hospital.id)}
      <div class="flex flex-col gap-3">
        <div class="flex items-baseline justify-between gap-3">
          <h2 class="truncate text-base font-semibold">{t('ui.dashboard.beds_at', hospital.label)}</h2>
          <span class="shrink-0 text-13 text-muted-foreground tabular-nums">{t('ui.dashboard.free_of', hospital.total - hospital.occupied, hospital.total)}</span>
        </div>
        <div class="grid auto-rows-fr grid-cols-6 gap-2">
          {#each hospital.beds as bed (bed.index)}
            {#if bed.occupant}
              {@const occupant = bed.occupant}
              {@const line = occupantLine(occupant)}
              <button type="button" class="flex min-w-0 flex-col gap-1 rounded-md border border-border p-3 text-left transition-colors hover:bg-muted" onclick={() => mdt.openPatient(occupant.citizenid)} in:crossfade>
                <span class="flex justify-between gap-2 text-xs text-muted-foreground">
                  <span class="truncate">{bed.label}</span>
                  <span class="shrink-0 tabular-nums">{age(occupant.since, mdt.now)}</span>
                </span>
                <span class="truncate text-13 font-semibold">{occupant.name}</span>
                <span class="flex min-w-0 items-center gap-1.5 text-xs {line.tone}">
                  {#if line.dot}<Dot class={line.dot} size="size-1.5" />{/if}
                  <span class="truncate">{line.text}</span>
                </span>
              </button>
            {:else}
              <div class="flex min-w-0 flex-col gap-1 rounded-md border border-dashed border-input p-3" in:crossfade>
                <span class="truncate text-xs text-muted-foreground">{bed.label}</span>
                <span class="text-13 text-muted-foreground">{t('ui.dashboard.bed_free')}</span>
              </div>
            {/if}
          {/each}
        </div>
      </div>
    {/each}
  </section>

  <aside class="flex w-85 shrink-0 flex-col gap-3 overflow-y-auto border-l border-border p-6">
    <h2 class="text-base font-semibold">{t('ui.dashboard.on_duty')}</h2>
    <div class="flex flex-col">
      {#each data?.onDuty ?? [] as medic (medic.citizenid)}
        <div class="flex items-center gap-2.5 border-b border-border py-2.5 last:border-b-0">
          <Dot class={statusDots[medic.status]} />
          <div class="flex min-w-0 flex-1 flex-col gap-0.5">
            <span class="truncate text-13 font-semibold">{medic.callsign ? `${medic.callsign}, ${medic.name}` : medic.name}</span>
            <span class="truncate text-xs text-muted-foreground">{medic.detail}</span>
          </div>
          <span class="shrink-0 text-xs">{statusLabel(medic.status)}</span>
        </div>
      {:else}
        <p class="py-4 text-sm text-muted-foreground">{t('ui.dashboard.no_medics')}</p>
      {/each}
    </div>
  </aside>
</div>
