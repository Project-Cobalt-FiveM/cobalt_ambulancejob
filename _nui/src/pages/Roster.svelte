<script lang="ts">
  import { onMount } from 'svelte';
  import Users from 'phosphor-svelte/lib/Users';
  import Header from '../components/Header.svelte';
  import Button from '../components/ui/Button.svelte';
  import Tabs from '../components/ui/Tabs.svelte';
  import Select from '../components/ui/Select.svelte';
  import Checkbox from '../components/ui/Checkbox.svelte';
  import Dot from '../components/ui/Dot.svelte';
  import Row from '../components/ui/Row.svelte';
  import Field from '../components/ui/Field.svelte';
  import Empty from '../components/ui/Empty.svelte';
  import { fetchNui } from '../lib/nui';
  import { mdt } from '../lib/store.svelte';
  import { longDate, plural, statusDots, statusLabel } from '../lib/format';
  import { t } from '../lib/locale.svelte';
  import { crossfade } from '../lib/motion';
  import type { Roster, StaffMember } from '../lib/types';

  type Filter = 'all' | 'onduty' | 'doctors' | 'trainees';

  let roster = $state<Roster>({ staff: [], ranks: [], certifications: [] });
  let filter = $state<Filter>('all');
  let selectedId = $state<string | null>(null);
  let callsign = $state('');
  let grade = $state(0);
  let held = $state<string[]>([]);
  let saving = $state(false);

  const staff = $derived(roster.staff);
  const list = $derived(staff.filter((member) => matches(member, filter)));
  const selected = $derived(staff.find((member) => member.citizenid === selectedId) ?? null);
  const labels = $derived(new Map(roster.certifications.map((certification) => [certification.id, certification.label])));
  const rankOptions = $derived(roster.ranks.map((rank) => ({ value: rank.grade, label: rank.name })));
  const manage = $derived(mdt.can('manageRoster'));
  const dirty = $derived(
    selected !== null &&
      (callsign.trim() !== selected.callsign ||
        grade !== selected.grade ||
        held.length !== selected.certifications.length ||
        held.some((id) => !selected.certifications.includes(id))),
  );

  async function load() {
    const reply = mdt.single(await fetchNui('getRoster'));
    if (!reply) return;

    roster = reply;
    const current = staff.find((member) => member.citizenid === selectedId) ?? staff[0];
    if (current) pick(current);
  }

  onMount(load);

  function matches(member: StaffMember, value: Filter): boolean {
    switch (value) {
      case 'onduty':
        return member.status !== 'offduty';
      case 'doctors':
        return member.doctor;
      case 'trainees':
        return member.trainee;
      default:
        return true;
    }
  }

  function count(value: Filter): number {
    return staff.filter((member) => matches(member, value)).length;
  }

  function pick(member: StaffMember) {
    selectedId = member.citizenid;
    callsign = member.callsign;
    grade = member.grade;
    held = [...member.certifications];
  }

  function certificationList(member: StaffMember): string {
    return member.certifications.map((id) => labels.get(id)).filter(Boolean).join(', ') || t('ui.roster.none_yet');
  }

  function dotFor(member: StaffMember, active: boolean): string {
    if (active) return 'bg-foreground';
    return member.status === 'offduty' ? 'bg-disabled-icon' : statusDots[member.status];
  }

  function toggle(id: string, checked: boolean) {
    held = checked ? [...held, id] : held.filter((entry) => entry !== id);
  }

  async function save() {
    if (!selected || saving || !callsign.trim()) return;
    saving = true;

    const result = await fetchNui('saveStaff', { citizenid: selected.citizenid, callsign: callsign.trim(), grade, certifications: [...held] });

    saving = false;
    if (mdt.report(result, t('ui.common.saved_toast', selected.name))) await load();
  }
</script>

<Header title={t('ui.sidebar.roster')} subtitle={t('ui.roster.subtitle', staff.length, count('onduty'))} />

<div class="flex min-h-0 flex-1" in:crossfade>
  <section class="flex min-w-0 flex-1 flex-col gap-4 overflow-y-auto p-6">
    <Tabs
      bind:value={filter}
      tabs={[
        { value: 'all', label: t('ui.common.all'), count: count('all') },
        { value: 'onduty', label: t('ui.dashboard.on_duty'), count: count('onduty') },
        { value: 'doctors', label: t('ui.roster.doctors'), count: count('doctors') },
        { value: 'trainees', label: t('ui.roster.trainees'), count: count('trainees') },
      ]}
    />
    <div class="overflow-hidden rounded-lg border border-border">
      <div class="flex items-center gap-4 border-b border-border bg-muted px-4 py-2.5 text-xs font-medium text-muted-foreground">
        <span class="flex-1">{t('ui.common.name')}</span>
        <span class="w-25 shrink-0">{t('ui.roster.callsign')}</span>
        <span class="w-37.5 shrink-0">{t('ui.roster.rank')}</span>
        <span class="w-45 shrink-0">{t('ui.roster.certifications')}</span>
        <span class="w-22.5 shrink-0">{t('ui.common.status')}</span>
      </div>
      {#each list as member (member.citizenid)}
        {@const active = member.citizenid === selectedId}
        {@const off = member.status === 'offduty' && !active}
        <button
          type="button"
          class="flex w-full items-center gap-4 border-b border-border px-4 py-3 text-left text-13 transition-colors last:border-b-0 {active ? 'bg-primary' : 'hover:bg-muted'}"
          onclick={() => pick(member)}
        >
          <span class="flex-1 truncate text-sm {active ? 'font-semibold' : 'font-medium'}">{member.name}</span>
          <span class="w-25 shrink-0 truncate tabular-nums">{member.callsign}</span>
          <span class="w-37.5 shrink-0 truncate">{member.rank}</span>
          <span class="w-45 shrink-0 truncate {active ? '' : 'text-muted-foreground'}">{certificationList(member)}</span>
          <span class="flex w-22.5 shrink-0 items-center gap-1.5 {off ? 'text-muted-foreground' : ''}">
            <Dot class={dotFor(member, active)} size="size-1.5" />
            {statusLabel(member.status)}
          </span>
        </button>
      {:else}
        <p class="px-4 py-8 text-center text-sm text-muted-foreground">{t('ui.roster.empty')}</p>
      {/each}
    </div>
  </section>

  <aside class="flex w-95 shrink-0 flex-col border-l border-border">
    {#if selected}
      {#key selected.citizenid}
        <div class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-6" in:crossfade>
          <div class="flex flex-col gap-1">
            <span class="text-13 text-muted-foreground tabular-nums">
              {selected.joinedAt != null ? t('ui.roster.joined_hours', longDate(selected.joinedAt), plural(selected.hoursOnDuty, 'ui.plural.hours')) : t('ui.roster.hours', plural(selected.hoursOnDuty, 'ui.plural.hours'))}
            </span>
            <h2 class="text-xl font-semibold tracking-[-0.01em]">{selected.name}</h2>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <Field label={t('ui.roster.callsign')}><input class="field tabular-nums" bind:value={callsign} maxlength="20" disabled={!manage} /></Field>
            <Field label={t('ui.roster.rank')}><Select label={t('ui.roster.rank')} options={rankOptions} bind:value={grade} disabled={!manage} /></Field>
          </div>
          <div class="flex flex-col gap-2">
            <span class="text-sm font-medium">{t('ui.roster.certifications')}</span>
            <div class="flex flex-col rounded-lg border border-border">
              {#each roster.certifications as certification (certification.id)}
                <div class="flex items-center gap-2.5 border-b border-border px-3 py-2.5 text-13 last:border-b-0">
                  <Checkbox label={certification.label} checked={held.includes(certification.id)} disabled={!manage} onchange={(checked) => toggle(certification.id, checked)} />
                  <span class="flex-1">{certification.label}</span>
                </div>
              {:else}
                <p class="px-3 py-2.5 text-13 text-muted-foreground">{t('ui.roster.no_certifications')}</p>
              {/each}
            </div>
          </div>
          <div class="flex flex-col">
            <Row label={t('ui.roster.reports_filed')}>{selected.reportsFiled}</Row>
            <Row label={t('ui.roster.revives_month')}>{selected.revivesMonth}</Row>
          </div>
        </div>
        {#if manage}
          <div class="px-6 pb-6">
            <Button variant="primary" class="w-full" disabled={!dirty || saving || !callsign.trim()} onclick={save}>{t('ui.roster.save')}</Button>
          </div>
        {/if}
      {/key}
    {:else}
      <Empty icon={Users} title={t('ui.roster.none_selected')} body={t('ui.roster.none_selected_body')} />
    {/if}
  </aside>
</div>
