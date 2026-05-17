<script lang="ts">
  import { signInWithPassword, signInWithMagicLink } from '../stores/user'
  import { avatar, avatarSrc } from '../stores/avatar'
  import { updateProfile } from '../stores/profile'
  import { supabase } from '../lib/supabase'

  type Mode = 'password' | 'magic' | 'register'

  let email = ''
  let password = ''
  let displayName = ''
  let mode: Mode = 'password'
  let sent = false
  let loading = false
  let error = ''
  let showPassword = false
  let resetSent = false
  let resetLoading = false

  async function handleSubmit() {
    loading = true
    error = ''

    if (mode === 'register') {
      const { data, error: err } = await supabase.auth.signUp({ email, password })
      if (err) { error = err.message; loading = false; return }
      if (displayName.trim() && data.user) {
        await updateProfile({ display_name: displayName.trim() })
      }
      loading = false
      return
    }

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

  function switchMode(m: Mode) {
    mode = m
    error = ''
    showPassword = false
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
        <button class="link-btn mt-3" on:click={() => { resetSent = false }}>Назад</button>
      </div>
    {:else}
      <form on:submit|preventDefault={handleSubmit} class="login-form">

        {#if mode === 'register'}
          <p class="form-heading">Создать аккаунт</p>
          <label class="label" for="dname">Как тебя зовут?</label>
          <input
            id="dname"
            type="text"
            bind:value={displayName}
            placeholder="Даша"
            autocomplete="name"
          />
        {/if}

        <label class="label" for="email">Email</label>
        <input
          id="email"
          type="email"
          bind:value={email}
          placeholder="твой@email.com"
          autocomplete="email"
          required
        />

        {#if mode === 'password' || mode === 'register'}
          <label class="label" for="password">Пароль</label>
          <div class="password-wrap">
            <input
              id="password"
              type={showPassword ? 'text' : 'password'}
              bind:value={password}
              placeholder="••••••••"
              autocomplete={mode === 'register' ? 'new-password' : 'current-password'}
              required
            />
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
          {#if loading}
            {mode === 'register' ? 'Создаю...' : 'Вхожу...'}
          {:else if mode === 'register'}
            Создать аккаунт
          {:else if mode === 'password'}
            Войти
          {:else}
            Отправить ссылку
          {/if}
        </button>

        <div class="links-row">
          {#if mode === 'password'}
            <button type="button" class="link-btn" on:click={handleReset} disabled={resetLoading}>
              {resetLoading ? 'Отправляю...' : 'Забыла пароль?'}
            </button>
          {/if}
          {#if mode === 'register'}
            <button type="button" class="link-btn" on:click={() => switchMode('password')}>
              Уже есть аккаунт
            </button>
          {:else}
            <button type="button" class="link-btn" on:click={() => switchMode('register')}>
              Создать аккаунт
            </button>
          {/if}
          {#if mode !== 'register'}
            <button type="button" class="link-btn" on:click={() => switchMode(mode === 'password' ? 'magic' : 'password')}>
              {mode === 'password' ? 'Войти без пароля' : 'Войти по паролю'}
            </button>
          {/if}
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

  .form-heading {
    font-family: "Fraunces", serif;
    font-size: 1.25rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0 0 0.25rem;
    letter-spacing: -0.01em;
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
    flex-wrap: wrap;
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

  button:disabled { opacity: 0.6; }
</style>
