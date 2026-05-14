<script lang="ts">
  export let clickable = false
  export let padding: 'sm' | 'md' | 'lg' = 'md'
  export let onClick: (() => void) | null = null

  const paddings = { sm: '0.75rem', md: '1rem', lg: '1.25rem' }
</script>

<!-- svelte-ignore a11y-click-events-have-key-events -->
<!-- svelte-ignore a11y-no-static-element-interactions -->
<div
  class="card-wrapper"
  class:clickable
  style="--pad: {paddings[padding]}"
  on:click={onClick ?? undefined}
>
  <slot />
</div>

<style>
  .card-wrapper {
    background-color: var(--color-card);
    border-radius: 1.25rem;
    padding: var(--pad);
    border: 1px solid var(--color-border);
  }

  .clickable {
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: transform 0.1s, background-color 0.1s;
  }

  .clickable:active {
    transform: scale(0.98);
    background-color: var(--color-card-hover);
  }
</style>
