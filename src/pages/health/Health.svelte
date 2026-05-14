<script lang="ts">
  import { onMount } from 'svelte'
  import { activeHealthTab } from '../../stores/nav'
  import { supabase, today } from '../../lib/supabase'
  import { user } from '../../stores/user'
  import { icons } from '../../lib/icons'
  import Pills from './Pills.svelte'
  import Sleep from './Sleep.svelte'
  import Measurements from './Measurements.svelte'
  import Workouts from './Workouts.svelte'
  import Doctors from './Doctors.svelte'
  import Research from './Research.svelte'
  import Checkups from './Checkups.svelte'
  import type { HealthTab } from '../../lib/types'

  type Section = { id: HealthTab; title: string; sub: string; icon: string }

  const sections: Section[] = [
    { id: 'pills',        title: 'Таблетки',      sub: 'Препараты и приём',    icon: icons.pill },
    { id: 'sleep',        title: 'Сон',            sub: 'Качество и история',   icon: icons.moon },
    { id: 'measurements', title: 'Замеры',         sub: 'Вес, объёмы, состав', icon: icons.ruler },
    { id: 'workouts',     title: 'Тренировки',     sub: 'Активность и нагрузки',icon: icons.activity },
    { id: 'doctors',      title: 'Врачи',          sub: 'Визиты и процедуры',   icon: icons.stethoscope },
    { id: 'research',     title: 'Исследования',   sub: 'УЗИ, МРТ, анализы',   icon: icons.flask },
    { id: 'checkups',     title: 'Осмотры',        sub: 'Плановые проверки',    icon: icons.calendar_check },
  ]

  const todayDate = today()

  let pillsTaken = 0
  let pillsTotal = 0
  let lastSleepMinutes: number | null = null
  let nextCheckup: string | null = null
  let loadingStats = true

  async function loadStats() {
    if (!$user) return
    const uid = $user.id
    const [medsRes, logsRes, sleepRes, checkupRes] = await Promise.all([
      supabase.from('medications').select('id').eq('user_id', uid).eq('status', 'active'),
      supabase.from('medication_logs').select('id').eq('user_id', uid).eq('date', todayDate).eq('skipped', false),
      supabase.from('sleep_logs').select('duration_minutes').eq('user_id', uid).order('date', { ascending: false }).limit(1).maybeSingle(),
      supabase.from('annual_checkups').select('name,next_due_at').eq('user_id', uid).not('next_due_at', 'is', null).order('next_due_at').limit(1).maybeSingle(),
    ])
    pillsTotal = (medsRes.data ?? []).length
    pillsTaken = (logsRes.data ?? []).length
    lastSleepMinutes = sleepRes.data?.duration_minutes ?? null
    if (checkupRes.data?.next_due_at) {
      const d = new Date(checkupRes.data.next_due_at)
      nextCheckup = `${checkupRes.data.name} · ${d.toLocaleDateString('ru', { day: 'numeric', month: 'short' })}`
    }
    loadingStats = false
  }

  function formatSleep(mins: number | null): string {
    if (!mins) return '—'
    return `${Math.floor(mins / 60)}ч ${mins % 60 > 0 ? (mins % 60) + 'м' : ''}`.trim()
  }

  onMount(loadStats)
</script>

{#if $activeHealthTab === 'hub'}
  <div class="page-shell">
    <header class="page-header">
      <h1 class="section-title">Здоровье</h1>
    </header>

    <!-- Key stats -->
    {#if !loadingStats}
      <div class="hero-card mb-4">
        <div class="hero-stats">
          <div class="stat-block">
            <span class="stat-label">Таблетки</span>
            <span class="stat-value">{pillsTaken}<span class="stat-denom">/{pillsTotal}</span></span>
          </div>
          <div class="stat-sep" />
          <div class="stat-block">
            <span class="stat-label">Сон</span>
            <span class="stat-value" style="font-size:1.25rem">{formatSleep(lastSleepMinutes)}</span>
          </div>
          {#if nextCheckup}
            <div class="stat-sep" />
            <div class="stat-block" style="flex:2;align-items:flex-start;padding-left:0.5rem">
              <span class="stat-label">Следующий осмотр</span>
              <span class="next-checkup">{nextCheckup}</span>
            </div>
          {/if}
        </div>
      </div>
    {/if}

    <!-- Section grid -->
    <div class="health-grid">
      {#each sections as s}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="health-card" on:click={() => activeHealthTab.set(s.id)}>
          <div class="health-symbol">{@html s.icon}</div>
          <div class="health-text">
            <span class="health-name">{s.title}</span>
            <span class="health-desc">{s.sub}</span>
          </div>
        </div>
      {/each}
    </div>
  </div>

{:else}
  <!-- Sub-page with back button -->
  <div class="page-shell">
    <header class="sub-header">
      <button class="back-btn" on:click={() => activeHealthTab.set('hub')}>←</button>
      <h1 class="section-title">{sections.find(s => s.id === $activeHealthTab)?.title ?? ''}</h1>
    </header>

    <div class="sub-content">
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
{/if}

<style>
  .page-header {
    display: flex;
    align-items: center;
    padding: 1rem 0 0.75rem;
  }

  .sub-header {
    display: flex;
    align-items: center;
    gap: 0.875rem;
    padding: 1rem 0 0.875rem;
  }

  .back-btn {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    width: 2.25rem;
    height: 2.25rem;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1rem;
    color: var(--color-accent);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    flex-shrink: 0;
  }

  .health-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.625rem;
  }

  .health-card {
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
    padding: 1rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
    min-height: 6rem;
    position: relative;
  }

  .health-card:active { transform: scale(0.97); opacity: 0.85; }

  .health-symbol {
    width: 2rem;
    height: 2rem;
    background: var(--color-bg);
    border-radius: 0.625rem;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--color-accent);
    flex-shrink: 0;
    border: 1px solid var(--color-border);
    padding: 0.375rem;
  }

  .health-symbol :global(svg) { width: 100%; height: 100%; }

  .health-text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin-top: auto;
  }

  .health-name {
    font-size: 0.9375rem;
    font-weight: 500;
    color: var(--color-text);
    font-family: "Fraunces", serif;
    letter-spacing: -0.01em;
  }

  .health-desc { font-size: 0.6875rem; color: var(--color-muted); line-height: 1.3; }

  .hero-stats { display: flex; align-items: center; }

  .next-checkup {
    font-size: 0.8125rem;
    color: var(--color-text);
    line-height: 1.3;
  }

  .sub-content { padding-bottom: 2rem; }

  .mb-4 { margin-bottom: 1rem; }
</style>
