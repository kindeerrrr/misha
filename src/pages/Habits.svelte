<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import DateNav from '../components/ui/DateNav.svelte'
  import Modal from '../components/ui/Modal.svelte'
  import type { Habit, HabitLog } from '../lib/types'

  let habits: Habit[] = []
  let logs: HabitLog[] = []       // logs for selectedDate (toggling)
  let allLogs: HabitLog[] = []    // logs for last 7 days (streaks)
  let loading = true
  let showAddModal = false

  const todayDate = today()
  let selectedDate = todayDate

  const weekDates: string[] = Array.from({ length: 7 }, (_, i) => {
    const d = new Date()
    d.setDate(d.getDate() - (6 - i))
    return d.toISOString().slice(0, 10)
  })
  const weekStart = weekDates[0]

  let newName = ''
  let saving = false

  const COLORS = ['#c084fc','#fb923c','#34d399','#60a5fa','#f472b6','#a3e635','#fbbf24','#94a3b8']
  let newColor = COLORS[0]

  async function loadHabits() {
    if (!$user) return
    const res = await supabase.from('habits').select('*').eq('user_id', $user.id).eq('archived', false).order('sort_order')
    habits = res.data ?? []
  }

  async function loadLogs(date: string) {
    if (!$user) return
    const res = await supabase.from('habit_logs').select('*').eq('user_id', $user.id).eq('date', date)
    logs = res.data ?? []
  }

  async function loadStreakLogs() {
    if (!$user) return
    const res = await supabase.from('habit_logs').select('*').eq('user_id', $user.id).gte('date', weekStart).lte('date', todayDate)
    allLogs = res.data ?? []
  }

  async function load() {
    await Promise.all([loadHabits(), loadLogs(selectedDate), loadStreakLogs()])
    loading = false
  }

  $: if (selectedDate) loadLogs(selectedDate)

  function isDone(habit: Habit) {
    return logs.some(l => l.habit_id === habit.id)
  }

  function hasLog(habit: Habit, date: string) {
    return allLogs.some(l => l.habit_id === habit.id && l.date === date)
  }

  async function toggle(habit: Habit) {
    if (!$user) return
    const existing = logs.find(l => l.habit_id === habit.id)
    if (existing) {
      await supabase.from('habit_logs').delete().eq('id', existing.id)
      logs = logs.filter(l => l.id !== existing.id)
      allLogs = allLogs.filter(l => l.id !== existing.id)
    } else {
      const { data } = await supabase.from('habit_logs').insert({
        user_id: $user.id,
        habit_id: habit.id,
        date: selectedDate,
      }).select().single()
      if (data) {
        logs = [...logs, data]
        allLogs = [...allLogs, data]
      }
    }
  }

  async function addHabit() {
    if (!$user || !newName.trim()) return
    saving = true
    const { data } = await supabase.from('habits').insert({
      user_id: $user.id,
      name: newName.trim(),
      color: newColor,
      sort_order: habits.length,
      archived: false,
    }).select().single()
    if (data) habits = [...habits, data]
    showAddModal = false
    newName = ''; newColor = COLORS[0]
    saving = false
  }

  async function archive(habit: Habit) {
    await supabase.from('habits').update({ archived: true }).eq('id', habit.id)
    habits = habits.filter(h => h.id !== habit.id)
  }

  function doneCount() { return logs.length }

  function streakCount(habit: Habit): number {
    let count = 0
    for (let i = weekDates.length - 1; i >= 0; i--) {
      if (hasLog(habit, weekDates[i])) count++
      else break
    }
    return count
  }

  onMount(load)
</script>

<div class="page-shell">
  <header class="page-header">
    <h1 class="section-title">Привычки</h1>
    <button class="add-btn" on:click={() => showAddModal = true}>+ Добавить</button>
  </header>

  <div class="date-row">
    <DateNav date={selectedDate} on:change={e => selectedDate = e.detail} />
  </div>

  {#if !loading && habits.length > 0}
    <div class="hero-card mb-4">
      <div class="hero-stats">
        <div class="stat-block">
          <span class="stat-label">Выполнено</span>
          <span class="stat-value">{doneCount()}<span class="stat-denom">/{habits.length}</span></span>
        </div>
        <div class="stat-sep" />
        <div class="stat-block" style="flex:2; align-items:flex-start; padding-left:1rem">
          <span class="stat-label">Прогресс</span>
          <div class="hero-bar-wrap">
            <div class="hero-bar">
              <div class="hero-bar-fill" style="width:{Math.round(doneCount() / habits.length * 100)}%" />
            </div>
            <span class="hero-pct">{Math.round(doneCount() / habits.length * 100)}%</span>
          </div>
        </div>
      </div>
    </div>
  {/if}

  {#if loading}
    <div class="skeleton mt-4" style="height:10rem" />
  {:else if habits.length === 0}
    <div class="empty-state mt-4">Добавь первую привычку →</div>
  {:else}
    <div class="habit-list">
      {#each habits as habit}
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div
          class="habit-row"
          class:done={isDone(habit)}
          on:click={() => toggle(habit)}
          style="--habit-color:{habit.color ?? 'var(--color-accent)'}"
        >
          <div class="habit-main">
            <div class="habit-top">
              <div class="habit-check">{isDone(habit) ? '✓' : ''}</div>
              <span class="habit-name">{habit.name}</span>
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <button class="archive-btn" on:click|stopPropagation={() => archive(habit)}>×</button>
            </div>
            <div class="streak-dots">
              {#each weekDates as d}
                <div
                  class="streak-dot"
                  class:filled={hasLog(habit, d)}
                  class:is-today={d === todayDate}
                  style="--dot-color:{habit.color ?? 'var(--color-accent)'}"
                />
              {/each}
              {#if streakCount(habit) > 0}
                <span class="streak-label">{streakCount(habit)}д подряд</span>
              {/if}
            </div>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<Modal title="Новая привычка" open={showAddModal} on:close={() => { showAddModal = false; newName = '' }}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="habit-name">Название</label>
      <input id="habit-name" type="text" bind:value={newName} placeholder="Например, Выпить воду" />
    </div>
    <div class="form-field">
      <label class="label">Цвет</label>
      <div class="color-row">
        {#each COLORS as c}
          <button
            class="color-dot"
            class:selected={newColor === c}
            style="background:{c}"
            on:click={() => newColor = c}
          />
        {/each}
      </div>
    </div>
    <button class="btn-primary" on:click={addHabit} disabled={saving || !newName.trim()}>
      {saving ? 'Сохраняю...' : 'Добавить'}
    </button>
  </div>
</Modal>

<style>
  .page-shell { max-width: 480px; margin: 0 auto; padding: 0 1rem 6rem; }

  .page-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 1rem 0 0.75rem;
  }

  .add-btn {
    background: var(--color-accent); color: white; border: none;
    border-radius: 0.875rem; padding: 0.5rem 1rem; font-size: 0.9375rem;
    cursor: pointer;
  }

  .date-row { display: flex; justify-content: center; margin-bottom: 0.875rem; }

  .hero-stats { display: flex; align-items: center; }

  .hero-bar-wrap { display: flex; align-items: center; gap: 0.5rem; width: 100%; margin-top: 2px; }
  .hero-bar { flex: 1; height: 5px; background: var(--color-border); border-radius: 3px; overflow: hidden; }
  .hero-bar-fill { height: 100%; background: var(--color-accent); border-radius: 3px; transition: width 0.4s; }
  .hero-pct { font-family: "JetBrains Mono", monospace; font-size: 0.75rem; color: var(--color-muted); white-space: nowrap; }

  .habit-list { display: flex; flex-direction: column; gap: 0.5rem; }

  .habit-row {
    padding: 0.875rem 1rem;
    background: var(--color-card); border: 1.5px solid var(--color-border);
    border-radius: 1rem; cursor: pointer;
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .habit-row:active { transform: scale(0.98); }
  .habit-row.done {
    background: var(--habit-color);
    border-color: var(--habit-color);
    color: white;
  }

  .habit-main { display: flex; flex-direction: column; gap: 0.5rem; }
  .habit-top { display: flex; align-items: center; gap: 0.875rem; }

  .habit-check {
    width: 1.5rem; height: 1.5rem; border-radius: 50%;
    border: 1.5px solid var(--color-border);
    display: flex; align-items: center; justify-content: center;
    font-size: 0.875rem; flex-shrink: 0;
  }
  .habit-row.done .habit-check { border-color: rgba(255,255,255,0.5); color: white; }

  .habit-name { flex: 1; font-size: 0.9375rem; }

  .archive-btn {
    background: none; border: none; color: var(--color-muted);
    font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1;
    opacity: 0.5;
  }
  .habit-row.done .archive-btn { color: white; opacity: 0.6; }

  .streak-label {
    font-size: 0.6875rem;
    color: var(--color-muted);
    margin-left: 0.25rem;
    white-space: nowrap;
  }
  .habit-row.done .streak-label { color: rgba(255,255,255,0.7); }

  .color-row { display: flex; gap: 0.5rem; flex-wrap: wrap; }
  .color-dot {
    width: 2rem; height: 2rem; border-radius: 50%; border: 3px solid transparent;
    cursor: pointer; -webkit-tap-highlight-color: transparent; transition: transform 0.1s;
  }
  .color-dot.selected { border-color: var(--color-text); transform: scale(1.15); }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mb-4 { margin-bottom: 1rem; }
  .mt-4 { margin-top: 1rem; }
</style>
