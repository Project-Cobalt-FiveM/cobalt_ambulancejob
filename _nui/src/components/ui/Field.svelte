<script lang="ts">
  import type { Snippet } from 'svelte';

  let { label, hint, class: className = '', children }: { label: string; hint?: string; class?: string; children: Snippet } = $props();
</script>

<label class="flex min-w-0 flex-col gap-2 {className}">
  <span class="text-sm font-medium">{label}</span>
  {@render children()}
  {#if hint}<span class="text-xs text-muted-foreground">{hint}</span>{/if}
</label>
