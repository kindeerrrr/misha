<script lang="ts">
  import { activeTab, navigate } from '../../stores/nav'
  import { icons } from '../../lib/icons'
  import type { NavTab } from '../../lib/types'

  const tabs: { id: NavTab; label: string; icon: string }[] = [
    { id: 'dashboard', label: 'Главная',  icon: icons.home },
    { id: 'health',    label: 'Здоровье', icon: icons.heart },
    { id: 'emotions',  label: 'День',     icon: icons.sun },
    { id: 'finances',  label: 'Деньги',   icon: icons.wallet },
    { id: 'hub',       label: 'Все',      icon: icons.grid },
  ]
</script>

<nav class="bottom-nav">
  {#each tabs as tab}
    <button
      class="tab-item"
      class:active={$activeTab === tab.id}
      on:click={() => navigate(tab.id)}
      aria-label={tab.label}
    >
      <span class="tab-icon">{@html tab.icon}</span>
      <span class="tab-label">{tab.label}</span>
    </button>
  {/each}
</nav>

<style>
  .bottom-nav {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    display: flex;
    background-color: var(--color-card);
    border-top: 1px solid var(--color-border);
    padding-bottom: env(safe-area-inset-bottom);
    z-index: 100;
    max-width: 480px;
    margin: 0 auto;
  }

  .tab-item {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 2px;
    padding: 0.5rem 0.25rem 0.375rem;
    background: none;
    border: none;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
    color: var(--color-muted);
  }

  .tab-item.active { color: var(--color-accent); }
  .tab-item:active { opacity: 0.6; }

  .tab-icon {
    width: 1.375rem;
    height: 1.375rem;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .tab-icon :global(svg) {
    width: 100%;
    height: 100%;
  }

  .tab-label {
    font-family: "Source Serif 4", serif;
    font-size: 0.625rem;
    letter-spacing: 0.02em;
    line-height: 1;
  }
</style>
