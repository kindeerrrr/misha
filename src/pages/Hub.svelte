<script lang="ts">
  import { navigate } from '../stores/nav'
  import type { NavTab } from '../lib/types'

  const sections: {
    id: NavTab
    title: string
    sub: string
    symbol: string
    soon?: boolean
  }[] = [
    { id: 'habits',   title: 'Привычки',    sub: 'Ежедневный трекер',        symbol: '◈' },
    { id: 'media',    title: 'Медиа',       sub: 'Книги, фильмы, сериалы',   symbol: '▷' },
    { id: 'cat',      title: 'Кошка',       sub: 'Здоровье, уход, корм',     symbol: '◇' },
    { id: 'settings', title: 'Настройки',   sub: 'Тема и параметры',         symbol: '⚙' },
    { id: 'dashboard', title: 'Путешествия', sub: 'Поездки и маршруты',      symbol: '→', soon: true },
    { id: 'dashboard', title: 'Кредиты',    sub: 'Долги и платежи',          symbol: '₽', soon: true },
  ]
</script>

<div class="page-shell">
  <header class="hub-header">
    <h1 class="hub-title">Все разделы</h1>
    <p class="hub-sub">Быстрый доступ ко всему</p>
  </header>

  <div class="hub-grid">
    {#each sections as s}
      <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
      <div
        class="hub-card"
        class:soon={s.soon}
        on:click={() => !s.soon && navigate(s.id)}
      >
        <div class="hub-symbol">{s.symbol}</div>
        <div class="hub-text">
          <span class="hub-name">{s.title}</span>
          <span class="hub-desc">{s.sub}</span>
        </div>
        {#if s.soon}
          <span class="soon-badge">Скоро</span>
        {:else}
          <span class="hub-arrow">›</span>
        {/if}
      </div>
    {/each}
  </div>
</div>

<style>
  .page-shell {
    max-width: 480px;
    margin: 0 auto;
    padding: 0 1rem 6rem;
  }

  .hub-header {
    padding: 1.5rem 0 1.25rem;
  }

  .hub-title {
    font-family: "Fraunces", serif;
    font-size: 1.75rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0 0 0.25rem;
    letter-spacing: -0.02em;
  }

  .hub-sub {
    font-size: 0.875rem;
    color: var(--color-muted);
    margin: 0;
  }

  .hub-grid {
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
  }

  .hub-card {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 1rem 1.125rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
    position: relative;
    overflow: hidden;
  }

  .hub-card:not(.soon):active {
    transform: scale(0.98);
    opacity: 0.85;
  }

  .hub-card.soon {
    opacity: 0.5;
    cursor: default;
  }

  .hub-symbol {
    width: 2.5rem;
    height: 2.5rem;
    background: var(--color-bg);
    border-radius: 0.75rem;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.125rem;
    color: var(--color-accent);
    flex-shrink: 0;
    border: 1px solid var(--color-border);
  }

  .hub-text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .hub-name {
    font-size: 1rem;
    font-weight: 500;
    color: var(--color-text);
    font-family: "Fraunces", serif;
    letter-spacing: -0.01em;
  }

  .hub-desc {
    font-size: 0.8125rem;
    color: var(--color-muted);
  }

  .hub-arrow {
    font-size: 1.25rem;
    color: var(--color-border);
    line-height: 1;
  }

  .soon-badge {
    font-size: 0.6875rem;
    color: var(--color-muted);
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.5rem;
    padding: 0.125rem 0.5rem;
    white-space: nowrap;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
</style>
