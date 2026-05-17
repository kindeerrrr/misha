<script lang="ts">
  import { signInWithPassword, signInWithMagicLink } from '../stores/user'
  import { avatar, avatarSrc } from '../stores/avatar'

  let email = 'daryabelogaj24@icloud.com'
  let password = ''
  let mode: 'password' | 'magic' = 'password'
  let sent = false
  let loading = false
  let error = ''

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
          <input
            id="password"
            type="password"
            bind:value={password}
            placeholder="••••••••"
            autocomplete="current-password"
            required
          />
        {/if}
        {#if error}
          <p class="error-msg">{error}</p>
        {/if}
        <button type="submit" class="btn-primary mt-4" disabled={loading}>
          {loading ? 'Вхожу...' : mode === 'password' ? 'Войти' : 'Отправить ссылку'}
        </button>
        <button type="button" class="mode-toggle" on:click={() => { mode = mode === 'password' ? 'magic' : 'password'; error = '' }}>
          {mode === 'password' ? 'Войти без пароля (ссылка на почту)' : 'Войти по паролю'}
        </button>
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

  .error-msg {
    font-size: 0.8125rem;
    color: var(--color-danger);
    margin: 0;
  }

  .mode-toggle {
    background: none;
    border: none;
    color: var(--color-accent);
    font-size: 0.8125rem;
    cursor: pointer;
    padding: 0.25rem 0;
    text-align: center;
    -webkit-tap-highlight-color: transparent;
  }

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

  button:disabled {
    opacity: 0.6;
  }
</style>
