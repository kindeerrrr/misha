<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import Modal from '../components/ui/Modal.svelte'
  import type { Expense, ExpenseCategory } from '../lib/types'

  let categories: ExpenseCategory[] = []
  let expenses: Expense[] = []
  let loading = true
  let showModal = false

  const todayDate = today()

  type Period = 'day' | 'week' | 'month'
  let period: Period = 'week'

  function periodStart(p: Period): string {
    const d = new Date()
    if (p === 'day') return todayDate
    if (p === 'week') {
      d.setDate(d.getDate() - 6)
    } else {
      d.setDate(1)
    }
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`
  }

  async function loadExpenses() {
    if (!$user) return
    const start = periodStart(period)
    const res = await supabase.from('expenses')
      .select('*, expense_categories(name, emoji, group_name)')
      .eq('user_id', $user.id)
      .gte('date', start)
      .order('date', { ascending: false })
      .order('created_at', { ascending: false })
    expenses = (res.data ?? []).map((e: Expense & { expense_categories?: ExpenseCategory }) => ({
      ...e, category: e.expense_categories
    }))
  }

  const weekAgo = periodStart('week')

  // Form
  let amount = ''
  let selCatId = ''
  let note = ''
  let expDate = todayDate
  let txType: 'expense' | 'income' | 'saving' = 'expense'
  let saving = false

  async function load() {
    if (!$user) return
    const [catRes] = await Promise.all([
      supabase.from('expense_categories').select('*').eq('user_id', $user.id).order('sort_order'),
    ])
    categories = catRes.data ?? []
    await loadExpenses()
    loading = false
  }

  $: if (!loading && period) loadExpenses()

  async function saveExpense() {
    if (!$user || !amount) return
    if (txType === 'expense' && !selCatId) return
    saving = true
    const { data } = await supabase.from('expenses').insert({
      user_id: $user.id,
      date: expDate,
      amount: parseFloat(amount),
      category_id: txType === 'expense' ? selCatId : null,
      note: note || null,
      tx_type: txType,
    }).select('*, expense_categories(name, emoji, group_name)').single()
    if (data) {
      const exp: Expense = { ...data, category: data.expense_categories }
      expenses = [exp, ...expenses]
    }
    showModal = false
    amount = ''; selCatId = ''; note = ''; expDate = todayDate; txType = 'expense'
    saving = false
  }

  async function deleteExpense(id: string) {
    if (!$user) return
    await supabase.from('expenses').delete().eq('id', id)
    expenses = expenses.filter(e => e.id !== id)
  }

  function quickCategories() {
    return categories.filter(c => c.is_quick).slice(0, 8)
  }

  function periodLabel(p: Period): string {
    if (p === 'day') return 'сегодня'
    if (p === 'week') return 'за 7 дней'
    return 'за месяц'
  }

  function totalExpenses() {
    return expenses.filter(e => !e.tx_type || e.tx_type === 'expense').reduce((s, e) => s + e.amount, 0)
  }

  function totalIncome() {
    return expenses.filter(e => e.tx_type === 'income').reduce((s, e) => s + e.amount, 0)
  }

  function totalSavings() {
    return expenses.filter(e => e.tx_type === 'saving').reduce((s, e) => s + e.amount, 0)
  }

  function groupByDate() {
    const groups: Record<string, Expense[]> = {}
    for (const e of expenses) {
      if (!groups[e.date]) groups[e.date] = []
      groups[e.date].push(e)
    }
    return Object.entries(groups)
  }

  function dateLabel(d: string) {
    if (d === todayDate) return 'Сегодня'
    const yesterday = new Date(); yesterday.setDate(yesterday.getDate() - 1)
    if (d === yesterday.toISOString().slice(0, 10)) return 'Вчера'
    return new Date(d).toLocaleDateString('ru', { weekday: 'short', day: 'numeric', month: 'short' })
  }

  function dayTotal(dayExpenses: Expense[]) {
    return dayExpenses.filter(e => !e.tx_type || e.tx_type === 'expense').reduce((s, e) => s + e.amount, 0)
  }

  function txIcon(type: string | undefined) {
    if (type === 'income') return '↑'
    if (type === 'saving') return '◆'
    return ''
  }

  function txColor(type: string | undefined) {
    if (type === 'income') return 'var(--color-success)'
    if (type === 'saving') return 'var(--color-accent2)'
    return 'var(--color-text)'
  }

  onMount(load)
</script>

<div class="page-shell">
  <header class="page-header">
    <h1 class="section-title">Финансы</h1>
    <button class="add-btn" on:click={() => showModal = true}>+ Запись</button>
  </header>

  <!-- Period selector -->
  <div class="period-tabs">
    <button class="period-tab" class:active={period === 'day'} on:click={() => period = 'day'}>День</button>
    <button class="period-tab" class:active={period === 'week'} on:click={() => period = 'week'}>Неделя</button>
    <button class="period-tab" class:active={period === 'month'} on:click={() => period = 'month'}>Месяц</button>
  </div>

  <!-- Summary -->
  <div class="summary-row">
    <div class="summary-card">
      <span class="label">Расходы · {periodLabel(period)}</span>
      <span class="summary-amount number-display">{totalExpenses().toLocaleString('ru')} ₽</span>
    </div>
    <div class="summary-card income">
      <span class="label">Доходы · {periodLabel(period)}</span>
      <span class="summary-amount number-display" style="color:var(--color-success)">{totalIncome().toLocaleString('ru')} ₽</span>
    </div>
  </div>
  {#if totalSavings() > 0}
    <div class="saving-row">
      <span class="label">Накопления · {periodLabel(period)}</span>
      <span class="number-display" style="color:var(--color-accent2)">{totalSavings().toLocaleString('ru')} ₽</span>
    </div>
  {/if}

  <!-- Quick categories -->
  {#if !loading && quickCategories().length > 0}
    <div class="quick-section mt-3">
      <p class="label mb-2">Быстрый расход</p>
      <div class="quick-grid">
        {#each quickCategories() as cat}
          <button
            class="quick-btn"
            on:click={() => { selCatId = cat.id; txType = 'expense'; showModal = true }}
          >
            {cat.name}
          </button>
        {/each}
        <button class="quick-btn other-btn" on:click={() => showModal = true}>Другое</button>
      </div>
    </div>
  {/if}

  <!-- List -->
  {#if loading}
    <div class="skeleton mt-4" style="height:8rem" />
  {:else if expenses.length === 0}
    <div class="empty-state mt-4">Запиши первую трату →</div>
  {:else}
    <div class="expense-groups mt-4">
      {#each groupByDate() as [date, dayExpenses]}
        <div class="day-group">
          <div class="day-header">
            <span class="label">{dateLabel(date)}</span>
            <span class="day-total number-display">{dayTotal(dayExpenses).toLocaleString('ru')} ₽</span>
          </div>
          {#each dayExpenses as exp}
            <div class="expense-row">
              {#if txIcon(exp.tx_type)}
                <span class="tx-icon" style="color:{txColor(exp.tx_type)}">{txIcon(exp.tx_type)}</span>
              {/if}
              <div class="exp-info">
                <span class="exp-cat" style="color:{txColor(exp.tx_type)}">
                  {exp.tx_type === 'income' ? 'Доход' : exp.tx_type === 'saving' ? 'Накопление' : (exp.category?.name ?? '—')}
                </span>
                {#if exp.note}<span class="exp-note">{exp.note}</span>{/if}
              </div>
              <span class="exp-amount number-display" style="color:{txColor(exp.tx_type)}">{exp.amount.toLocaleString('ru')} ₽</span>
              <button class="del-btn" on:click={() => deleteExpense(exp.id)}>×</button>
            </div>
          {/each}
        </div>
      {/each}
    </div>
  {/if}
</div>

<!-- Modal -->
<Modal title="Новая запись" open={showModal} on:close={() => { showModal = false; selCatId = '' }}>
  <div class="form-stack">
    <!-- Type selector -->
    <div class="type-tabs">
      <button class="type-tab" class:active={txType === 'expense'} on:click={() => txType = 'expense'}>Расход</button>
      <button class="type-tab" class:active={txType === 'income'} on:click={() => txType = 'income'}>Доход</button>
      <button class="type-tab" class:active={txType === 'saving'} on:click={() => txType = 'saving'}>Накопление</button>
    </div>

    <!-- Amount -->
    <div class="form-field">
      <label class="label" for="exp-amount">Сумма ₽</label>
      <input id="exp-amount" type="number" bind:value={amount} placeholder="0"
        inputmode="decimal" step="0.01" class="amount-input" />
    </div>

    <!-- Category (only for expenses) -->
    {#if txType === 'expense'}
      <div class="form-field">
        <label class="label">Категория</label>
        <div class="cat-grid">
          {#each categories as cat}
            <button
              class="cat-btn"
              class:selected={selCatId === cat.id}
              on:click={() => selCatId = cat.id}
            >{cat.name}</button>
          {/each}
        </div>
      </div>
    {/if}

    <!-- Note -->
    <div class="form-field">
      <label class="label" for="exp-note">Заметка</label>
      <input id="exp-note" type="text" bind:value={note} placeholder="Необязательно" />
    </div>

    <!-- Date -->
    <div class="form-field">
      <label class="label" for="exp-date">Дата</label>
      <input id="exp-date" type="date" bind:value={expDate} />
    </div>

    <button class="btn-primary"
      on:click={saveExpense}
      disabled={saving || !amount || (txType === 'expense' && !selCatId)}>
      {saving ? 'Сохраняю...' : 'Добавить'}
    </button>
  </div>
</Modal>

<style>
  .page-shell { max-width: 480px; margin: 0 auto; padding: 0 1.375rem 6rem; }

  .page-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 1rem 0 0.75rem;
  }

  .add-btn {
    background: var(--color-accent); color: white; border: none;
    border-radius: 0.875rem; padding: 0.5rem 1rem; font-size: 0.9375rem;
    cursor: pointer; transition: opacity 0.15s;
  }
  .add-btn:active { opacity: 0.8; }

  .period-tabs {
    display: flex;
    gap: 0.375rem;
    margin-bottom: 0.875rem;
  }

  .period-tab {
    flex: 1;
    padding: 0.5rem;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-card);
    color: var(--color-muted);
    font-size: 0.875rem;
    cursor: pointer;
    transition: all 0.15s;
    -webkit-tap-highlight-color: transparent;
  }

  .period-tab.active {
    background: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  .summary-row { display: grid; grid-template-columns: 1fr 1fr; gap: 0.625rem; }

  .summary-card {
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 1.125rem; padding: 0.875rem 1rem;
    display: flex; flex-direction: column; gap: 0.375rem;
  }

  .summary-amount { font-size: 1.25rem; color: var(--color-text); }

  .saving-row {
    display: flex; justify-content: space-between; align-items: center;
    padding: 0.625rem 0.875rem;
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 0.875rem; margin-top: 0.5rem;
    font-size: 0.9375rem;
  }

  .quick-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.375rem; }

  .quick-btn {
    padding: 0.625rem 0.5rem;
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 0.875rem; font-size: 0.8125rem; cursor: pointer;
    text-align: center; line-height: 1.3;
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
    color: var(--color-text);
  }
  .quick-btn:active { background: var(--color-card-hover); transform: scale(0.97); }
  .other-btn { color: var(--color-muted); }

  .expense-groups { display: flex; flex-direction: column; gap: 1.25rem; }
  .day-group { display: flex; flex-direction: column; gap: 0.375rem; }

  .day-header {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 0.25rem;
  }
  .day-total { font-size: 0.9375rem; color: var(--color-text); }

  .expense-row {
    display: flex; align-items: center; gap: 0.625rem;
    padding: 0.625rem 0.875rem;
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 0.875rem;
  }

  .exp-emoji { font-size: 1rem; }
  .tx-icon { font-size: 1rem; font-weight: 600; width: 1rem; text-align: center; }
  .exp-info { flex: 1; display: flex; flex-direction: column; gap: 1px; }
  .exp-cat { font-size: 0.9375rem; }
  .exp-note { font-size: 0.75rem; color: var(--color-muted); }
  .exp-amount { font-size: 0.9375rem; white-space: nowrap; }
  .del-btn { background: none; border: none; color: var(--color-muted); font-size: 1.25rem; cursor: pointer; padding: 0 0.25rem; line-height: 1; }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .type-tabs {
    display: flex; background: var(--color-card); border-radius: 0.875rem;
    padding: 0.25rem; gap: 0.25rem; border: 1px solid var(--color-border);
  }
  .type-tab {
    flex: 1; padding: 0.5rem; border: none; border-radius: 0.625rem;
    font-size: 0.875rem; background: none; color: var(--color-muted);
    cursor: pointer; transition: all 0.15s; -webkit-tap-highlight-color: transparent;
  }
  .type-tab.active { background: var(--color-accent); color: white; }

  .amount-input {
    font-family: "JetBrains Mono", monospace !important;
    font-size: 1.75rem !important; text-align: center; padding: 0.75rem !important;
  }

  .cat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.375rem; max-height: 14rem; overflow-y: auto; }
  .cat-btn {
    padding: 0.5rem 0.375rem; border: 1px solid var(--color-border);
    border-radius: 0.75rem; background: var(--color-card); cursor: pointer;
    font-size: 0.8125rem; text-align: center; line-height: 1.3;
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
    color: var(--color-text);
  }
  .cat-btn.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }

  .skeleton { border-radius: 1.25rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
  .mb-2 { margin-bottom: 0.5rem; }
</style>
