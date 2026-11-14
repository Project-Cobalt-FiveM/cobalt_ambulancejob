<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import Clock from 'phosphor-svelte/lib/Clock';
  import X from 'phosphor-svelte/lib/X';
  import Header from '../components/Header.svelte';
  import Button from '../components/ui/Button.svelte';
  import Select from '../components/ui/Select.svelte';
  import Picker from '../components/ui/Picker.svelte';
  import Toggle from '../components/ui/Toggle.svelte';
  import Dot from '../components/ui/Dot.svelte';
  import { bloodLabel, tally, times } from '../components/records/format';
  import { fetchNui } from '../lib/nui';
  import { mdt, type ReportEditor } from '../lib/store.svelte';
  import { bodyPartLabel, bodyParts, clockTime, injuryDots, injuryKinds, injuryLabel, money, nowSeconds, outcomeLabel, pad, reportNumber, shortDate, toDate } from '../lib/format';
  import { t } from '../lib/locale.svelte';
  import { crossfade } from '../lib/motion';
  import type { PickOption } from '../components/ui/types';
  import type { BloodType, BodyPart, InjuryKind, Report, ReportDraft, ReportInjury, ReportOutcome, ReportStatus, Template, Treatment, TreatmentCategory } from '../lib/types';

  type PatientPick = { citizenid: string | null; name: string; bloodType?: BloodType };

  type BillLine = { key: string; label: string; amount: number; remove?: () => void };

  let { editor }: { editor: ReportEditor } = $props();

  const seed = untrack(() => editor);

  const outcomes: ReportOutcome[] = ['scene', 'transported', 'deceased'];
  const partOptions = $derived(bodyParts.map((value) => ({ value, label: bodyPartLabel(value) })));
  const kindOptions = $derived(injuryKinds.map((value) => ({ value, label: injuryLabel(value), dot: injuryDots[value] })));

  let draft = $state<ReportDraft>({
    id: seed.id,
    citizenid: seed.citizenid,
    patientName: '',
    callId: seed.callId,
    occurredAt: nowSeconds(),
    injuries: [],
    medications: [],
    extras: [],
    narrative: '',
    outcome: 'scene',
  });

  let bloodType = $state<BloodType>();
  let status = $state<ReportStatus>('draft');
  let author = $state<string | null>(null);
  let loading = $state(true);
  let treatments = $state.raw<Treatment[]>([]);
  let templates = $state.raw<Template[]>([]);
  let template = $state(seed.templateId ?? 0);
  let sendInvoice = $state(true);
  let savedAt = $state<number | null>(null);
  let busy = $state(false);
  let addingInjury = $state(false);
  let newPart = $state<BodyPart>('torso');
  let newKind = $state<InjuryKind>('bleeding');
  let timeInput = $state<HTMLInputElement>();

  const catalogue = $derived(new Map(treatments.map((treatment) => [treatment.id, treatment])));
  const ownsReport = $derived(author == null || author === mdt.medic?.citizenid || mdt.can('editOtherReports'));
  const editable = $derived(!loading && status === 'draft' && mdt.can('writeReports') && ownsReport);
  const hasPatient = $derived(draft.citizenid != null || draft.patientName.trim().length > 0);
  const invoiceAllowed = $derived(draft.citizenid != null && mdt.can('sendInvoices'));
  const billing = $derived(sendInvoice && invoiceAllowed);
  const ready = $derived(hasPatient && draft.narrative.trim().length > 0);
  const templateOptions = $derived([{ value: 0, label: t('ui.common.none') }, ...templates.map((entry) => ({ value: entry.id, label: entry.name }))]);

  const lines = $derived.by(() => {
    const given = tally(draft.injuries.flatMap((injury) => injury.treatments), catalogue)
      .filter(({ treatment }) => treatment.price > 0)
      .map(({ treatment, count }): BillLine => ({ key: `treatment-${treatment.id}`, label: times(treatment.name, count), amount: treatment.price * count }));

    const extras = draft.extras.flatMap((id, index): BillLine[] => {
      const treatment = catalogue.get(id);
      return treatment ? [{ key: `extra-${index}`, label: treatment.name, amount: treatment.price, remove: () => draft.extras.splice(index, 1) }] : [];
    });

    const medications = draft.medications.reduce((sum, id) => sum + (catalogue.get(id)?.price ?? 0), 0);
    const medicationLine: BillLine[] = draft.medications.length ? [{ key: 'medications', label: t('ui.editor.medications_line', draft.medications.length), amount: medications }] : [];

    return [...given, ...extras, ...medicationLine];
  });

  const total = $derived(lines.reduce((sum, line) => sum + line.amount, 0));

  const title = $derived(draft.id === null ? t('ui.editor.new_title') : t('ui.editor.title', reportNumber(draft.id)));
  const subtitle = $derived.by(() => {
    if (loading) return t('ui.common.loading');
    if (draft.id === null) return t('ui.editor.not_saved');
    if (status === 'filed') return t('ui.editor.filed', reportNumber(draft.id));
    return savedAt === null ? t('ui.editor.draft', reportNumber(draft.id)) : t('ui.editor.draft_saved', reportNumber(draft.id), clockTime(savedAt));
  });

  function fromReport(report: Report): ReportDraft {
    return {
      id: report.id,
      citizenid: report.citizenid,
      patientName: report.patientName,
      callId: report.callId,
      occurredAt: report.occurredAt,
      injuries: report.injuries,
      medications: report.medications,
      extras: report.extras,
      narrative: report.narrative,
      outcome: report.outcome,
    };
  }

  async function lookupBlood(citizenid: string | null): Promise<BloodType | undefined> {
    if (!citizenid) return;

    const found = mdt.list(await fetchNui('searchPatients', { query: citizenid })) ?? [];
    return found.find((patient) => patient.citizenid === citizenid)?.bloodType;
  }

  async function loadReport(id: number) {
    const report = mdt.single(await fetchNui('getReport', { id }));
    if (!report) return;

    draft = fromReport(report);
    bloodType = report.bloodType;
    status = report.status;
    author = report.medicCitizenid;
  }

  async function startReport() {
    const started = mdt.single(await fetchNui('newReport', { citizenid: seed.citizenid, callId: seed.callId, templateId: seed.templateId }));
    if (!started) return;

    draft = started;
    author = mdt.medic?.citizenid ?? null;
    bloodType = await lookupBlood(draft.citizenid);
  }

  onMount(async () => {
    void fetchNui('getTreatments').then((reply) => (treatments = mdt.list(reply) ?? treatments));
    void fetchNui('getTemplates').then((reply) => (templates = mdt.list(reply) ?? templates));

    await (seed.id === null ? startReport() : loadReport(seed.id));
    loading = false;
  });

  function toLocalInput(seconds: number): string {
    const date = toDate(seconds);
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  function setTime(value: string) {
    const parsed = new Date(value).getTime();
    if (!Number.isNaN(parsed)) draft.occurredAt = Math.floor(parsed / 1000);
  }

  function callLabel(id: number | null): string {
    if (id === null) return t('ui.common.none');

    const call = mdt.call(id);
    return call ? t('ui.editor.call_priority', id, call.priority) : t('ui.editor.call', id);
  }

  function patientLabel(): string {
    return draft.citizenid ? `${draft.patientName}, ${bloodLabel(bloodType)}` : t('ui.editor.unknown_patient_chip', draft.patientName);
  }

  function pickPatient(patient: PatientPick) {
    draft.citizenid = patient.citizenid;
    draft.patientName = patient.name;
    bloodType = patient.bloodType;
  }

  function clearPatient() {
    pickPatient({ citizenid: null, name: '' });
  }

  async function searchPatients(query: string): Promise<PickOption<PatientPick>[]> {
    if (query.trim().length < 2) return [];

    const found = mdt.list(await fetchNui('searchPatients', { query: query.trim() })) ?? [];
    return found.map((patient) => ({
      key: patient.citizenid,
      label: patient.name,
      detail: `${patient.citizenid}, ${bloodLabel(patient.bloodType)}`,
      value: { citizenid: patient.citizenid, name: patient.name, bloodType: patient.bloodType },
    }));
  }

  function unknownPatient(query: string): PickOption<PatientPick> {
    return {
      key: `unknown-${query}`,
      label: t('ui.editor.add_unknown', query),
      detail: t('ui.editor.no_record'),
      value: { citizenid: null, name: query },
    };
  }

  function options(categories: TreatmentCategory[], query: string, keep: (treatment: Treatment) => boolean): PickOption<number>[] {
    const text = query.trim().toLowerCase();
    return treatments
      .filter((treatment) => categories.includes(treatment.category) && keep(treatment) && treatment.name.toLowerCase().includes(text))
      .map((treatment) => ({ key: String(treatment.id), label: treatment.name, detail: money(treatment.price), value: treatment.id }));
  }

  function treatmentSearch(injury: ReportInjury) {
    const fits = (treatment: Treatment) => treatment.treats.includes(injury.kind) && !injury.treatments.includes(treatment.id);
    return async (query: string) => options(['injury', 'procedure'], query, fits);
  }

  async function searchMedications(query: string) {
    return options(['medication'], query, () => true);
  }

  async function searchExtras(query: string) {
    return options(['procedure', 'fee'], query, (treatment) => !draft.extras.includes(treatment.id) && treatment.treats.every((kind) => kind === 'down'));
  }

  function addInjury() {
    draft.injuries.push({ bodyPart: newPart, kind: newKind, label: injuryLabel(newKind), treatments: [], treated: false });
    addingInjury = false;
  }

  function applyTemplate(id: number) {
    const found = templates.find((entry) => entry.id === id);
    if (found) draft.narrative = found.narrative;
  }

  function snapshot(): ReportDraft {
    const value = $state.snapshot(draft);
    return { ...value, injuries: value.injuries.map((injury) => ({ ...injury, treated: injury.treatments.length > 0 })) };
  }

  async function saveDraft() {
    if (busy) return;
    busy = true;

    const result = await fetchNui('saveReport', snapshot());
    busy = false;
    if (!mdt.report(result, t('ui.editor.draft_saved_toast'))) return;

    draft.id = result.id;
    savedAt = nowSeconds();
  }

  async function file() {
    if (busy) return;
    busy = true;

    const result = await fetchNui('fileReport', { ...snapshot(), sendInvoice: billing });
    busy = false;
    if (!mdt.report(result, billing ? t('ui.editor.filed_billed_toast') : t('ui.editor.filed_toast'))) return;

    void mdt.refreshUnpaid();
    mdt.openReport(result.id);
  }

  $effect(() => {
    if (!addingInjury) return;
    return mdt.pushLayer(() => (addingInjury = false));
  });
</script>

{#snippet chip(label: string, remove: () => void, small: boolean)}
  <span class="inline-flex items-center gap-1 rounded-sm bg-secondary pr-1 pl-2 font-medium {small ? 'py-0.5 text-xs' : 'py-0.75 text-13'}">
    {label}
    {#if editable}
      <button type="button" class="rounded-sm p-0.5 text-muted-foreground hover:bg-secondary-hover hover:text-foreground" aria-label={t('ui.common.remove', label)} onclick={remove}>
        <X size="0.625rem" />
      </button>
    {/if}
  </span>
{/snippet}

<Header {title} {subtitle} />

<div class="flex min-h-0 flex-1" in:crossfade>
  <section class="flex min-w-0 flex-1 flex-col gap-4.5 overflow-y-auto p-6">
    <div class="flex gap-3">
      <div class="flex flex-1 flex-col gap-1.5">
        <span class="text-sm font-medium">{t('ui.common.patient')}</span>
        <div class="flex h-9 items-center gap-2 rounded-md border border-input px-1.5">
          {#if hasPatient}
            {@render chip(patientLabel(), clearPatient, false)}
          {:else if editable}
            <Picker label={t('ui.editor.choose_patient')} placeholder={t('ui.common.search_patients')} search={searchPatients} free={unknownPatient} onpick={pickPatient} />
          {:else}
            <span class="px-1.5 text-sm text-muted-foreground">{t('ui.common.none')}</span>
          {/if}
        </div>
      </div>
      <div class="flex w-37.5 shrink-0 flex-col gap-1.5">
        <span class="text-sm font-medium">{t('ui.editor.call_label')}</span>
        <div class="flex h-9 items-center rounded-md border border-input px-3 text-sm tabular-nums {draft.callId === null ? 'text-muted-foreground' : ''}">{callLabel(draft.callId)}</div>
      </div>
      <div class="flex w-45 shrink-0 flex-col gap-1.5">
        <span class="text-sm font-medium">{t('ui.editor.time')}</span>
        <div class="relative">
          <button type="button" class="field flex items-center gap-2 text-left" disabled={!editable} onclick={() => timeInput?.showPicker()}>
            <Clock size="0.875rem" class="shrink-0 text-muted-foreground" />
            <span class="tabular-nums">{shortDate(draft.occurredAt)}, {clockTime(draft.occurredAt)}</span>
          </button>
          <input bind:this={timeInput} type="datetime-local" aria-label={t('ui.editor.time')} tabindex="-1" class="sr-only" value={toLocalInput(draft.occurredAt)} onchange={(event) => setTime(event.currentTarget.value)} />
        </div>
      </div>
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium">{t('ui.common.injuries_and_treatment')}</span>
      <div class="flex flex-col rounded-lg border border-border">
        {#each draft.injuries as injury, index (index)}
          <div class="flex items-center gap-4 border-b border-border px-3.5 py-2.5 last:border-b-0">
            <span class="w-25 shrink-0 text-13 font-medium">{bodyPartLabel(injury.bodyPart)}</span>
            <span class="flex w-32.5 shrink-0 items-center gap-1.5 text-13"><Dot class={injuryDots[injury.kind]} size="size-1.5" />{injury.label}</span>
            <div class="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
              {#each injury.treatments as id, position (position)}
                {@render chip(catalogue.get(id)?.name ?? t('ui.editor.unknown_treatment'), () => injury.treatments.splice(position, 1), true)}
              {/each}
              {#if editable}<Picker label={t('ui.editor.add_treatment')} placeholder={t('ui.editor.search_treatments')} search={treatmentSearch(injury)} onpick={(id) => injury.treatments.push(id)} />{/if}
            </div>
            {#if injury.treatments.length}
              <span class="text-xs text-success">{t('ui.editor.treated')}</span>
            {:else}
              <span class="text-xs text-muted-foreground">{t('ui.editor.not_treated')}</span>
            {/if}
            {#if editable}
              <button type="button" class="rounded-sm p-1 text-muted-foreground hover:bg-muted hover:text-foreground" aria-label={t('ui.editor.remove_injury', bodyPartLabel(injury.bodyPart))} onclick={() => draft.injuries.splice(index, 1)}>
                <X size="0.75rem" />
              </button>
            {/if}
          </div>
        {:else}
          {#if !addingInjury}<p class="px-3.5 py-3 text-13 text-muted-foreground">{t('ui.editor.no_injuries')}</p>{/if}
        {/each}
        {#if addingInjury}
          <div class="flex items-center gap-2 border-t border-border px-3.5 py-2.5 first:border-t-0" in:crossfade>
            <Select class="w-40" label={t('ui.editor.body_part')} options={partOptions} bind:value={newPart} />
            <Select class="w-40" label={t('ui.editor.injury')} options={kindOptions} bind:value={newKind} />
            <div class="flex-1"></div>
            <Button size="sm" onclick={() => (addingInjury = false)}>{t('ui.common.cancel')}</Button>
            <Button size="sm" variant="primary" onclick={addInjury}>{t('ui.editor.add_injury')}</Button>
          </div>
        {/if}
      </div>
      {#if editable && !addingInjury}
        <button type="button" class="self-start rounded-sm border border-dashed border-input px-2 py-0.5 text-13 font-medium text-muted-foreground hover:text-foreground" onclick={() => (addingInjury = true)}>
          {t('ui.editor.add_injury')}
        </button>
      {/if}
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium">{t('ui.editor.medications_given')}</span>
      <div class="flex flex-wrap items-center gap-1.5">
        {#each draft.medications as id, position (position)}
          {@render chip(catalogue.get(id)?.name ?? t('ui.editor.unknown_medication'), () => draft.medications.splice(position, 1), false)}
        {:else}
          {#if !editable}<span class="text-13 text-muted-foreground">{t('ui.common.none')}</span>{/if}
        {/each}
        {#if editable}<Picker label={t('ui.editor.add_medication')} placeholder={t('ui.editor.search_medications')} search={searchMedications} onpick={(id) => draft.medications.push(id)} />{/if}
      </div>
    </div>

    <div class="flex min-h-50 flex-1 flex-col gap-1.5">
      <div class="flex items-center justify-between gap-3">
        <span class="text-sm font-medium">{t('ui.common.narrative')}</span>
        {#if editable}
          <Select class="w-50" prefix={t('ui.editor.template')} label={t('ui.editor.use_template')} options={templateOptions} bind:value={template} onchange={applyTemplate} />
        {/if}
      </div>
      <textarea
        class="field flex-1 resize-none py-2.5 leading-5.5"
        bind:value={draft.narrative}
        disabled={!editable}
        maxlength="8000"
        aria-label={t('ui.common.narrative')}
        placeholder={t('ui.editor.narrative_placeholder')}
      ></textarea>
    </div>

    <div class="flex items-center gap-3">
      <span class="text-sm font-medium">{t('ui.common.outcome')}</span>
      <div class="flex gap-0.5 rounded-md border border-border bg-muted p-0.75" role="radiogroup" aria-label={t('ui.common.outcome')}>
        {#each outcomes as outcome (outcome)}
          {@const active = draft.outcome === outcome}
          <button
            type="button"
            role="radio"
            aria-checked={active}
            disabled={!editable && !active}
            class="rounded-sm px-3 py-1 text-13 font-medium transition-colors {active ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:text-foreground'}"
            onclick={() => editable && (draft.outcome = outcome)}
          >
            {outcomeLabel(outcome)}
          </button>
        {/each}
      </div>
    </div>
  </section>

  <aside class="flex w-95 shrink-0 flex-col gap-4 border-l border-border p-6">
    <div class="flex flex-col gap-0.5">
      <h2 class="text-base font-semibold">{t('ui.editor.bill')}</h2>
      <p class="text-13 text-muted-foreground">{t('ui.editor.bill_note')}</p>
    </div>

    <div class="flex flex-col">
      {#each lines as line (line.key)}
        <div class="flex items-center justify-between gap-3 border-b border-border py-2.5 text-13">
          <span class="flex min-w-0 items-center gap-1.5">
            <span class="truncate">{line.label}</span>
            {#if line.remove && editable}
              <button type="button" class="rounded-sm p-0.5 text-muted-foreground hover:bg-muted hover:text-foreground" aria-label={t('ui.common.remove', line.label)} onclick={line.remove}><X size="0.625rem" /></button>
            {/if}
          </span>
          <span class="tabular-nums">{money(line.amount)}</span>
        </div>
      {:else}
        <p class="border-b border-border py-2.5 text-13 text-muted-foreground">{t('ui.editor.nothing_to_bill')}</p>
      {/each}
      {#if editable}
        <div class="pt-2.5"><Picker label={t('ui.editor.add_charge')} placeholder={t('ui.editor.search_charges')} search={searchExtras} onpick={(id) => draft.extras.push(id)} /></div>
      {/if}
    </div>

    <div class="flex items-baseline justify-between">
      <span class="text-sm font-medium text-muted-foreground">{t('ui.common.total')}</span>
      <span class="text-2xl font-semibold tabular-nums">{money(total)}</span>
    </div>

    <div class="flex items-center gap-3">
      <Toggle label={t('ui.editor.send_invoice')} checked={billing} disabled={!editable || !invoiceAllowed} onchange={(value) => (sendInvoice = value)} />
      <div class="flex flex-col gap-0.5">
        <span class="text-sm {invoiceAllowed ? '' : 'text-muted-foreground'}">{t('ui.editor.send_invoice')}</span>
        <span class="text-xs text-muted-foreground">{draft.citizenid == null ? t('ui.editor.needs_record') : t('ui.editor.paid_from_bank')}</span>
      </div>
    </div>

    {#if editable}
      <div class="mt-auto flex gap-2">
        <Button disabled={busy} onclick={saveDraft}>{t('ui.editor.save_draft')}</Button>
        <Button variant="primary" class="flex-1" disabled={busy || !ready} onclick={file}>{billing ? t('ui.editor.file_and_bill') : t('ui.editor.file_report')}</Button>
      </div>
    {:else if status === 'filed'}
      <p class="mt-auto text-13 text-muted-foreground">{t('ui.editor.locked')}</p>
    {/if}
  </aside>
</div>
