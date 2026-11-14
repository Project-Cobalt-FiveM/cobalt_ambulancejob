<script lang="ts">
  import MapPin from 'phosphor-svelte/lib/MapPin';
  import { mdt } from '../lib/store.svelte';
  import { countdown, distance } from '../lib/format';
  import { rise } from '../lib/motion';
  import { t } from '../lib/locale.svelte';
  import { bleed, responderLine, since } from './dispatch/calls';
  import type { Call } from '../lib/types';

  const shown = $derived(mdt.alerts.slice(0, 4));

  function badge(call: Call): string {
    return call.priority === 1 ? 'bg-destructive-solid' : 'bg-secondary';
  }
</script>

<div class="absolute top-8 right-8 flex w-95 flex-col gap-2.5" aria-live="polite">
  {#each shown as alert, index (alert.key)}
    {@const call = alert.call}
    <div transition:rise>
      {#if index === 0}
        {@const bleeding = bleed(call, mdt.now)}
        <div class="flex flex-col gap-3 rounded-lg border border-border bg-card p-4 shadow-lg">
          <div class="flex items-center gap-2">
            <span class="rounded-sm px-1.5 py-0.5 text-xs font-semibold {badge(call)}">{call.code}</span>
            <span class="flex-1 truncate text-xs font-medium text-muted-foreground tabular-nums">{t('ui.popup.call_number', call.id)}</span>
            <span class="text-xs text-muted-foreground tabular-nums">{since(call, mdt.now)}</span>
          </div>
          <div class="flex flex-col gap-1">
            <span class="text-base font-semibold">{call.title}</span>
            <span class="flex items-center gap-1.5 text-13 text-muted-foreground tabular-nums">
              <MapPin size="0.875rem" class="shrink-0" />{call.location}, {distance(alert.distance)}
            </span>
          </div>
          {#if bleeding}
            <div class="flex flex-col gap-1.5">
              <div class="flex items-center text-xs">
                <span class="flex-1 text-muted-foreground">{t('ui.popup.bleeds_out_in')}</span>
                <span class="font-semibold text-destructive tabular-nums">{countdown(bleeding.left)}</span>
              </div>
              <div class="flex h-1 overflow-hidden rounded-full bg-secondary">
                <div class="h-full rounded-full bg-destructive w-full origin-left transition-transform duration-300 ease-linear" style:transform="scaleX({bleeding.share})"></div>
              </div>
            </div>
          {/if}
          <div class="flex gap-2 text-13 font-medium">
            <span class="flex h-8.5 flex-1 items-center justify-center gap-2 rounded-md bg-primary">
              <span class="rounded-sm bg-cobalt-hover px-1.25 text-[0.6875rem] font-semibold">{mdt.keybinds.respond}</span>{t('ui.dispatch.respond')}
            </span>
            <span class="flex h-8.5 flex-1 items-center justify-center gap-2 rounded-md bg-secondary">
              <span class="rounded-sm bg-secondary-hover px-1.25 text-[0.6875rem] font-semibold">{mdt.keybinds.waypoint}</span>{t('ui.dispatch.set_waypoint')}
            </span>
          </div>
        </div>
      {:else}
        <div class="flex flex-col gap-1.5 rounded-lg border border-border bg-card px-4 py-3">
          <div class="flex items-center gap-2">
            <span class="rounded-sm px-1.5 py-0.5 text-xs font-semibold {badge(call)}">{call.code}</span>
            <span class="flex-1 truncate text-sm font-medium">{call.title}</span>
            <span class="text-xs text-muted-foreground tabular-nums">{since(call, mdt.now)}</span>
          </div>
          <span class="truncate text-xs text-muted-foreground">{call.location}, {responderLine(call)}</span>
        </div>
      {/if}
    </div>
  {/each}
</div>
