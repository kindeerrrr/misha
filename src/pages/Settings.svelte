<script lang="ts">
  import PageShell from '../components/layout/PageShell.svelte'
  import Card from '../components/ui/Card.svelte'
  import { theme } from '../stores/theme'
  import { signOut } from '../stores/user'
  import { user } from '../stores/user'
  import type { Theme } from '../lib/types'

  const THEMES: { id: Theme; label: string; bg: string; accent: string }[] = [
    { id: 'light',  label: 'Светлая', bg: '#FFFFFF',  accent: '#007AFF' },
    { id: 'dark',   label: 'Тёмная',  bg: '#1C1C1E',  accent: '#0A84FF' },
    { id: 'latte',  label: 'Латте',   bg: '#FAF5EE',  accent: '#B85A3E' },
    { id: 'sage',   label: 'Шалфей',  bg: '#F4F1EA',  accent: '#6D8F70' },
  ]

  async function handleSignOut() {
    await signOut()
  }
</script>

<PageShell title="Настройки">
  <div class="settings-list">

    <section>
      <p class="label mb-2">Тема</p>
      <div class="theme-grid">
        {#each THEMES as t}
          <button
            class="theme-card"
            class:active={$theme === t.id}
            on:click={() => theme.set(t.id)}
          >
            <div class="theme-preview" style="background:{t.bg}">
              <div class="theme-accent-dot" style="background:{t.accent}" />
            </div>
            <span class="theme-label">{t.label}</span>
          </button>
        {/each}
      </div>
    </section>

    <section class="mt-4">
      <p class="label mb-2">Аккаунт</p>
      <Card>
        <div class="account-row">
          <span class="account-email">{$user?.email ?? '—'}</span>
        </div>
      </Card>
    </section>

    <section class="mt-6">
      <button class="btn-ghost" on:click={handleSignOut}>
        Выйти
      </button>
    </section>

    <p class="version-label">misha v0.1 · made with love</p>
  </div>
</PageShell>

<style>
  .settings-list {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .theme-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.625rem;
  }

  .theme-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
    padding: 0.75rem;
    background: var(--color-card);
    border: 1.5px solid var(--color-border);
    border-radius: 1rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }
  .theme-card.active {
    border-color: var(--color-accent);
    box-shadow: 0 0 0 1px var(--color-accent);
  }
  .theme-card:active { transform: scale(0.97); }

  .theme-preview {
    width: 100%;
    height: 3.5rem;
    border-radius: 0.625rem;
    border: 1px solid rgba(0,0,0,0.08);
    display: flex;
    align-items: flex-end;
    justify-content: flex-end;
    padding: 0.375rem;
  }

  .theme-accent-dot {
    width: 1rem;
    height: 1rem;
    border-radius: 50%;
  }

  .theme-label {
    font-size: 0.8125rem;
    color: var(--color-text);
  }
  .theme-card.active .theme-label {
    color: var(--color-accent);
    font-weight: 500;
  }

  .account-row {
    display: flex;
    align-items: center;
  }

  .account-email {
    font-size: 0.9375rem;
    color: var(--color-text);
  }

  .version-label {
    text-align: center;
    font-size: 0.75rem;
    color: var(--color-muted);
    margin-top: 2rem;
  }

  .mt-4 { margin-top: 1rem; }
  .mt-6 { margin-top: 1.5rem; }
  .mb-2 { margin-bottom: 0.5rem; }
</style>
