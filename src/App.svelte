<script lang="ts">
  import { user, authLoading } from './stores/user'
  import { activeTab } from './stores/nav'
  import BottomNav from './components/layout/BottomNav.svelte'
  import OfflineBanner from './components/ui/OfflineBanner.svelte'
  import Login from './pages/Login.svelte'
  import Dashboard from './pages/Dashboard.svelte'
  import Health from './pages/health/Health.svelte'
  import Emotions from './pages/Emotions.svelte'
  import Finances from './pages/Finances.svelte'
  import Settings from './pages/Settings.svelte'
</script>

{#if $authLoading}
  <div class="splash">
    <div class="splash-logo">M</div>
  </div>
{:else if !$user}
  <Login />
{:else}
  <OfflineBanner />
  <div class="app-shell">
    {#if $activeTab === 'dashboard'}
      <Dashboard />
    {:else if $activeTab === 'health'}
      <Health />
    {:else if $activeTab === 'emotions'}
      <Emotions />
    {:else if $activeTab === 'finances'}
      <Finances />
    {:else if $activeTab === 'settings'}
      <Settings />
    {/if}
  </div>
  <BottomNav />
{/if}

<style>
  .app-shell {
    min-height: 100dvh;
    background-color: var(--color-bg);
  }

  .splash {
    min-height: 100dvh;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: var(--color-bg);
  }

  .splash-logo {
    width: 5rem;
    height: 5rem;
    border-radius: 1.5rem;
    background-color: var(--color-accent);
    color: white;
    font-family: "Fraunces", serif;
    font-size: 2.5rem;
    font-weight: 300;
    display: flex;
    align-items: center;
    justify-content: center;
    animation: pulse 1.5s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }
</style>
