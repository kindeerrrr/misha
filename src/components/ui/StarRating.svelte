<script lang="ts">
  export let value: number = 0
  export let max: number = 5
  export let readonly = false
  export let size: 'sm' | 'md' = 'md'

  import { createEventDispatcher } from 'svelte'
  const dispatch = createEventDispatcher()

  function pick(n: number) {
    if (readonly) return
    dispatch('change', n)
  }
</script>

<div class="stars" class:sm={size === 'sm'}>
  {#each Array(max) as _, i}
    <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
    <span
      class="star"
      class:filled={i < value}
      class:interactive={!readonly}
      on:click={() => pick(i + 1)}
    >★</span>
  {/each}
</div>

<style>
  .stars { display: flex; gap: 0.125rem; }
  .star { font-size: 1.375rem; color: var(--color-border); transition: color 0.1s; line-height: 1; }
  .star.filled { color: var(--color-accent); }
  .star.interactive { cursor: pointer; -webkit-tap-highlight-color: transparent; }
  .star.interactive:active { transform: scale(1.2); }
  .sm .star { font-size: 1rem; }
</style>
