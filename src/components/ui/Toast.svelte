<script lang="ts">
  import { toasts } from '../../stores/toast'
</script>

{#if $toasts.length > 0}
  <div class="toast-stack">
    {#each $toasts as t (t.id)}
      <div class="toast toast-{t.type}">{t.message}</div>
    {/each}
  </div>
{/if}

<style>
  .toast-stack {
    position: fixed;
    bottom: 5.5rem;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    z-index: 9999;
    pointer-events: none;
    align-items: center;
  }

  .toast {
    padding: 0.625rem 1.25rem;
    border-radius: 2rem;
    font-size: 0.9375rem;
    font-weight: 500;
    white-space: nowrap;
    box-shadow: 0 4px 16px rgba(0,0,0,0.15);
    animation: slide-up 0.2s ease;
  }

  .toast-success { background: #22c55e; color: white; }
  .toast-error   { background: #ef4444; color: white; }
  .toast-info    { background: var(--color-accent); color: white; }

  @keyframes slide-up {
    from { opacity: 0; transform: translateY(0.5rem); }
    to   { opacity: 1; transform: translateY(0); }
  }
</style>
