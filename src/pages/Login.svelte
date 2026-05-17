<script lang="ts">
  import { signInWithPassword, signInWithMagicLink } from '../stores/user'
  import { avatar, avatarSrc } from '../stores/avatar'
  import { supabase } from '../lib/supabase'

  let email = 'daryabelogaj24@icloud.com'
  let password = ''
  let mode: 'password' | 'magic' = 'password'
  let sent = false
  let loading = false
  let error = ''
  let showPassword = false
  let resetSent = false
  let resetLoading = false

  async function handleSubmit() {
    loading = true
    error = ''
    if (mode === 'password') {
      const { error: err } = await signInWithPassword(email, password)
      loading = false
      if (err) error = err.message
    } else {
      const { error: err } = await signInWithMagicLink(email)
      loading = false
      if (err) error = err.message
      else sent = true
    }
  }

  async function handleReset() {
    if (!email) { error = 'Введи email'; return }
    resetLoading = true
    error = ''
    const { error: err } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/`,
    })
    resetLoading = false
    if (err) error = err.message
    else resetSent = true
  }
</script>

<div class="login-page">
  <div class="login-inner">
    <div class="brand">
      <img src={avatarSrc($avatar)} alt="misha" class="logo" />
      <h1 class="app-name">misha</h1>
      <p class="app-tagline">личный трекер жизни</p>
    </div>

    {#if sent}
      <div class="sent-card card">
        <div class="sent-icon">✉</div>
        <p class="sent-title">Ссылка отправлена</p>
        <p class="sent-body">Проверь {email} — придёт письмо с волшебной ссылкой. Открой её на этом устройстве.</p>
      </div>
    {:else if resetSent}
      <div class="sent-card card">
        <div class="sent-icon">🔑</div>
        <p class="sent-title">Письмо отправлено</p>
        <p class="sent-body">Проверь {email} — придёт ссылка для сброса пароля.</p>
        <button class="mode-toggle mt-3" on:click={() => resetSent = false}>Назад</button>
      </div>
    {:else}
      <form on:submit|preventDefault={handleSubmit} class="login-form">
        <label class="label" for="email">Email</label>
        <input
          id="email"
          type="email"
          bind:value={email}
          placeholder="твой@email.com"
          autocomplete="email"
          required
        />
        {#if mode === 'password'}
          <label class="label" for="password">Пароль</label>
          <div class="password-wrap">
            {#if showPassword}
              <input
                id="password"
                type="text"
                bind:value={password}
                placeholder="••••••••"
                autocomplete="current-password"
                required
              />
            {:else}
              <input
                id="password"
                type="password"
                bind:value={password}
                placeholder="••••••••"
                autocomplete="current-password"
                required
              />
            {/if}
            <button
              type="button"
              class="eye-btn"
              on:click={() => showPassword = !showPassword}
              aria-label={showPassword ? 'Скрыть пароль' : 'Показать пароль'}
            >
              {#if showPassword}
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94"/>
                  <path d="M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19"/>
                  <line x1="1" y1="1" x2="23" y2="23"/>
                </svg>
              {:else}
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
                  <circle cx="12" cy="12" r="3"/>
                </svg>
              {/if}
            </button>
          </div>
        {/if}
        {#if error}
          <p class="error-msg">{error}</p>
        {/if}
        <button type="submit" class="btn-primary mt-4" disabled={loading}>
          {loading ? 'Вхожу...' : mode === 'password' ? 'Войти' : 'Отправить ссылку'}
        </button>

        <div class="links-row">
          {#if mode === 'password'}
            <button type="button" class="link-btn" on:click={handleReset} disabled={resetLoading}>
              {resetLoading ? 'Отправляю...' : 'Забыла пароль?'}
            </button>
          {/if}
          <button type="button" class="link-btn" on:click={() => { mode = mode === 'password' ? 'magic' : 'password'; error = '' }}>
            {mode === 'password' ? 'Войти без пароля' : 'Войти по паролю'}
          </button>
        </div>
      </form>
    {/if}
  </div>
</div>

<style>
  .login-page {
    min-height: 100dvh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 2rem 1.5rem;
    background-color: var(--color-bg);
  }

  .login-inner {
    width: 100%;
    max-width: 360px;
  }

  .brand {
    text-align: center;
    margin-bottom: 2.5rem;
  }

  .logo {
    width: 4rem;
    height: 4rem;
    border-radius: 1.25rem;
    display: block;
    margin: 0 auto 1rem;
    object-fit: cover;
  }

  .app-name {
    font-family: "Fraunces", serif;
    font-weight: 300;
    font-size: 2rem;
    letter-spacing: -0.02em;
    color: var(--color-text);
    margin: 0;
  }

  .app-tagline {
    font-size: 0.875rem;
    color: var(--color-muted);
    margin: 0.25rem 0 0;
  }

  .login-form {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .password-wrap {
    position: relative;
  }

  .password-wrap input {
    padding-right: 2.75rem;
  }

  .eye-btn {
    position: absolute;
    right: 0.75rem;
    top: 50%;
    transform: translateY(-50%);
    background: none;
    border: none;
    padding: 0;
    width: 1.25rem;
    height: 1.25rem;
    color: var(--color-muted);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    -webkit-tap-highlight-color: transparent;
  }
  .eye-btn svg { width: 100%; height: 100%; }
  .eye-btn:active { color: var(--color-accent); }

  .error-msg {
    font-size: 0.8125rem;
    color: var(--color-danger);
    margin: 0;
  }

  .links-row {
    display: flex;
    justify-content: space-between;
    gap: 0.5rem;
    margin-top: 0.25rem;
  }

  .link-btn {
    background: none;
    border: none;
    color: var(--color-accent);
    font-size: 0.8125rem;
    cursor: pointer;
    padding: 0.25rem 0;
    -webkit-tap-highlight-color: transparent;
    opacity: 1;
    transition: opacity 0.15s;
  }
  .link-btn:disabled { opacity: 0.5; cursor: default; }
  .link-btn:active { opacity: 0.6; }

  .sent-card {
    text-align: center;
    padding: 2rem 1.5rem;
  }

  .sent-icon {
    font-size: 2.5rem;
    margin-bottom: 0.75rem;
  }

  .sent-title {
    font-family: "Fraunces", serif;
    font-size: 1.25rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0 0 0.5rem;
  }

  .sent-body {
    font-size: 0.875rem;
    color: var(--color-muted);
    line-height: 1.5;
    margin: 0;
  }

  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 0.25rem; }

  button:disabled {
    opacity: 0.6;
  }
</style>
