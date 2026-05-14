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
  import Habits from './pages/Habits.svelte'
  import Media from './pages/Media.svelte'
  import Cat from './pages/Cat.svelte'
  import Settings from './pages/Settings.svelte'
  import Hub from './pages/Hub.svelte'
  import Travel from './pages/Travel.svelte'
  import Toast from './components/ui/Toast.svelte'
  import type { NavTab } from './lib/types'

  // Mount each tab once on first visit, then keep it alive (hidden)
  let visited: Partial<Record<NavTab, true>> = {}
  $: if ($user && $activeTab) visited = { ...visited, [$activeTab]: true }
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
    <div class:hidden={$activeTab !== 'dashboard'}>{#if visited['dashboard']}<Dashboard />{/if}</div>
    <div class:hidden={$activeTab !== 'health'}>{#if visited['health']}<Health />{/if}</div>
    <div class:hidden={$activeTab !== 'emotions'}>{#if visited['emotions']}<Emotions />{/if}</div>
    <div class:hidden={$activeTab !== 'finances'}>{#if visited['finances']}<Finances />{/if}</div>
    <div class:hidden={$activeTab !== 'habits'}>{#if visited['habits']}<Habits />{/if}</div>
    <div class:hidden={$activeTab !== 'media'}>{#if visited['media']}<Media />{/if}</div>
    <div class:hidden={$activeTab !== 'cat'}>{#if visited['cat']}<Cat />{/if}</div>
    <div class:hidden={$activeTab !== 'settings'}>{#if visited['settings']}<Settings />{/if}</div>
    <div class:hidden={$activeTab !== 'hub'}>{#if visited['hub']}<Hub />{/if}</div>
    <div class:hidden={$activeTab !== 'travel'}>{#if visited['travel']}<Travel />{/if}</div>
  </div>
  <BottomNav />
  <Toast />
{/if}

<style>
  .app-shell {
    min-height: 100dvh;
    background-color: var(--color-bg);
  }

  .hidden {
    display: none;
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
