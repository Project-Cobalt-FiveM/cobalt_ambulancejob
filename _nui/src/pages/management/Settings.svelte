<script lang="ts">
  import { onMount } from 'svelte';
  import Toggle from '../../components/ui/Toggle.svelte';
  import { fetchNui } from '../../lib/nui';
  import { mdt } from '../../lib/store.svelte';
  import { t } from '../../lib/locale.svelte';
  import type { Settings } from '../../lib/types';

  let settings = $state<Settings | null>(null);

  onMount(async () => {
    settings = mdt.single(await fetchNui('getSettings'));
  });

  async function save(next: Settings, success: string): Promise<boolean> {
    if (!mdt.report(await fetchNui('saveSettings', next), success)) return false;

    settings = next;
    mdt.settings = next;
    return true;
  }

  async function saveShare(value: number) {
    if (!settings) return;

    await save({ ...settings, medicShare: Math.min(100, Math.max(0, Math.round(value))) }, t('ui.settings.share_saved'));
  }

  async function sharePolice(shareWithPolice: boolean) {
    if (!settings) return;

    const current = settings;
    if (!(await save({ ...current, shareWithPolice }, shareWithPolice ? t('ui.settings.police_on') : t('ui.settings.police_off')))) settings = { ...current };
  }
</script>

<section class="flex min-w-0 flex-1 flex-col gap-3 p-6">
  {#if settings}
    <div class="flex items-center gap-3 rounded-lg border border-border px-4 py-3">
      <div class="flex flex-1 flex-col gap-0.5">
        <span class="text-sm font-medium">{t('ui.settings.medic_share')}</span>
        <span class="text-xs text-muted-foreground">{t('ui.settings.medic_share_hint')}</span>
      </div>
      <span class="field flex h-8 w-24 shrink-0 items-center gap-1 px-2.5 text-13 focus-within:border-primary">
        <input
          class="h-full min-w-0 flex-1 bg-transparent tabular-nums outline-none"
          type="number"
          min="0"
          max="100"
          aria-label={t('ui.settings.medic_share_percent')}
          value={settings.medicShare}
          onchange={(event) => saveShare(event.currentTarget.valueAsNumber)}
        />
        <span class="text-muted-foreground">%</span>
      </span>
    </div>
    <div class="flex items-center gap-3 rounded-lg border border-border px-4 py-3">
      <div class="flex flex-1 flex-col gap-0.5">
        <span class="text-sm font-medium">{t('ui.settings.share_police')}</span>
        <span class="text-xs text-muted-foreground">{t('ui.settings.share_police_hint')}</span>
      </div>
      <Toggle label={t('ui.settings.share_police')} checked={settings.shareWithPolice} onchange={sharePolice} />
    </div>
  {/if}
</section>
