<script lang="ts">
  import CheckCircle from 'phosphor-svelte/lib/CheckCircle';
  import { fade } from 'svelte/transition';
  import { mdt } from '../lib/store.svelte';
  import { fetchNui } from '../lib/nui';
  import { countdown, money } from '../lib/format';
  import { ease, rise } from '../lib/motion';
  import { t } from '../lib/locale.svelte';
  import type { DeathScreen } from '../lib/types';
  import bloodLight from '../assets/blood-1.svg';
  import bloodMedium from '../assets/blood-2.svg';
  import bloodHeavy from '../assets/blood-3.svg';

  let { screen, offset }: { screen: DeathScreen; offset: number } = $props();

  const now = $derived(mdt.now + offset);
  const left = $derived(Math.max(0, (screen.kind === 'dead' ? screen.respawnAt : screen.endsAt) - now));
  const share = $derived(screen.kind === 'laststand' ? Math.min(1, left / screen.total) : 0);
  const ready = $derived(screen.kind === 'dead' && left <= 0);
  const severity = $derived(screen.kind !== 'laststand' || share > 0.6 ? 1 : share > 0.25 ? 2 : 3);
  const layers = $derived([bloodLight, bloodMedium, bloodHeavy].slice(0, severity));
  const spread = $derived(screen.kind === 'laststand' ? 1 + share * 0.22 : 1);

  let held = $state(0);

  $effect(() => {
    const hold = mdt.deathHold;

    if (!hold) {
      held = 0;
      return;
    }

    let frame = requestAnimationFrame(function tick(time) {
      held = Math.min(1, (time - hold.startedAt) / hold.ms);
      if (held < 1) frame = requestAnimationFrame(tick);
    });

    return () => cancelAnimationFrame(frame);
  });

  const holdLeft = $derived(mdt.deathHold ? ((1 - held) * mdt.deathHold.ms) / 1000 : 0);

  function respawn() {
    if (ready) void fetchNui('respawn');
  }
</script>

<div class="pointer-events-none fixed inset-0 select-none" transition:fade={{ duration: 300, easing: ease }}>
  <div class="absolute inset-0 transition-transform duration-300" style:transform="scale({spread})">
    {#each layers as layer (layer)}
      <img src={layer} alt="" class="absolute inset-0 size-full object-cover" transition:fade={{ duration: 300, easing: ease }} />
    {/each}
  </div>

  <div class="absolute inset-0 flex flex-col items-center justify-center gap-5 text-center" role="status" aria-live="polite">
    {#if screen.kind === 'knockedout'}
      <h1 class="text-[3.5rem] leading-none font-bold">{t('ui.death.out_cold')}</h1>
      <span class="text-[7rem] leading-none font-bold tabular-nums">{countdown(left)}</span>
      <span class="text-lg text-muted-foreground">{t('ui.death.until_come_round')}</span>
    {:else if screen.kind === 'laststand'}
      <h1 class="text-[3.5rem] leading-none font-bold">{t('ui.death.bleeding_out')}</h1>
      <span class="text-[8rem] leading-none font-bold text-destructive tabular-nums">{countdown(left)}</span>
      <div class="flex h-1.5 w-[28rem] overflow-hidden rounded-full bg-secondary">
        <div class="h-full rounded-full bg-destructive w-full origin-left transition-transform duration-300 ease-linear" style:transform="scaleX({share})"></div>
      </div>
      <div class="mt-6 flex h-20 flex-col items-center justify-start gap-3 text-xl font-medium">
        {#if screen.emsCalled}
          <span class="flex items-center gap-2.5" in:rise={{ y: 6, duration: 250 }}>
            <CheckCircle size="1.5rem" class="text-success" />{t('ui.death.ems_notified')}
          </span>
        {:else}
          <span class="flex items-center gap-3">
            <span class="flex size-10 items-center justify-center rounded-md text-lg font-semibold transition-colors {mdt.deathHold ? 'bg-primary' : 'bg-secondary'}">{screen.callKey}</span>
            {mdt.deathHold ? t('ui.death.keep_holding') : t('ui.death.hold_to_call')}
            {#if mdt.deathHold}
              <span class="w-12 text-left text-muted-foreground tabular-nums">{t('ui.common.seconds_short', holdLeft.toFixed(1))}</span>
            {/if}
          </span>
          {#if mdt.deathHold}
            <div class="flex h-1.5 w-64 overflow-hidden rounded-full bg-secondary" transition:fade={{ duration: 150, easing: ease }}>
              <div class="h-full rounded-full bg-primary" style:width="{held * 100}%"></div>
            </div>
          {/if}
        {/if}
      </div>
    {:else}
      <h1 class="text-[3.5rem] leading-none font-bold">{t('ui.death.unconscious')}</h1>
      {#if ready}
        <button
          type="button"
          class="pointer-events-auto mt-6 flex h-16 items-center gap-4 rounded-lg bg-primary pr-7 pl-4 text-xl font-semibold transition-colors hover:bg-cobalt-hover"
          onclick={respawn}
          in:rise={{ y: 6, duration: 250 }}
        >
          <span class="flex size-10 items-center justify-center rounded-md bg-cobalt-hover text-lg">{screen.respawnKey}</span>
          {t('ui.death.respawn_at', screen.hospital)}
          <span class="rounded-md bg-cobalt-hover px-2.5 py-1 text-lg tabular-nums">{money(screen.fee)}</span>
        </button>
      {:else}
        <span class="text-[8rem] leading-none font-bold tabular-nums">{countdown(left)}</span>
        <span class="text-lg text-muted-foreground">{t('ui.death.until_respawn', screen.hospital, money(screen.fee))}</span>
      {/if}
      {#if screen.killKey}
        <span class="mt-4 flex items-center gap-2.5 text-base text-muted-foreground">
          <span class="flex size-8 items-center justify-center rounded-md bg-secondary text-sm font-semibold text-foreground">{screen.killKey}</span>{t('ui.death.character_kill')}
        </span>
      {/if}
    {/if}
  </div>
</div>
