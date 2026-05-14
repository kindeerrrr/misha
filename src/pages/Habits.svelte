<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import Modal from '../components/ui/Modal.svelte'
  import type { Habit, HabitLog } from '../lib/types'

  let habits: Habit[] = []
  let logs: HabitLog[] = []       // logs for selectedDate (for isDone check)
  let allLogs: HabitLog[] = []    // logs for the selected week
  let loading = true
  let showAddModal = false

  const todayDate = today()
  let selectedDate = todayDate
  let weekOffset = 0  // 0 = current week, -1 = last week, etc.

  const DAY_LABELS = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']

  type WeekCell = { date: string; num: number; label: string }

  function buildWeekCells(offset: number): WeekCell[] {
    const now = new Date()
    const dow = now.getDay()
    const diff = dow === 0 ? 6 : dow - 1
    return DAY_LABELS.map((label, i) => {
      const d = new Date(now)
      d.setDate(now.getDate() - diff + i + offset * 7)
      const date = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`
      return { date, num: d.getDate(), label }
    })
  }

  let weekCells: WeekCell[] = buildWeekCells(0)
  let weekStart = weekCells[0].date
  let weekEnd = weekCells[6].date

  $: {
    weekCells = buildWeekCells(weekOffset)
    weekStart = weekCells[0].date
    weekEnd = weekCells[6].date
  }

  $: weekLabel = (() => {
    if (!weekCells.length) return ''
    const s = weekCells[0]; const e = weekCells[6]
    const sd = new Date(s.date + 'T12:00:00'); const ed = new Date(e.date + 'T12:00:00')
    const sm = sd.toLocaleDateString('ru', { month: 'short' })
    const em = ed.toLocaleDateString('ru', { month: 'short' })
    return sd.getMonth() === ed.getMonth()
      ? `${s.num}–${e.num} ${em}`
      : `${s.num} ${sm} – ${e.num} ${em}`
  })()

  let newName = ''
  let saving = false
  const COLORS = ['#c084fc','#fb923c','#34d399','#60a5fa','#f472b6','#a3e635','#fbbf24','#94a3b8']
  let newColor = COLORS[0]

  // Edit habit
  let editingHabit: Habit | null = null
  let editName = ''
  let editColor = COLORS[0]

  function openEdit(habit: Habit) {
    editingHabit = habit
    editName = habit.name
    editColor = habit.color ?? COLORS[0]
  }

  async function saveEdit() {
    if (!editingHabit || !editName.trim()) return
    saving = true
    const { data } = await supabase.from('habits')
      .update({ name: editName.trim(), color: editColor })
      .eq('id', editingHabit.id)
      .select().single()
    if (data) habits = habits.map(h => h.id === data.id ? data : h)
    editingHabit = null
    saving = false
  }

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

  async function loadWeekLogs(start: string, end: string) {
    if (!$user) return
    const res = await supabase.from('habit_logs').select('*').eq('user_id', $user.id).gte('date', start).lte('date', end)
    allLogs = res.data ?? []
  }

  async function load() {
    await Promise.all([loadHabits(), loadLogs(selectedDate), loadWeekLogs(weekCells[0].date, weekCells[6].date)])
    loading = false
  }

  $: if (!loading && selectedDate) loadLogs(selectedDate)
  $: if (!loading) loadWeekLogs(weekStart, weekEnd)

  function selectDay(date: string) {
    selectedDate = date
  }

  function isDone(habit: Habit) {
    return logs.some(l => l.habit_id === habit.id)
  }

  function hasLog(habit: Habit, date: string) {
    return allLogs.some(l => l.habit_id === habit.id && l.date === date)
  }

  const togglingHabits = new Set<string>()

  async function toggleForDate(habit: Habit, date: string) {
    if (!$user) return
    const key = `${habit.id}:${date}`
    if (togglingHabits.has(key)) return
    togglingHabits.add(key)
    const existing = allLogs.find(l => l.habit_id === habit.id && l.date === date)
    // Optimistic update — apply immediately, rollback on error
    const tempId = `temp-${Date.now()}`
    if (existing) {
      allLogs = allLogs.filter(l => l.id !== existing.id)
      if (date === selectedDate) logs = logs.filter(l => l.id !== existing.id)
    } else {
      const tempLog = { id: tempId, habit_id: habit.id, user_id: $user.id, date, created_at: new Date().toISOString() } as HabitLog
      allLogs = [...allLogs, tempLog]
      if (date === selectedDate) logs = [...logs, tempLog]
    }
    try {
      if (existing) {
        const { error } = await supabase.from('habit_logs').delete().eq('id', existing.id)
        if (error) {
          allLogs = [...allLogs, existing]
          if (date === selectedDate) logs = [...logs, existing]
        }
      } else {
        const { data, error } = await supabase.from('habit_logs').insert({
          user_id: $user.id,
          habit_id: habit.id,
          date: date,
        }).select().single()
        if (error || !data) {
          allLogs = allLogs.filter(l => l.id !== tempId)
          if (date === selectedDate) logs = logs.filter(l => l.id !== tempId)
        } else {
          allLogs = allLogs.map(l => l.id === tempId ? data : l)
          if (date === selectedDate) logs = logs.map(l => l.id === tempId ? data : l)
        }
      }
    } catch {
      // rollback already handled above
    } finally {
      togglingHabits.delete(key)
    }
  }

  async function toggle(habit: Habit) {
    await toggleForDate(habit, selectedDate)
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

  onMount(load)
</script>

<div class="page-shell">
  <header class="page-header">
    <h1 class="section-title">Привычки</h1>
    <button class="add-btn" on:click={() => showAddModal = true}>+ Добавить</button>
  </header>

  <!-- Week nav -->
  <div class="week-nav">
    <button class="week-arrow" on:click={() => weekOffset -= 1}>←</button>
    <span class="week-label">{weekLabel}</span>
    <button class="week-arrow" class:disabled={weekOffset >= 0} on:click={() => { if (weekOffset < 0) weekOffset += 1 }}>→</button>
  </div>

  <!-- Day strip -->
  <div class="day-strip">
    {#each weekCells as cell}
      <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
      <div
        class="day-cell"
        class:selected={cell.date === selectedDate}
        class:is-today={cell.date === todayDate}
        class:future={cell.date > todayDate}
        on:click={() => cell.date <= todayDate && selectDay(cell.date)}
      >
        <span class="day-label-text">{cell.label}</span>
        <span class="day-num">{cell.num}</span>
      </div>
    {/each}
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
              <div class="hero-bar-fill" style="width:{habits.length ? Math.round(doneCount() / habits.length * 100) : 0}%" />
            </div>
            <span class="hero-pct">{habits.length ? Math.round(doneCount() / habits.length * 100) : 0}%</span>
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
              <button class="edit-btn" on:click|stopPropagation={() => openEdit(habit)}>✎</button>
              <button class="archive-btn" on:click|stopPropagation={() => archive(habit)}>×</button>
            </div>
            <div class="streak-dots">
              {#each weekCells as cell}
                <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
                <div
                  class="streak-dot"
                  class:filled={hasLog(habit, cell.date)}
                  class:is-today={cell.date === selectedDate}
                  class:future-dot={cell.date > todayDate}
                  style="--dot-color:{habit.color ?? 'var(--color-accent)'}"
                  on:click|stopPropagation={() => cell.date <= todayDate && toggleForDate(habit, cell.date)}
                />
              {/each}
            </div>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<Modal title="Редактировать" open={!!editingHabit} on:close={() => editingHabit = null}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="edit-habit-name">Название</label>
      <input id="edit-habit-name" type="text" bind:value={editName} />
    </div>
    <div class="form-field">
      <label class="label">Цвет</label>
      <div class="color-row">
        {#each COLORS as c}
          <button
            class="color-dot"
            class:selected={editColor === c}
            style="background:{c}"
            on:click={() => editColor = c}
          />
        {/each}
      </div>
    </div>
    <button class="btn-primary" on:click={saveEdit} disabled={saving || !editName.trim()}>
      {saving ? 'Сохраняю...' : 'Сохранить'}
    </button>
    <button class="btn-ghost" style="margin-top:-0.5rem" on:click={() => { if(editingHabit) archive(editingHabit); editingHabit = null }}>
      Удалить привычку
    </button>
  </div>
</Modal>

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
  .page-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 1rem 0 0.75rem;
  }

  .add-btn {
    background: var(--color-accent); color: white; border: none;
    border-radius: 0.875rem; padding: 0.5rem 1rem; font-size: 0.9375rem;
    cursor: pointer; -webkit-tap-highlight-color: transparent;
  }

  /* Week navigation */
  .week-nav {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 1rem;
    margin-bottom: 0.75rem;
  }

  .week-arrow {
    background: none;
    border: 1px solid var(--color-border);
    border-radius: 0.625rem;
    width: 2rem;
    height: 2rem;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1rem;
    color: var(--color-accent);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
    flex-shrink: 0;
  }
  .week-arrow.disabled { opacity: 0.3; cursor: default; }

  .week-label {
    font-size: 0.9375rem;
    color: var(--color-text);
    font-family: "Fraunces", serif;
    font-weight: 300;
    min-width: 8rem;
    text-align: center;
  }

  /* Day strip */
  .day-strip {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    gap: 0.25rem;
    margin-bottom: 1rem;
  }

  .day-cell {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 0.375rem 0.125rem;
    border-radius: 0.625rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: background 0.15s;
  }
  .day-cell.future { opacity: 0.35; cursor: default; }
  .day-cell.selected {
    background: var(--color-accent);
  }
  .day-cell.is-today:not(.selected) {
    background: var(--color-card);
    border: 1px solid var(--color-accent);
  }

  .day-label-text {
    font-size: 0.625rem;
    color: var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .day-cell.selected .day-label-text { color: rgba(255,255,255,0.8); }

  .day-num {
    font-family: "JetBrains Mono", monospace;
    font-size: 0.875rem;
    color: var(--color-text);
    line-height: 1;
    font-weight: 500;
  }
  .day-cell.selected .day-num { color: white; }
  .day-cell.is-today:not(.selected) .day-num { color: var(--color-accent); }

  /* Hero */
  .hero-stats { display: flex; align-items: center; }
  .hero-bar-wrap { display: flex; align-items: center; gap: 0.5rem; width: 100%; margin-top: 2px; }
  .hero-bar { flex: 1; height: 5px; background: var(--color-border); border-radius: 3px; overflow: hidden; }
  .hero-bar-fill { height: 100%; background: var(--color-accent); border-radius: 3px; transition: width 0.4s; }
  .hero-pct { font-family: "JetBrains Mono", monospace; font-size: 0.75rem; color: var(--color-muted); white-space: nowrap; }

  /* Habits */
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

  .edit-btn {
    background: none; border: none; color: var(--color-muted);
    font-size: 1rem; cursor: pointer; padding: 0 0.25rem; line-height: 1;
    opacity: 0.5;
  }
  .habit-row.done .edit-btn { color: white; opacity: 0.6; }

  .archive-btn {
    background: none; border: none; color: var(--color-muted);
    font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1;
    opacity: 0.5;
  }
  .habit-row.done .archive-btn { color: white; opacity: 0.6; }

  .streak-dots { display: flex; gap: 0.25rem; }

  .streak-dot {
    width: 1.125rem;
    height: 1.125rem;
    border-radius: 50%;
    background: var(--color-border);
    cursor: pointer;
    flex-shrink: 0;
    transition: background 0.15s, transform 0.1s;
    -webkit-tap-highlight-color: transparent;
  }
  .streak-dot:active { transform: scale(0.85); }
  .streak-dot.filled { background: var(--dot-color); }
  .streak-dot.is-today { outline: 2px solid var(--dot-color); outline-offset: 1px; }

  .future-dot { opacity: 0.2; cursor: default; }

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
