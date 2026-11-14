<script lang="ts">
  import { onMount } from 'svelte';
  import Plus from 'phosphor-svelte/lib/Plus';
  import Button from '../../components/ui/Button.svelte';
  import Tabs from '../../components/ui/Tabs.svelte';
  import Select from '../../components/ui/Select.svelte';
  import Field from '../../components/ui/Field.svelte';
  import { fetchNui } from '../../lib/nui';
  import { mdt } from '../../lib/store.svelte';
  import { capitalise, money } from '../../lib/format';
  import { t } from '../../lib/locale.svelte';
  import type { ItemOption, TreatKind, Treatment, TreatmentCategory, TreatmentInput } from '../../lib/types';

  type Filter = 'all' | TreatmentCategory;

  type Draft = Omit<TreatmentInput, 'item'> & { item: string };

  const treatOrder: TreatKind[] = ['fracture', 'bleeding', 'burn', 'severed', 'down'];

  const categories: TreatmentCategory[] = ['injury', 'procedure', 'medication', 'fee'];

  const categoryOptions = $derived(categories.map((value) => ({ value, label: t(`ui.treatments.category.${value}`) })));

  let treatments = $state<Treatment[]>([]);
  let items = $state<ItemOption[]>([]);
  let filter = $state<Filter>('all');
  let draft = $state<Draft | null>(null);
  let busy = $state(false);

  const list = $derived(treatments.filter((entry) => filter === 'all' || entry.category === filter));
  const itemLabels = $derived(new Map(items.map((item) => [item.name, item.label])));
  const itemOptions = $derived([{ value: '', label: t('ui.common.none') }, ...items.map((item) => ({ value: item.name, label: item.label }))]);
  const valid = $derived(draft !== null && draft.name.trim() !== '' && draft.price >= 0 && draft.seconds >= 0);

  async function load() {
    const reply = mdt.list(await fetchNui('getTreatments'));
    if (!reply) return;

    treatments = reply;
    const current = treatments.find((entry) => entry.id === draft?.id) ?? treatments[0];
    if (current) pick(current);
  }

  onMount(() => {
    void load();
    void fetchNui('getItems').then((reply) => (items = mdt.list(reply) ?? items));
  });

  function count(value: Filter): number {
    return treatments.filter((entry) => value === 'all' || entry.category === value).length;
  }

  function pick(entry: Treatment) {
    draft = { ...entry, treats: [...entry.treats], item: entry.item ?? '' };
  }

  function startNew() {
    draft = { id: null, name: '', category: filter === 'all' ? 'injury' : filter, treats: [], item: '', price: 0, seconds: 0 };
  }

  function treatsList(entry: Treatment): string {
    if (entry.treats.length === 0) return t('ui.treatments.nothing');
    return capitalise(entry.treats.map((kind) => treatLabel(kind).toLowerCase()).join(', '));
  }

  function treatLabel(kind: TreatKind): string {
    return t(`ui.treatments.treats.${kind}`);
  }

  function toggleTreat(current: Draft, kind: TreatKind) {
    current.treats = current.treats.includes(kind) ? current.treats.filter((entry) => entry !== kind) : [...current.treats, kind];
  }

  async function save() {
    if (!draft || !valid || busy) return;
    busy = true;

    const payload: TreatmentInput = { ...$state.snapshot(draft), name: draft.name.trim(), item: draft.item || null };
    const result = await fetchNui('saveTreatment', payload);

    busy = false;
    if (!mdt.report(result, payload.id === null ? t('ui.treatments.added_toast') : t('ui.treatments.saved_toast'))) return;

    draft.id = result.id;
    await load();
  }

  async function remove() {
    if (!draft || draft.id === null) return;

    if (mdt.report(await fetchNui('deleteTreatment', { id: draft.id }), t('ui.common.deleted_toast', draft.name))) {
      draft = null;
      await load();
    }
  }
</script>

<section class="flex min-w-0 flex-1 flex-col gap-4 overflow-y-auto p-6">
  <div class="flex items-center gap-4">
    <div class="flex-1">
      <Tabs
        bind:value={filter}
        tabs={[
          { value: 'all', label: t('ui.common.all'), count: count('all') },
          { value: 'injury', label: t('ui.treatments.tab.injury'), count: count('injury') },
          { value: 'procedure', label: t('ui.treatments.tab.procedure'), count: count('procedure') },
          { value: 'medication', label: t('ui.treatments.tab.medication'), count: count('medication') },
          { value: 'fee', label: t('ui.treatments.tab.fee'), count: count('fee') },
        ]}
      />
    </div>
    <Button variant="link" onclick={startNew}><Plus size="0.875rem" />{t('ui.treatments.new')}</Button>
  </div>
  <div class="overflow-hidden rounded-lg border border-border">
    <div class="flex items-center gap-4 border-b border-border bg-muted px-4 py-2.5 text-xs font-medium text-muted-foreground">
      <span class="flex-1">{t('ui.treatments.treatment')}</span>
      <span class="w-37.5 shrink-0">{t('ui.treatments.treats_label')}</span>
      <span class="w-32.5 shrink-0">{t('ui.treatments.item_used')}</span>
      <span class="w-20 shrink-0 text-right">{t('ui.treatments.price')}</span>
    </div>
    {#each list as entry (entry.id)}
      {@const active = entry.id === draft?.id}
      <button
        type="button"
        class="flex w-full items-center gap-4 border-b border-border px-4 py-3 text-left text-13 transition-colors last:border-b-0 {active ? 'bg-primary' : 'hover:bg-muted'}"
        onclick={() => pick(entry)}
      >
        <span class="flex-1 truncate text-sm {active ? 'font-semibold' : 'font-medium'}">{entry.name}</span>
        <span class="w-37.5 shrink-0 truncate {entry.treats.length === 0 && !active ? 'text-muted-foreground' : ''}">{treatsList(entry)}</span>
        <span class="w-32.5 shrink-0 truncate {active ? '' : 'text-muted-foreground'}">{entry.item ? (itemLabels.get(entry.item) ?? entry.item) : t('ui.common.none')}</span>
        <span class="w-20 shrink-0 text-right tabular-nums">{money(entry.price)}</span>
      </button>
    {:else}
      <p class="px-4 py-8 text-center text-sm text-muted-foreground">{t('ui.treatments.empty')}</p>
    {/each}
  </div>
</section>

<aside class="flex w-85 shrink-0 flex-col gap-4 overflow-y-auto border-l border-border p-6">
  {#if draft}
    {@const current = draft}
    <h2 class="text-base font-semibold">{current.id === null ? t('ui.treatments.new') : t('ui.treatments.edit')}</h2>
    <Field label={t('ui.common.name')}><input class="field" bind:value={current.name} maxlength="60" /></Field>
    <Field label={t('ui.treatments.category_label')}><Select label={t('ui.treatments.category_label')} options={categoryOptions} bind:value={current.category} /></Field>
    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium">{t('ui.treatments.treats_label')}</span>
      <div class="flex flex-wrap gap-1.5">
        {#each treatOrder as kind (kind)}
          {@const on = current.treats.includes(kind)}
          <button
            type="button"
            aria-pressed={on}
            class="rounded-sm border px-2.5 py-0.5 text-13 font-medium transition-colors {on ? 'border-primary bg-primary text-primary-foreground' : 'border-border text-muted-foreground hover:bg-muted hover:text-foreground'}"
            onclick={() => toggleTreat(current, kind)}
          >
            {treatLabel(kind)}
          </button>
        {/each}
      </div>
    </div>
    <div class="flex gap-3">
      <Field label={t('ui.treatments.item_used')} class="flex-1"><Select label={t('ui.treatments.item_used')} options={itemOptions} bind:value={current.item} /></Field>
      <Field label={t('ui.treatments.price')} class="w-27.5 shrink-0">
        <span class="field flex items-center gap-1 focus-within:border-primary">
          <span class="text-muted-foreground tabular-nums">$</span>
          <input class="h-full min-w-0 flex-1 bg-transparent tabular-nums outline-none" type="number" min="0" bind:value={current.price} />
        </span>
      </Field>
    </div>
    <Field label={t('ui.treatments.takes')}>
      <span class="field flex items-center gap-1 focus-within:border-primary">
        <input class="h-full min-w-0 flex-1 bg-transparent tabular-nums outline-none" type="number" min="0" max="120" bind:value={current.seconds} />
        <span class="text-muted-foreground">{t('ui.treatments.seconds_unit')}</span>
      </span>
    </Field>
    <span class="flex-1"></span>
    <div class="flex gap-2">
      {#if current.id !== null}<Button variant="destructive" onclick={remove}>{t('ui.common.delete')}</Button>{/if}
      <span class="flex-1"></span>
      <Button variant="primary" disabled={!valid || busy} onclick={save}>{current.id === null ? t('ui.treatments.add') : t('ui.treatments.save')}</Button>
    </div>
  {:else}
    <p class="text-sm text-muted-foreground">{t('ui.treatments.pick')}</p>
  {/if}
</aside>
