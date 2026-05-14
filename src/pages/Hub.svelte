<script lang="ts">
  import { navigate } from '../stores/nav'
  import { icons } from '../lib/icons'
  import type { NavTab } from '../lib/types'

  type Section = { id: NavTab; title: string; sub: string; icon: string; soon?: boolean }

  const sections: Section[] = [
    { id: 'dashboard', title: 'Главная',     sub: 'Дашборд дня',               icon: icons.home },
    { id: 'health',    title: 'Здоровье',    sub: 'Таблетки, сон, тренировки', icon: icons.heart },
    { id: 'emotions',  title: 'День',        sub: 'Настроение и итоги',         icon: icons.sun },
    { id: 'finances',  title: 'Деньги',      sub: 'Расходы и доходы',           icon: icons.wallet },
    { id: 'habits',    title: 'Привычки',    sub: 'Ежедневный трекер',          icon: icons.check_circle },
    { id: 'media',     title: 'Медиа',       sub: 'Книги, фильмы, сериалы',     icon: icons.book },
    { id: 'cat',       title: 'Животные',    sub: 'Питомцы, уход, здоровье',    icon: icons.paw },
    { id: 'settings',  title: 'Настройки',   sub: 'Тема и параметры',           icon: icons.settings },
    { id: 'dashboard', title: 'Путешествия', sub: 'Поездки и маршруты',         icon: icons.map_pin, soon: true },
    { id: 'dashboard', title: 'Кредиты',     sub: 'Долги и платежи',            icon: icons.credit_card, soon: true },
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
        {#if s.soon}
          <span class="soon-badge">Скоро</span>
        {/if}
        <div class="hub-symbol">{@html s.icon}</div>
        <div class="hub-text">
          <span class="hub-name">{s.title}</span>
          <span class="hub-desc">{s.sub}</span>
        </div>
      </div>
    {/each}
  </div>
</div>

<style>
  .hub-header { padding: 1.5rem 0 1.25rem; }

  .hub-title {
    font-family: "Fraunces", serif;
    font-size: 1.75rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0 0 0.25rem;
    letter-spacing: -0.02em;
  }

  .hub-sub { font-size: 0.875rem; color: var(--color-muted); margin: 0; }

  .hub-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.625rem;
  }

  .hub-card {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    padding: 1rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
    position: relative;
    overflow: hidden;
    min-height: 6.5rem;
  }

  .hub-card:not(.soon):active { transform: scale(0.97); opacity: 0.85; }
  .hub-card.soon { opacity: 0.45; cursor: default; }

  .hub-symbol {
    width: 2rem;
    height: 2rem;
    background: var(--color-bg);
    border-radius: 0.625rem;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--color-accent);
    flex-shrink: 0;
    border: 1px solid var(--color-border);
    padding: 0.375rem;
  }

  .hub-symbol :global(svg) { width: 100%; height: 100%; }

  .hub-text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin-top: auto;
  }

  .hub-name {
    font-size: 0.9375rem;
    font-weight: 500;
    color: var(--color-text);
    font-family: "Fraunces", serif;
    letter-spacing: -0.01em;
  }

  .hub-desc { font-size: 0.6875rem; color: var(--color-muted); line-height: 1.3; }

  .soon-badge {
    position: absolute;
    top: 0.5rem;
    right: 0.5rem;
    font-size: 0.5rem;
    color: var(--color-muted);
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.375rem;
    padding: 0.125rem 0.375rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
</style>
