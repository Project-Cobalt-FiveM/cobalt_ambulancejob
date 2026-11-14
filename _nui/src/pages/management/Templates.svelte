<script lang="ts">
  import { onMount } from 'svelte';
  import Button from '../../components/ui/Button.svelte';
  import Field from '../../components/ui/Field.svelte';
  import { fetchNui } from '../../lib/nui';
  import { mdt } from '../../lib/store.svelte';
  import { plural } from '../../lib/format';
  import { t } from '../../lib/locale.svelte';
  import type { Template, TemplateInput } from '../../lib/types';

  let templates = $state<Template[]>([]);
  let draft = $state<TemplateInput | null>(null);
  let busy = $state(false);

  const valid = $derived(draft !== null && draft.name.trim() !== '' && draft.narrative.trim() !== '');

  async function load() {
    const reply = mdt.list(await fetchNui('getTemplates'));
    if (!reply) return;

    templates = reply;
    const current = templates.find((entry) => entry.id === draft?.id) ?? templates[0];
    if (current) pick(current);
  }

  onMount(load);

  function pick(template: Template) {
    draft = { id: template.id, name: template.name, narrative: template.narrative };
  }

  async function save() {
    if (!draft || !valid || busy) return;
    busy = true;

    const payload = { ...draft, name: draft.name.trim() };
    const result = await fetchNui('saveTemplate', payload);

    busy = false;
    if (!mdt.report(result, payload.id === null ? t('ui.templates.added_toast') : t('ui.templates.saved_toast'))) return;

    draft.id = result.id;
    await load();
  }

  async function remove() {
    if (!draft || draft.id === null) return;

    if (mdt.report(await fetchNui('deleteTemplate', { id: draft.id }), t('ui.common.deleted_toast', draft.name))) {
      draft = null;
      await load();
    }
  }
</script>

<section class="flex w-75 shrink-0 flex-col gap-3 overflow-y-auto border-r border-border p-5">
  <div class="flex items-center">
    <h2 class="flex-1 text-sm font-semibold">{t('ui.templates.title')}</h2>
    <Button variant="link" onclick={() => (draft = { id: null, name: '', narrative: '' })}>{t('ui.templates.new')}</Button>
  </div>
  <div class="flex flex-col gap-1">
    {#each templates as template (template.id)}
      {@const active = template.id === draft?.id}
      <button
        type="button"
        class="flex flex-col gap-0.5 rounded-md px-3 py-2.5 text-left transition-colors {active ? 'bg-primary' : 'border border-border hover:bg-muted'}"
        onclick={() => pick(template)}
      >
        <span class="text-sm font-medium">{template.name}</span>
        <span class="text-xs tabular-nums {active ? '' : 'text-muted-foreground'}">{t('ui.templates.used', plural(template.uses, 'ui.plural.times'))}</span>
      </button>
    {:else}
      <p class="text-13 text-muted-foreground">{t('ui.templates.empty')}</p>
    {/each}
  </div>
</section>

<section class="flex min-w-0 flex-1 flex-col gap-4 p-6">
  {#if draft}
    {@const current = draft}
    <Field label={t('ui.common.name')}><input class="field" bind:value={current.name} maxlength="40" /></Field>
    <label class="flex min-h-0 flex-1 flex-col gap-2">
      <span class="text-sm font-medium">{t('ui.common.narrative')}</span>
      <textarea class="field min-h-0 flex-1 resize-none py-3 leading-6" bind:value={current.narrative} maxlength="8000"></textarea>
      <span class="text-xs text-muted-foreground">{t('ui.templates.hint')}</span>
    </label>
    <div class="flex gap-2">
      {#if current.id !== null}<Button variant="destructive" onclick={remove}>{t('ui.common.delete')}</Button>{/if}
      <span class="flex-1"></span>
      <Button variant="primary" disabled={!valid || busy} onclick={save}>{current.id === null ? t('ui.templates.add') : t('ui.templates.save')}</Button>
    </div>
  {:else}
    <p class="text-sm text-muted-foreground">{t('ui.templates.pick')}</p>
  {/if}
</section>
