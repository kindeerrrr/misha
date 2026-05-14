<script lang="ts">
  import PageShell from '../components/layout/PageShell.svelte'
  import Card from '../components/ui/Card.svelte'
  import { theme } from '../stores/theme'
  import { signOut } from '../stores/user'
  import { user } from '../stores/user'

  async function handleSignOut() {
    await signOut()
  }
</script>

<PageShell title="Настройки">
  <div class="settings-list">

    <section>
      <p class="label mb-2">Тема</p>
      <Card>
        <div class="theme-row">
          <div class="theme-preview" class:active={$theme === 'latte'}>
            <div class="swatch latte" />
            <span>Латте</span>
          </div>
          <button
            class="theme-toggle"
            on:click={() => theme.toggle()}
            aria-label="Переключить тему"
          >
            <div class="toggle-track" class:sage={$theme === 'sage'}>
              <div class="toggle-thumb" />
            </div>
          </button>
          <div class="theme-preview" class:active={$theme === 'sage'}>
            <div class="swatch sage" />
            <span>Шалфей</span>
          </div>
        </div>
      </Card>
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

    <p class="version-label">misha v0.1 · made with ♡</p>
  </div>
</PageShell>

<style>
  .settings-list {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .theme-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  .theme-preview {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.375rem;
    font-size: 0.8125rem;
    color: var(--color-muted);
    transition: color 0.15s;
  }

  .theme-preview.active {
    color: var(--color-text);
    font-weight: 400;
  }

  .swatch {
    width: 2.5rem;
    height: 2.5rem;
    border-radius: 0.75rem;
    border: 2px solid var(--color-border);
  }

  .swatch.latte { background: linear-gradient(135deg, #FAF5EE 50%, #B85A3E 50%); }
  .swatch.sage  { background: linear-gradient(135deg, #F4F1EA 50%, #6D8F70 50%); }

  .theme-toggle {
    background: none;
    border: none;
    cursor: pointer;
    padding: 0.25rem;
  }

  .toggle-track {
    width: 3rem;
    height: 1.75rem;
    background-color: var(--color-accent);
    border-radius: 1rem;
    position: relative;
    transition: background-color 0.2s;
  }

  .toggle-track.sage {
    background-color: #6D8F70;
  }

  .toggle-thumb {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 1.25rem;
    height: 1.25rem;
    background: white;
    border-radius: 50%;
    transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
  }

  .toggle-track.sage .toggle-thumb {
    transform: translateX(1.25rem);
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
</style>
