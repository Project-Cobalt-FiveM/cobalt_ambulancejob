<script lang="ts" module>
  let lastQuery = '';
</script>

<script lang="ts">
  import PlusSquare from 'phosphor-svelte/lib/PlusSquare';
  import MagnifyingGlass from 'phosphor-svelte/lib/MagnifyingGlass';
  import UsersThree from 'phosphor-svelte/lib/UsersThree';
  import Header from '../components/Header.svelte';
  import SearchBox from '../components/SearchBox.svelte';
  import Button from '../components/ui/Button.svelte';
  import Badge from '../components/ui/Badge.svelte';
  import Tabs from '../components/ui/Tabs.svelte';
  import Row from '../components/ui/Row.svelte';
  import Empty from '../components/ui/Empty.svelte';
  import { bornOn, shortBlood } from '../components/records/format';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { capitalise, initials, money, plural, shortDate } from '../lib/format';
  import { crossfade } from '../lib/motion';
  import { t } from '../lib/locale.svelte';
  import type { PatientSummary } from '../lib/types';

  type Filter = 'all' | 'admitted' | 'unpaid';

  let query = $state(lastQuery);
  let filter = $state<Filter>('all');
  let results = $state<PatientSummary[]>([]);
  let selectedId = $state<string | null>(null);
  let request = 0;

  const matches: Record<Filter, (patient: PatientSummary) => boolean> = {
    all: () => true,
    admitted: (patient) => patient.admission !== null,
    unpaid: (patient) => patient.balance > 0,
  };

  const filtered = $derived(results.filter(matches[filter]));
  const selected = $derived(results.find((patient) => patient.citizenid === selectedId) ?? null);
  const count = (value: Filter) => results.filter(matches[value]).length;

  $effect(() => {
    const text = query.trim();
    const current = ++request;
    lastQuery = text;
    if (text.length === 1) return;

    const timer = setTimeout(async () => {
      const found = mdt.list(await fetchNui('searchPatients', { query: text }));
      if (!found || current !== request) return;

      results = found;
      if (!results.some((patient) => patient.citizenid === selectedId)) selectedId = results[0]?.citizenid ?? null;
    }, 200);

    return () => clearTimeout(timer);
  });

  function isDown(patient: PatientSummary): boolean {
    return patient.state === 'down' || patient.state === 'dead';
  }

  function lastTreated(patient: PatientSummary): string {
    return patient.lastTreated ? `${shortDate(patient.lastTreated.at)}, ${patient.lastTreated.summary}` : t('ui.patients.never');
  }
</script>

<Header title={t('ui.sidebar.patients')} subtitle={t('ui.patients.subtitle')}>
  {#snippet action()}
    {#if mdt.can('writeReports')}
      <Button variant="primary" onclick={() => mdt.newReport()}><PlusSquare size="1rem" />{t('ui.common.new_report')}</Button>
    {/if}
  {/snippet}
</Header>

<div class="flex min-h-0 flex-1" in:crossfade>
  <section class="flex min-w-0 flex-1 flex-col gap-4 overflow-y-auto p-6">
    <SearchBox bind:value={query} icon={MagnifyingGlass} placeholder={t('ui.patients.search_placeholder')} autofocus count={plural(results.length, 'ui.plural.results')} />

    {#if results.length}
      <Tabs
        bind:value={filter}
        tabs={[
          { value: 'all', label: t('ui.common.all'), count: results.length },
          { value: 'admitted', label: t('ui.patients.admitted'), count: count('admitted') },
          { value: 'unpaid', label: t('ui.patients.unpaid_bills'), count: count('unpaid') },
        ]}
      />

      <div class="flex flex-col gap-1">
        <div class="mb-0.5 grid grid-cols-[2.25rem_1fr_6.875rem_5.625rem_11.25rem] gap-4 px-4 text-xs font-medium text-muted-foreground">
          <span></span><span>{t('ui.common.name')}</span><span>{t('ui.common.citizen_id')}</span><span>{t('ui.patients.blood')}</span><span>{t('ui.common.status')}</span>
        </div>
        {#each filtered as patient (patient.citizenid)}
          {@const active = patient.citizenid === selectedId}
          <button
            type="button"
            class="grid grid-cols-[2.25rem_1fr_6.875rem_5.625rem_11.25rem] items-center gap-4 rounded-lg border px-4 py-2.5 text-left transition-colors {active ? 'border-primary bg-primary' : 'border-border hover:bg-muted'}"
            onclick={() => (selectedId = patient.citizenid)}
            ondblclick={() => mdt.openPatient(patient.citizenid)}
          >
            <span class="flex size-9 items-center justify-center rounded-full text-13 font-semibold {active ? 'bg-cobalt-hover' : 'bg-secondary'}">{initials(patient.name)}</span>
            <span class="flex min-w-0 flex-col gap-0.5">
              <span class="truncate text-sm {active ? 'font-semibold' : 'font-medium'}">{patient.name}</span>
              <span class="truncate text-xs {active ? '' : 'text-muted-foreground'}">{t('ui.patients.sex_born', capitalise(patient.sex), bornOn(patient.dob))}</span>
            </span>
            <span class="text-13 tabular-nums">{patient.citizenid}</span>
            <span class="text-13 {patient.bloodType || active ? '' : 'text-muted-foreground'}">{shortBlood(patient.bloodType)}</span>
            <span class="flex gap-1 overflow-hidden">
              {#if isDown(patient)}<Badge tone="danger">{t('ui.patients.down')}</Badge>{/if}
              {#if patient.admission}<Badge tone={active ? 'onPrimary' : 'neutral'}>{patient.admission}</Badge>{/if}
              {#if patient.balance > 0}<Badge tone={active ? 'onPrimary' : 'neutral'}>{t('ui.patients.unpaid', money(patient.balance))}</Badge>{/if}
            </span>
          </button>
        {:else}
          <p class="px-4 py-8 text-center text-sm text-muted-foreground">{t('ui.patients.no_filter_match')}</p>
        {/each}
      </div>
    {:else}
      <Empty icon={UsersThree} title={t('ui.common.no_patients_match')} body={t('ui.patients.no_match_body')} />
    {/if}
  </section>

  <aside class="flex w-100 shrink-0 flex-col gap-5 border-l border-border p-6">
    {#if selected}
      {#key selected.citizenid}
        <div class="flex flex-1 flex-col gap-5" in:crossfade>
          <div class="flex flex-col gap-0.5">
            <h2 class="truncate text-xl font-semibold tracking-[-0.01em]">{selected.name}</h2>
            <span class="text-13 text-muted-foreground tabular-nums">{selected.citizenid}{selected.age !== null ? `, ${t('ui.patients.years_old', selected.age)}` : ''}</span>
          </div>

          <div class="flex flex-col">
            <Row label={t('ui.common.blood_type')}>{selected.bloodType ?? t('ui.common.unknown')}</Row>
            <Row label={t('ui.patients.conditions')}>{selected.conditions.join(', ') || t('ui.common.none')}</Row>
            <Row label={t('ui.patients.last_treated')}>{lastTreated(selected)}</Row>
            <Row label={t('ui.patients.balance_owed')}>{money(selected.balance)}</Row>
          </div>

          <div class="mt-auto flex gap-2">
            <Button variant="primary" class="flex-1" onclick={() => selected && mdt.openPatient(selected.citizenid)}>{t('ui.patients.open_record')}</Button>
            {#if mdt.can('writeReports')}
              <Button onclick={() => selected && mdt.newReport(selected.citizenid)}>{t('ui.patients.start_report')}</Button>
            {/if}
          </div>
        </div>
      {/key}
    {:else}
      <p class="text-sm text-muted-foreground">{t('ui.patients.pick')}</p>
    {/if}
  </aside>
</div>
