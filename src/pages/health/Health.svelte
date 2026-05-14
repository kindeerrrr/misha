<script lang="ts">
  import { activeHealthTab } from '../../stores/nav'
  import Pills from './Pills.svelte'
  import Sleep from './Sleep.svelte'
  import Measurements from './Measurements.svelte'
  import Workouts from './Workouts.svelte'
  import Doctors from './Doctors.svelte'
  import Research from './Research.svelte'
  import Checkups from './Checkups.svelte'

  const tabs = [
    { id: 'pills',        title: 'Таблетки' },
    { id: 'sleep',        title: 'Сон' },
    { id: 'measurements', title: 'Замеры' },
    { id: 'workouts',     title: 'Тренировки' },
    { id: 'doctors',      title: 'Врачи' },
    { id: 'research',     title: 'Исследования' },
    { id: 'checkups',     title: 'Осмотры' },
  ] as const
</script>

<div class="health-page">
  <!-- Scrollable sub-tabs -->
  <nav class="health-tabs" aria-label="Подразделы здоровья">
    {#each tabs as tab}
      <button
        class="health-tab"
        class:active={$activeHealthTab === tab.id}
        on:click={() => activeHealthTab.set(tab.id)}
        aria-label={tab.title}
      >
        <span class="tab-text">{tab.title}</span>
      </button>
    {/each}
  </nav>

  <div class="health-content">
    {#if $activeHealthTab === 'pills'}
      <Pills />
    {:else if $activeHealthTab === 'sleep'}
      <Sleep />
    {:else if $activeHealthTab === 'measurements'}
      <Measurements />
    {:else if $activeHealthTab === 'workouts'}
      <Workouts />
    {:else if $activeHealthTab === 'doctors'}
      <Doctors />
    {:else if $activeHealthTab === 'research'}
      <Research />
    {:else if $activeHealthTab === 'checkups'}
      <Checkups />
    {/if}
  </div>
</div>

<style>
  .health-page {
    max-width: 480px;
    margin: 0 auto;
    min-height: 100dvh;
  }

  .health-tabs {
    display: flex;
    overflow-x: auto;
    gap: 0.375rem;
    padding: 0.875rem 1rem 0;
    scrollbar-width: none;
    -webkit-overflow-scrolling: touch;
  }

  .health-tabs::-webkit-scrollbar { display: none; }

  .health-tab {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 3px;
    padding: 0.5rem 0.75rem;
    border-radius: 1rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    cursor: pointer;
    white-space: nowrap;
    flex-shrink: 0;
    -webkit-tap-highlight-color: transparent;
    transition: background-color 0.15s, border-color 0.15s;
  }

  .health-tab.active {
    background-color: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  .health-tab:active:not(.active) {
    background-color: var(--color-card-hover);
  }

  .tab-emoji { font-size: 1rem; line-height: 1; }
  .tab-text { font-size: 0.6875rem; line-height: 1; }

  .health-content {
    padding: 0.75rem 1rem 6rem;
  }
</style>
