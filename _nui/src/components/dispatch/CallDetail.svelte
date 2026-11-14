<script lang="ts">
  import NavigationArrow from 'phosphor-svelte/lib/NavigationArrow';
  import Button from '../ui/Button.svelte';
  import Dot from '../ui/Dot.svelte';
  import { bleed, stateLabel } from './calls';
  import { fetchNui } from '../../lib/nui';
  import { mdt } from '../../lib/store.svelte';
  import { bodyPartLabel, capitalise, clockTime, countdown, distance, injuryDots, injuryLabel, statusDots, statusLabel } from '../../lib/format';
  import { t } from '../../lib/locale.svelte';
  import { crossfade, rise } from '../../lib/motion';
  import type { BodyPart, Call, Injury, OnDutyMedic, Responder, Result } from '../../lib/types';

  const regions: [BodyPart[], string][] = [
    [['head'], 'ui.body_part.head'],
    [['torso'], 'ui.body_part.torso'],
    [['left_arm', 'right_arm'], 'ui.body_part.arms'],
    [['left_leg', 'right_leg'], 'ui.body_part.legs'],
  ];

  let { call, onDuty, onchange }: { call: Call; onDuty: OnDutyMedic[]; onchange: () => Promise<void> } = $props();

  let assigning = $state(false);

  const open = $derived(call.status === 'open');
  const responding = $derived(mdt.isResponding(call));
  const bleeding = $derived(bleed(call, mdt.now));
  const assignable = $derived(onDuty.filter((medic) => !call.responders.some((responder) => responder.citizenid === medic.citizenid)));
  const details = $derived(
    [
      [t('ui.dispatch.location'), call.distance == null ? call.location : `${call.location}, ${distance(call.distance)}`],
      [t('ui.dispatch.raised_by'), call.raisedBy],
      [t('ui.dispatch.caller'), call.caller && `${call.caller.name}, ${call.caller.number}`],
      [t('ui.dispatch.details'), call.description],
      [t('ui.common.blood_type'), call.patient?.bloodType],
    ].filter((entry): entry is [string, string] => Boolean(entry[1])),
  );
  const unhurt = $derived(call.patient ? unhurtLabel(call.patient.injuries) : '');

  $effect(() => {
    if (!assigning) return;
    return mdt.pushLayer(() => (assigning = false));
  });

  function unhurtLabel(injuries: Injury[]): string {
    const unhurt = (part: BodyPart) => !injuries.some((injury) => injury.bodyPart === part);
    const labels = regions.flatMap(([group, whole]) => {
      const kept = group.filter(unhurt);
      return kept.length === group.length ? [t(whole).toLowerCase()] : kept.map((part) => bodyPartLabel(part).toLowerCase());
    });

    return capitalise(labels.join(', '));
  }

  function chip(responder: Responder): string {
    const medic = onDuty.some((entry) => entry.citizenid === responder.citizenid);
    return medic ? `${responder.callsign} ${responder.name.split(' ').at(-1)}` : responder.callsign;
  }

  async function act(request: Promise<Result | null>, success: string) {
    if (mdt.report(await request, success)) await onchange();
  }

  function respond() {
    void act(responding ? fetchNui('leaveCall', { id: call.id }) : fetchNui('respondCall', { id: call.id }), responding ? t('ui.dispatch.left_toast') : t('ui.dispatch.responding_toast'));
  }

  async function waypoint() {
    mdt.report(await fetchNui('waypointCall', { id: call.id }), t('ui.dispatch.waypoint_toast'));
  }

  function assign(medic: OnDutyMedic) {
    assigning = false;
    void act(fetchNui('assignCall', { id: call.id, citizenid: medic.citizenid }), t('ui.dispatch.assigned_toast', medic.callsign || medic.name));
  }
</script>

<div class="flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto p-6" in:crossfade>
  <div class="flex items-start gap-3">
    <div class="flex min-w-0 flex-1 flex-col gap-1">
      <span class="text-13 text-muted-foreground tabular-nums">{t('ui.dispatch.call_heading', call.code, call.id, clockTime(call.createdAt))}</span>
      <h2 class="text-28 font-semibold tracking-[-0.02em]">{call.title}</h2>
    </div>
    {#if open}
      <div class="flex gap-2">
        {#if call.coords}<Button onclick={waypoint}><NavigationArrow size="0.875rem" />{t('ui.dispatch.set_waypoint')}</Button>{/if}
        <Button variant={responding ? 'secondary' : 'primary'} onclick={respond}>
          {responding ? t('ui.dispatch.leave_call') : t('ui.dispatch.respond')}
          {#if !responding}<span class="rounded-sm bg-cobalt-hover px-1.5 text-xs">{mdt.keybinds.respond}</span>{/if}
        </Button>
      </div>
    {/if}
  </div>

  {#if bleeding && call.patient}
    <div class="flex flex-col gap-2 rounded-lg border border-border p-4">
      <div class="flex justify-between">
        <span class="text-sm font-medium">{t('ui.dispatch.bleeding_out', stateLabel(call.patient.state))}</span>
        <span class="text-sm font-semibold text-destructive tabular-nums">{bleeding.left ? t('ui.dispatch.time_left', countdown(bleeding.left)) : t('ui.dispatch.bled_out')}</span>
      </div>
      <div class="flex h-1.5 overflow-hidden rounded-full bg-secondary">
        <div class="h-full rounded-full bg-destructive w-full origin-left transition-transform duration-300 ease-linear" style:transform="scaleX({bleeding.share})"></div>
      </div>
      <p class="text-xs text-muted-foreground">{t('ui.dispatch.bleed_hint')}</p>
    </div>
  {/if}

  <div class="flex gap-6">
    <div class="flex min-w-0 flex-1 flex-col">
      {#if call.patient}
        {@const patient = call.patient}
        <div class="flex gap-4 border-b border-border py-2.5 text-13">
          <span class="w-30 shrink-0 text-muted-foreground">{t('ui.common.patient')}</span>
          <button type="button" class="min-w-0 text-left font-medium text-cobalt-foreground hover:text-foreground" onclick={() => mdt.openPatient(patient.citizenid)}>{patient.name}, {patient.citizenid}</button>
        </div>
      {/if}
      {#each details as [label, value] (label)}
        <div class="flex gap-4 border-b border-border py-2.5 text-13">
          <span class="w-30 shrink-0 text-muted-foreground">{label}</span>
          <span class="min-w-0 flex-1">{value}</span>
        </div>
      {/each}
    </div>

    {#if call.patient}
      <div class="flex w-75 shrink-0 flex-col gap-2">
        <h3 class="text-sm font-semibold">{t('ui.dispatch.injuries_reported')}</h3>
        <div class="flex flex-col rounded-lg border border-border">
          {#each call.patient.injuries as injury (`${injury.bodyPart}-${injury.kind}`)}
            <div class="flex items-center gap-2.5 border-b border-border px-3 py-2.5 text-13 last:border-b-0">
              <Dot size="size-1.5" class={injuryDots[injury.kind]} />
              <span class="flex-1">{bodyPartLabel(injury.bodyPart)}</span>
              <span>{injuryLabel(injury.kind)}</span>
            </div>
          {/each}
          {#if unhurt}
            <div class="flex items-center gap-2.5 px-3 py-2.5 text-13 text-muted-foreground">
              <Dot size="size-1.5" class="bg-disabled-icon" />
              <span class="flex-1">{unhurt}</span>
              <span>{t('ui.common.none')}</span>
            </div>
          {/if}
        </div>
      </div>
    {/if}
  </div>

  <div class="flex flex-col gap-2">
    <h3 class="text-sm font-semibold">{t('ui.dispatch.responding_heading')}</h3>
    <div class="flex flex-wrap items-center gap-1.5">
      {#each call.responders as responder (responder.citizenid)}
        <span class="rounded-sm bg-secondary px-2 py-0.75 text-13 font-medium tabular-nums">{chip(responder)}</span>
      {:else}
        {#if !open}<span class="text-13 text-muted-foreground">{t('ui.dispatch.nobody_responded')}</span>{/if}
      {/each}
      {#if open && assignable.length}
        <div class="relative">
          <button
            type="button"
            class="rounded-sm border border-dashed border-input px-2 py-0.5 text-13 font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            onclick={() => (assigning = !assigning)}
          >
            {t('ui.dispatch.assign_unit')}
          </button>
          {#if assigning}
            <button type="button" class="fixed inset-0 z-30 cursor-default" aria-label={t('ui.common.close')} tabindex="-1" onclick={() => (assigning = false)}></button>
            <ul class="absolute top-full left-0 z-40 mt-1 w-64 rounded-lg border border-border bg-popover p-1 shadow-lg" transition:rise>
              {#each assignable as medic (medic.citizenid)}
                <li>
                  <button type="button" class="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-muted" onclick={() => assign(medic)}>
                    <Dot class={statusDots[medic.status]} />
                    <span class="flex min-w-0 flex-1 flex-col">
                      <span class="truncate text-sm font-medium tabular-nums">{medic.callsign ? `${medic.callsign}, ${medic.name}` : medic.name}</span>
                      <span class="truncate text-xs text-muted-foreground">{medic.detail}</span>
                    </span>
                    <span class="shrink-0 text-xs text-muted-foreground">{statusLabel(medic.status)}</span>
                  </button>
                </li>
              {/each}
            </ul>
          {/if}
        </div>
      {/if}
    </div>
  </div>
</div>

<div class="flex items-center gap-2 px-6 pb-6">
  {#if open && call.patient}
    <Button onclick={() => act(fetchNui('markTransported', { id: call.id }), t('ui.dispatch.transported_toast'))}>{t('ui.dispatch.mark_transported')}</Button>
  {/if}
  {#if mdt.can('writeReports')}
    <Button onclick={() => mdt.newReport(call.patient?.citizenid ?? null, call.id)}>{t('ui.dispatch.start_report')}</Button>
  {/if}
  <span class="flex-1"></span>
  {#if open}
    <Button onclick={() => act(fetchNui('closeCall', { id: call.id }), t('ui.dispatch.closed_toast'))}>{t('ui.dispatch.close_call')}</Button>
  {/if}
</div>
