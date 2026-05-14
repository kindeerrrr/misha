<script lang="ts">
  export let title: string = ''
  export let subtitle: string = ''
  export let back: (() => void) | null = null
</script>

<div class="page-shell">
  {#if title}
    <header class="page-header">
      {#if back}
        <button class="back-btn" on:click={back} aria-label="Назад">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M15 18l-6-6 6-6"/>
          </svg>
        </button>
      {/if}
      <div class="header-text">
        <h1 class="section-title">{title}</h1>
        {#if subtitle}
          <p class="label mt-0.5">{subtitle}</p>
        {/if}
      </div>
      <slot name="action" />
    </header>
  {/if}

  <main class="page-content">
    <slot />
  </main>
</div>

<style>
  .page-shell {
    max-width: 480px;
    margin: 0 auto;
    padding: 0 1rem 6rem;
    min-height: 100dvh;
  }

  .page-header {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
    padding: 1rem 0 0.75rem;
  }

  .header-text {
    flex: 1;
  }

  .back-btn {
    background: none;
    border: none;
    color: var(--color-accent);
    cursor: pointer;
    padding: 0.25rem;
    margin-top: 0.125rem;
    -webkit-tap-highlight-color: transparent;
  }

  .page-content {
    padding-top: 0.25rem;
  }
</style>
