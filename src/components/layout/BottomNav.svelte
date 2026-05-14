<script lang="ts">
  import { activeTab, navigate } from '../../stores/nav'
  import type { NavTab } from '../../lib/types'

  const tabs: { id: NavTab; label: string; icon: string }[] = [
    { id: 'dashboard', label: 'Главная',   icon: '⌂' },
    { id: 'health',    label: 'Здоровье',  icon: '♡' },
    { id: 'emotions',  label: 'День',      icon: '✦' },
    { id: 'finances',  label: 'Деньги',    icon: '◎' },
    { id: 'habits',    label: 'Привычки',  icon: '◈' },
    { id: 'media',     label: 'Медиа',     icon: '▷' },
    { id: 'cat',       label: 'Кошка',     icon: '◇' },
    { id: 'settings',  label: 'Настройки', icon: '⚙' },
  ]
</script>

<nav class="bottom-nav">
  <div class="nav-scroll">
    {#each tabs as tab}
      <button
        class="tab-item"
        class:active={$activeTab === tab.id}
        on:click={() => navigate(tab.id)}
        aria-label={tab.label}
      >
        <span class="tab-icon">{tab.icon}</span>
        <span class="tab-label">{tab.label}</span>
      </button>
    {/each}
  </div>
</nav>

<style>
  .bottom-nav {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background-color: var(--color-card);
    border-top: 1px solid var(--color-border);
    padding-bottom: env(safe-area-inset-bottom);
    z-index: 100;
    max-width: 480px;
    margin: 0 auto;
  }

  .nav-scroll {
    display: flex;
    overflow-x: auto;
    scrollbar-width: none;
    -webkit-overflow-scrolling: touch;
  }
  .nav-scroll::-webkit-scrollbar { display: none; }

  .tab-item {
    flex: 0 0 auto;
    min-width: 4rem;
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
    font-size: 1.125rem;
    line-height: 1;
  }

  .tab-label {
    font-family: "Source Serif 4", serif;
    font-size: 0.5625rem;
    letter-spacing: 0.02em;
    line-height: 1;
    white-space: nowrap;
  }
</style>
