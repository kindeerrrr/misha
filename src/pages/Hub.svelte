<script lang="ts">
  import { navigate } from '../stores/nav'
  import { icons } from '../lib/icons'

  type Section = { id: string; title: string; sub: string; icon: string }

  const daily: Section[]   = [
    { id: 'dashboard', title: 'Главная',   sub: 'Дашборд дня',          icon: icons.home },
    { id: 'emotions',  title: 'День',      sub: 'Настроение и итоги',    icon: icons.sun },
  ]
  const health: Section[]  = [
    { id: 'health',    title: 'Здоровье',  sub: 'Таблетки, сон, спорт', icon: icons.heart },
    { id: 'habits',    title: 'Привычки',  sub: 'Ежедневный трекер',     icon: icons.check_circle },
  ]
  const finance: Section[] = [
    { id: 'finances',  title: 'Деньги',    sub: 'Расходы и доходы',      icon: icons.wallet },
    { id: 'credits',   title: 'Кредиты',   sub: 'Долги и платежи',       icon: icons.credit_card },
  ]
  const leisure: Section[] = [
    { id: 'media',     title: 'Медиа',     sub: 'Книги, фильмы, сериалы', icon: icons.book },
    { id: 'travel',    title: 'Путешествия', sub: 'Поездки и маршруты',  icon: icons.plane },
  ]
</script>

<div class="page-shell">
  <header class="hub-header">
    <div>
      <h1 class="hub-title">Все разделы</h1>
      <p class="hub-sub">Быстрый доступ ко всему</p>
    </div>
    <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
    <div class="settings-btn" on:click={() => navigate('settings')} title="Настройки">
      {@html icons.settings}
    </div>
  </header>

  <div class="hub-section">
    <span class="hub-section-label">Ежедневное</span>
    <div class="hub-grid">
      {#each daily as s}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="hub-card" on:click={() => navigate(s.id)}>
          <div class="hub-symbol">{@html s.icon}</div>
          <div class="hub-text">
            <span class="hub-name">{s.title}</span>
            <span class="hub-desc">{s.sub}</span>
          </div>
        </div>
      {/each}
    </div>
  </div>

  <div class="hub-section">
    <span class="hub-section-label">Здоровье</span>
    <div class="hub-grid">
      {#each health as s}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="hub-card" on:click={() => navigate(s.id)}>
          <div class="hub-symbol">{@html s.icon}</div>
          <div class="hub-text">
            <span class="hub-name">{s.title}</span>
            <span class="hub-desc">{s.sub}</span>
          </div>
        </div>
      {/each}
    </div>
  </div>

  <div class="hub-section">
    <span class="hub-section-label">Финансы</span>
    <div class="hub-grid">
      {#each finance as s}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="hub-card" on:click={() => navigate(s.id)}>
          <div class="hub-symbol">{@html s.icon}</div>
          <div class="hub-text">
            <span class="hub-name">{s.title}</span>
            <span class="hub-desc">{s.sub}</span>
          </div>
        </div>
      {/each}
    </div>
  </div>

  <div class="hub-section">
    <span class="hub-section-label">Досуг</span>
    <div class="hub-grid">
      {#each leisure as s}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="hub-card" on:click={() => navigate(s.id)}>
          <div class="hub-symbol">{@html s.icon}</div>
          <div class="hub-text">
            <span class="hub-name">{s.title}</span>
            <span class="hub-desc">{s.sub}</span>
          </div>
        </div>
      {/each}
    </div>
  </div>

  <!-- Животные — во всю ширину -->
  <div class="hub-section">
    <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
    <div class="hub-card wide" on:click={() => navigate('cat')}>
      <div class="hub-symbol">{@html icons.paw}</div>
      <div class="hub-text">
        <span class="hub-name">Животные</span>
        <span class="hub-desc">Питомцы, уход, здоровье</span>
      </div>
    </div>
  </div>
</div>

<style>
  .page-shell {
    max-width: 480px;
    margin: 0 auto;
    padding: 0 1.375rem 6rem;
    min-height: 100dvh;
  }

  .hub-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1.5rem 0 1rem;
  }

  .hub-title {
    font-family: "Fraunces", serif;
    font-size: 1.75rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0 0 0.125rem;
    letter-spacing: -0.02em;
  }

  .hub-sub { font-size: 0.875rem; color: var(--color-muted); margin: 0; }

  .settings-btn {
    width: 2.25rem; height: 2.25rem;
    color: var(--color-muted);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    display: flex; align-items: center; justify-content: center;
    border-radius: 0.625rem;
    transition: color 0.15s;
  }
  .settings-btn:active { color: var(--color-accent); }
  .settings-btn :global(svg) { width: 1.375rem; height: 1.375rem; }

  /* ── Sections ── */
  .hub-section { margin-bottom: 1.25rem; }

  .hub-section-label {
    display: block;
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted);
    margin-bottom: 0.5rem;
    padding-left: 0.25rem;
  }

  .hub-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.625rem;
  }

  .hub-card {
    display: flex;
    flex-direction: row;
    align-items: center;
    gap: 0.75rem;
    padding: 0.875rem 1rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }
  .hub-card.wide { grid-column: 1 / -1; }
  .hub-card:active { transform: scale(0.97); opacity: 0.85; }

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
    min-width: 0;
  }

  .hub-name {
    font-size: 0.9375rem;
    font-weight: 500;
    color: var(--color-text);
    font-family: "Fraunces", serif;
    letter-spacing: -0.01em;
  }

  .hub-desc { font-size: 0.6875rem; color: var(--color-muted); line-height: 1.3; }
</style>
