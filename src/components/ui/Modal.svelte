<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  export let title: string = ''
  export let open = false

  const dispatch = createEventDispatcher()
  function close() { dispatch('close') }
</script>

{#if open}
  <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
  <div class="overlay" on:click={close}>
    <div class="sheet" on:click|stopPropagation>
      <div class="handle" />
      {#if title}
        <h2 class="section-title mb-4">{title}</h2>
      {/if}
      <slot />
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.35);
    z-index: 200;
    display: flex;
    align-items: flex-end;
    justify-content: center;
  }

  .sheet {
    background-color: var(--color-bg);
    border-radius: 1.5rem 1.5rem 0 0;
    padding: 1rem 1.25rem calc(1.25rem + env(safe-area-inset-bottom));
    width: 100%;
    max-width: 480px;
    max-height: 90dvh;
    overflow-y: auto;
    animation: slideUp 0.25s cubic-bezier(0.32, 0.72, 0, 1);
  }

  .handle {
    width: 2.5rem;
    height: 4px;
    background-color: var(--color-border);
    border-radius: 2px;
    margin: 0 auto 1rem;
  }

  @keyframes slideUp {
    from { transform: translateY(100%); }
    to { transform: translateY(0); }
  }
</style>
