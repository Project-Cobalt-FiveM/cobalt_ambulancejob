<script lang="ts">
  import { onMount } from 'svelte';
  import IconContext from 'phosphor-svelte/lib/IconContext';
  import { onMessage, sendMockOpen } from './lib/nui';
  import { mdt } from './lib/store.svelte';
  import { rise } from './lib/motion';
  import Sidebar from './components/Sidebar.svelte';
  import CallPopup from './components/CallPopup.svelte';
  import DeathScreen from './components/DeathScreen.svelte';
  import Toast from './components/Toast.svelte';
  import Dashboard from './pages/Dashboard.svelte';
  import Dispatch from './pages/Dispatch.svelte';
  import Patients from './pages/Patients.svelte';
  import PatientProfile from './pages/PatientProfile.svelte';
  import Reports from './pages/Reports.svelte';
  import ReportEditor from './pages/ReportEditor.svelte';
  import Prescriptions from './pages/Prescriptions.svelte';
  import Billing from './pages/Billing.svelte';
  import Beds from './pages/Beds.svelte';
  import Roster from './pages/Roster.svelte';
  import Management from './pages/management/Management.svelte';

  function isTyping(target: EventTarget | null): boolean {
    return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || (target instanceof HTMLElement && target.isContentEditable);
  }

  function onkeydown(event: KeyboardEvent) {
    if (!mdt.visible) return;

    if (event.key === 'Escape') {
      event.preventDefault();
      mdt.escape();
      return;
    }

    if (event.key === '/' && !isTyping(event.target)) {
      event.preventDefault();
      document.getElementById('global-search')?.focus();
    }
  }

  onMount(() => {
    const stop = onMessage((message) => mdt.handle(message));
    void mdt.boot().then(sendMockOpen);
    return stop;
  });
</script>

<svelte:window {onkeydown} />

<IconContext values={{ weight: 'fill' }}>
  {#if mdt.visible && mdt.medic}
    <div class="fixed inset-0 flex items-center justify-center">
      <div class="relative flex h-[57.5rem] w-[102.5rem] overflow-hidden rounded-lg border border-border bg-card" transition:rise={{ duration: 300 }}>
        <Sidebar />
        <main class="relative flex min-w-0 flex-1 flex-col">
          {#key mdt.route.page}
            {#if mdt.route.page === 'dashboard'}
              <Dashboard />
            {:else if mdt.route.page === 'dispatch'}
              <Dispatch />
            {:else if mdt.route.page === 'patients'}
              {#if mdt.route.citizenid}
                {#key mdt.route.citizenid}<PatientProfile citizenid={mdt.route.citizenid} />{/key}
              {:else}
                <Patients />
              {/if}
            {:else if mdt.route.page === 'reports'}
              {#if mdt.route.editor}
                {#key mdt.route.editor}<ReportEditor editor={mdt.route.editor} />{/key}
              {:else}
                <Reports initial={mdt.route.selected} />
              {/if}
            {:else if mdt.route.page === 'prescriptions'}
              <Prescriptions />
            {:else if mdt.route.page === 'billing'}
              <Billing />
            {:else if mdt.route.page === 'beds'}
              <Beds />
            {:else if mdt.route.page === 'roster'}
              <Roster />
            {:else if mdt.route.page === 'management'}
              <Management />
            {/if}
          {/key}
        </main>
        <Toast />
      </div>
    </div>
  {:else}
    <CallPopup />
  {/if}
  {#if mdt.death}
    {#key mdt.death.screen.kind}
      <DeathScreen screen={mdt.death.screen} offset={mdt.death.offset} />
    {/key}
  {/if}
</IconContext>
