<script lang="ts">
  import PageShell from '../components/layout/PageShell.svelte'
  import Card from '../components/ui/Card.svelte'
  import { theme } from '../stores/theme'
  import { avatar, avatarSrc } from '../stores/avatar'
  import { signOut } from '../stores/user'
  import { user } from '../stores/user'
  import { profile, updateProfile } from '../stores/profile'
  import { showToast } from '../stores/toast'
  import type { Theme, AvatarVariant } from '../lib/types'

  let editingName = false
  let nameInput = ''

  function startEditName() {
    nameInput = $profile?.display_name ?? ''
    editingName = true
  }

  async function saveName() {
    const { error } = await updateProfile({ display_name: nameInput.trim() })
    if (error) showToast('Ошибка сохранения', 'error')
    else { showToast('Имя сохранено', 'success'); editingName = false }
  }

  async function forceUpdate() {
    if ('serviceWorker' in navigator) {
      const reg = await navigator.serviceWorker.getRegistration()
      await reg?.update()
    }
    showToast('Обновляю...', 'info', 1000)
    setTimeout(() => window.location.reload(), 1000)
  }

  const THEMES: { id: Theme; label: string; bg: string; accent: string }[] = [
    { id: 'light',  label: 'Светлая', bg: '#FFFFFF',  accent: '#007AFF' },
    { id: 'dark',   label: 'Тёмная',  bg: '#1C1C1E',  accent: '#0A84FF' },
    { id: 'latte',  label: 'Латте',   bg: '#FAF5EE',  accent: '#B85A3E' },
    { id: 'sage',   label: 'Шалфей',  bg: '#F4F1EA',  accent: '#6D8F70' },
  ]

  const AVATARS: { id: AvatarVariant; label: string }[] = [
    { id: 'sage', label: 'Sage' },
    { id: 'pink', label: 'Pink' },
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
      <p class="label mb-2">Аватар</p>
      <div class="avatar-grid">
        {#each AVATARS as av}
          <button
            class="avatar-card"
            class:active={$avatar === av.id}
            on:click={() => avatar.set(av.id)}
          >
            <img
              src={avatarSrc(av.id)}
              alt={av.label}
              class="avatar-img"
            />
            <span class="avatar-label">{av.label}</span>
          </button>
        {/each}
      </div>
    </section>

    <section class="mt-4">
      <p class="label mb-2">Аккаунт</p>
      <Card>
        <div class="account-col">
          <span class="account-email">{$user?.email ?? '—'}</span>
          {#if editingName}
            <div class="name-edit-row">
              <input
                class="name-input"
                bind:value={nameInput}
                placeholder="Твоё имя"
                on:keydown={e => { if (e.key === 'Enter') saveName() }}
              />
              <button class="name-save-btn" on:click={saveName}>Сохранить</button>
              <button class="name-cancel-btn" on:click={() => editingName = false}>Отмена</button>
            </div>
          {:else}
            <button class="name-btn" on:click={startEditName}>
              {$profile?.display_name ? $profile.display_name : '+ Добавить имя'}
            </button>
          {/if}
        </div>
      </Card>
    </section>

    <section class="mt-4">
      <p class="label mb-2">Приложение</p>
      <Card>
        <button class="update-btn" on:click={forceUpdate}>
          Обновить приложение
          <span class="update-hint">принудительно загрузить новую версию</span>
        </button>
      </Card>
    </section>

    <section class="mt-4">
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

  /* Avatar */
  .avatar-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.625rem;
  }

  .avatar-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
    padding: 0.875rem 0.75rem;
    background: var(--color-card);
    border: 1.5px solid var(--color-border);
    border-radius: 1rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }
  .avatar-card.active {
    border-color: var(--color-accent);
    box-shadow: 0 0 0 1px var(--color-accent);
  }
  .avatar-card:active { transform: scale(0.97); }

  .avatar-img {
    width: 4rem;
    height: 4rem;
    border-radius: 1rem;
    object-fit: cover;
  }

  .avatar-label {
    font-size: 0.8125rem;
    color: var(--color-text);
  }
  .avatar-card.active .avatar-label {
    color: var(--color-accent);
    font-weight: 500;
  }

  .account-col {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .account-email {
    font-size: 0.8125rem;
    color: var(--color-muted);
  }

  .name-btn {
    background: none; border: none; padding: 0;
    font-size: 0.9375rem; color: var(--color-accent);
    cursor: pointer; text-align: left;
    -webkit-tap-highlight-color: transparent;
  }

  .name-edit-row {
    display: flex; gap: 0.5rem; align-items: center; flex-wrap: wrap;
  }

  .name-input {
    flex: 1; min-width: 0;
    font-size: 0.9375rem;
    padding: 0.375rem 0.625rem;
    border-radius: 0.5rem;
  }

  .name-save-btn {
    background: var(--color-accent); color: white; border: none;
    border-radius: 0.5rem; padding: 0.375rem 0.75rem;
    font-size: 0.8125rem; cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }

  .name-cancel-btn {
    background: none; border: none; color: var(--color-muted);
    font-size: 0.8125rem; cursor: pointer; padding: 0.375rem 0;
    -webkit-tap-highlight-color: transparent;
  }

  .update-btn {
    background: none; border: none; cursor: pointer; width: 100%;
    text-align: left; padding: 0; display: flex; flex-direction: column; gap: 2px;
    -webkit-tap-highlight-color: transparent;
    font-size: 0.9375rem; color: var(--color-text);
  }
  .update-btn:active { opacity: 0.6; }
  .update-hint { font-size: 0.75rem; color: var(--color-muted); }

  .version-label {
    text-align: center;
    font-size: 0.75rem;
    color: var(--color-muted);
    margin-top: 2rem;
  }

  .mt-4 { margin-top: 1rem; }
  .mb-2 { margin-bottom: 0.5rem; }
</style>
