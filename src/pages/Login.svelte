<script lang="ts">
  import { signInWithMagicLink } from '../stores/user'

  let email = 'daryabelogaj24@icloud.com'
  let sent = false
  let loading = false
  let error = ''

  async function handleSubmit() {
    loading = true
    error = ''
    const { error: err } = await signInWithMagicLink(email)
    loading = false
    if (err) {
      error = err.message
    } else {
      sent = true
    }
  }
</script>

<div class="login-page">
  <div class="login-inner">
    <div class="brand">
      <div class="logo">M</div>
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
        {#if error}
          <p class="error-msg">{error}</p>
        {/if}
        <button type="submit" class="btn-primary mt-4" disabled={loading}>
          {loading ? 'Отправляю...' : 'Войти без пароля'}
        </button>
        <p class="login-hint">Пришлём ссылку на почту — нажмёшь и войдёшь</p>
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
    background-color: var(--color-accent);
    color: white;
    font-family: "Fraunces", serif;
    font-size: 2rem;
    font-weight: 300;
    display: flex;
    align-items: center;
    justify-content: center;
    margin: 0 auto 1rem;
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

  .login-hint {
    text-align: center;
    font-size: 0.75rem;
    color: var(--color-muted);
    margin: 0.5rem 0 0;
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
