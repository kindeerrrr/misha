<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import Modal from '../components/ui/Modal.svelte'
  import { triggerFinanceModal } from '../stores/financeModal'
  import type { Expense, ExpenseCategory } from '../lib/types'

  // ── Period ────────────────────────────────────────────────────────────────
  type Period = 'day' | 'week' | 'month'
  let period: Period = 'day'
  let monthOffset = 0  // 0 = current month, -1 = last, etc.

  function toDateStr(d: Date): string {
    return d.toISOString().slice(0, 10)
  }

  function getPeriodRange(): { start: string; end: string } {
    const now = new Date()
    if (period === 'day') {
      const t = today()
      return { start: t, end: t }
    }
    if (period === 'week') {
      const start = new Date(now)
      start.setDate(start.getDate() - 6)
      return { start: toDateStr(start), end: today() }
    }
    const first = new Date(now.getFullYear(), now.getMonth() + monthOffset, 1)
    const last  = new Date(now.getFullYear(), now.getMonth() + monthOffset + 1, 0)
    return { start: toDateStr(first), end: toDateStr(last) }
  }

  function getMonthLabel(): string {
    const now = new Date()
    const d = new Date(now.getFullYear(), now.getMonth() + monthOffset, 1)
    if (monthOffset === 0) return 'Этот месяц'
    if (monthOffset === -1) return 'Прошлый месяц'
    return d.toLocaleDateString('ru', { month: 'long', year: 'numeric' })
  }

  function periodLabel(): string {
    if (period === 'day') return 'сегодня'
    if (period === 'week') return 'за 7 дней'
    return getMonthLabel().toLowerCase()
  }

  // ── Data ─────────────────────────────────────────────────────────────────
  let categories: ExpenseCategory[] = []
  let expenses: Expense[] = []
  let pastNames: Array<{ name: string; category_id: string | null }> = []
  let loading = true
  let listLoading = false

  async function loadCategories() {
    if (!$user) return
    const res = await supabase
      .from('expense_categories').select('*')
      .eq('user_id', $user.id).order('sort_order')
    categories = res.data ?? []
  }

  async function loadExpenses() {
    if (!$user) return
    listLoading = true
    const { start, end } = getPeriodRange()
    const res = await supabase
      .from('expenses')
      .select('*, expense_categories(name, emoji, group_name, applies_to)')
      .eq('user_id', $user.id)
      .gte('date', start)
      .lte('date', end)
      .order('date', { ascending: false })
      .order('created_at', { ascending: false })
    expenses = (res.data ?? []).map((e: Expense & { expense_categories?: ExpenseCategory }) => ({
      ...e, category: e.expense_categories,
    }))
    listLoading = false
  }

  async function loadPastNames() {
    if (!$user) return
    const res = await supabase
      .from('expenses')
      .select('name, category_id')
      .eq('user_id', $user.id)
      .not('name', 'is', null)
      .order('created_at', { ascending: false })
      .limit(400)
    if (res.data) {
      const seen = new Set<string>()
      pastNames = (res.data as Array<{ name: string | null; category_id: string | null }>)
        .filter(e => {
          if (!e.name) return false
          const k = e.name.toLowerCase()
          if (seen.has(k)) return false
          seen.add(k)
          return true
        })
        .map(e => ({ name: e.name as string, category_id: e.category_id }))
    }
  }

  // Track last loaded key to avoid double-load on mount
  let prevKey = ''

  async function load() {
    if (!$user) return
    loading = true
    await Promise.all([loadCategories(), loadExpenses(), loadPastNames()])
    prevKey = `${period}-${monthOffset}`
    loading = false
  }

  $: {
    const key = `${period}-${monthOffset}`
    if (!loading && key !== prevKey) {
      prevKey = key
      loadExpenses()
    }
  }

  // Trigger from dashboard "Трата" button
  $: if ($triggerFinanceModal) {
    openAdd()
    triggerFinanceModal.set(false)
  }

  onMount(load)

  // ── Derived ──────────────────────────────────────────────────────────────
  let searchQuery = ''
  let excludeCredit = false

  $: filteredExpenses = expenses.filter(e => {
    if (!searchQuery.trim()) return true
    const q = searchQuery.toLowerCase()
    return (
      (e.name  ?? '').toLowerCase().includes(q) ||
      (e.note  ?? '').toLowerCase().includes(q) ||
      (e.category?.name ?? '').toLowerCase().includes(q)
    )
  })

  $: baseForTotal = excludeCredit
    ? expenses.filter(e => e.payment_type !== 'installment')
    : expenses

  $: expenseTotal     = baseForTotal.filter(e => !e.tx_type || e.tx_type === 'expense').reduce((s, e) => s + Number(e.amount), 0)
  $: incomeTotal      = expenses.filter(e => e.tx_type === 'income').reduce((s, e) => s + Number(e.amount), 0)
  $: installmentTotal = expenses.filter(e => (e.tx_type === 'expense' || !e.tx_type) && e.payment_type === 'installment').reduce((s, e) => s + Number(e.amount), 0)

  function groupByDate(): Array<{ date: string; items: Expense[] }> {
    const m: Record<string, Expense[]> = {}
    for (const e of filteredExpenses) {
      if (!m[e.date]) m[e.date] = []
      m[e.date].push(e)
    }
    return Object.keys(m).map(d => ({ date: d, items: m[d] }))
  }

  const todayStr = today()

  function dateLabel(d: string): string {
    if (d === todayStr) return 'Сегодня'
    const yest = new Date()
    yest.setDate(yest.getDate() - 1)
    if (d === toDateStr(yest)) return 'Вчера'
    return new Date(d + 'T00:00:00').toLocaleDateString('ru', { weekday: 'short', day: 'numeric', month: 'short' })
  }

  function dayTotal(items: Expense[]): number {
    const base = excludeCredit ? items.filter(e => e.payment_type !== 'installment') : items
    return base.filter(e => !e.tx_type || e.tx_type === 'expense').reduce((s, e) => s + Number(e.amount), 0)
  }

  // ── Entry form ───────────────────────────────────────────────────────────
  let showModal  = false
  let showCatModal = false
  let editingId: string | null = null

  let formAmount      = ''
  let formName        = ''
  let formNote        = ''
  let formCatId       = ''
  let formDate        = today()
  let formTxType: 'expense' | 'income' | 'saving' = 'expense'
  let formPayType: 'regular' | 'installment' = 'regular'
  let formError       = ''
  let saving          = false

  // Category dropdown
  let catSearch    = ''
  let showCatDrop  = false

  $: formCats = categories.filter(c => {
    const a = c.applies_to ?? 'expense'
    if (formTxType === 'income') return a === 'income' || a === 'both'
    return a === 'expense' || a === 'both'
  })
  $: filteredFormCats = formCats.filter(c =>
    !catSearch || c.name.toLowerCase().includes(catSearch.toLowerCase())
  )
  $: selectedCat = categories.find(c => c.id === formCatId) ?? null

  // Name autocomplete
  let nameSuggs: typeof pastNames = []

  function onNameInput() {
    formError = ''
    const q = formName.trim().toLowerCase()
    nameSuggs = q.length >= 1
      ? pastNames.filter(n => n.name.toLowerCase().includes(q)).slice(0, 6)
      : []
  }

  function pickName(s: { name: string; category_id: string | null }) {
    formName  = s.name
    if (s.category_id && !formCatId) formCatId = s.category_id
    nameSuggs = []
  }

  function resetForm() {
    formAmount = ''; formName = ''; formNote = ''; formCatId = ''
    formDate   = today(); formTxType = 'expense'; formPayType = 'regular'
    formError  = ''; catSearch = ''; showCatDrop = false; nameSuggs = []
    editingId  = null
  }

  export function openAdd(prefillCatId = '') {
    resetForm()
    if (prefillCatId) formCatId = prefillCatId
    showModal = true
  }

  function openEdit(exp: Expense) {
    resetForm()
    editingId    = exp.id
    formAmount   = String(exp.amount)
    formName     = exp.name  ?? ''
    formNote     = exp.note  ?? ''
    formCatId    = exp.category_id ?? ''
    formDate     = exp.date
    formTxType   = (exp.tx_type  ?? 'expense') as typeof formTxType
    formPayType  = (exp.payment_type ?? 'regular') as typeof formPayType
    showModal    = true
  }

  function validate(): boolean {
    const n = parseFloat(formAmount)
    if (!formAmount.trim() || isNaN(n) || n <= 0) {
      formError = 'Укажи сумму'
      return false
    }
    if (formTxType !== 'saving' && !formCatId) {
      formError = 'Выбери категорию'
      return false
    }
    return true
  }

  async function saveEntry() {
    if (!$user || !validate()) return
    saving = true
    const payload = {
      user_id:      $user.id,
      date:         formDate,
      amount:       parseFloat(formAmount),
      category_id:  formTxType !== 'saving' ? (formCatId || null) : null,
      name:         formName.trim() || null,
      note:         formNote.trim() || null,
      tx_type:      formTxType,
      payment_type: formTxType === 'expense' ? formPayType : 'regular',
    }
    try {
      if (editingId) {
        const { data } = await supabase.from('expenses')
          .update(payload).eq('id', editingId).eq('user_id', $user.id)
          .select('*, expense_categories(name, emoji, group_name, applies_to)').single()
        if (data) {
          const exp: Expense = { ...data, category: data.expense_categories }
          expenses = expenses.map(e => e.id === editingId ? exp : e)
        }
      } else {
        const { data } = await supabase.from('expenses')
          .insert(payload)
          .select('*, expense_categories(name, emoji, group_name, applies_to)').single()
        if (data) {
          const exp: Expense = { ...data, category: data.expense_categories }
          const { start, end } = getPeriodRange()
          if (data.date >= start && data.date <= end) expenses = [exp, ...expenses]
          if (data.name) {
            const lc = (data.name as string).toLowerCase()
            pastNames = [
              { name: data.name as string, category_id: data.category_id as string | null },
              ...pastNames.filter(n => n.name.toLowerCase() !== lc),
            ]
          }
        }
      }
      showModal = false
      resetForm()
    } finally {
      saving = false
    }
  }

  async function deleteEntry(id: string) {
    if (!$user) return
    await supabase.from('expenses').delete().eq('id', id).eq('user_id', $user.id)
    expenses = expenses.filter(e => e.id !== id)
    showModal = false
    resetForm()
  }

  $: quickCats = categories
    .filter(c => c.is_quick && (c.applies_to === 'expense' || c.applies_to === 'both' || !c.applies_to))
    .slice(0, 8)

  // ── Category management ───────────────────────────────────────────────────
  let editingCatId: string | null = null
  let catFName = ''; let catFEmoji = ''; let catFGroup = ''
  let catFIsQuick = false
  let catFAppliesTo: 'expense' | 'income' | 'both' = 'expense'
  let catFSaving = false
  let catFilter: 'all' | 'expense' | 'income' = 'all'

  function startAddCat() {
    editingCatId = null
    catFName = ''; catFEmoji = ''; catFGroup = ''; catFIsQuick = false; catFAppliesTo = 'expense'
  }

  function startEditCat(cat: ExpenseCategory) {
    editingCatId = cat.id
    catFName     = cat.name
    catFEmoji    = cat.emoji  ?? ''
    catFGroup    = cat.group_name ?? ''
    catFIsQuick  = cat.is_quick
    catFAppliesTo = (cat.applies_to ?? 'expense') as typeof catFAppliesTo
  }

  $: visibleCats = catFilter === 'all' ? categories
    : categories.filter(c => {
        const a = c.applies_to ?? 'expense'
        if (catFilter === 'income') return a === 'income' || a === 'both'
        return a === 'expense' || a === 'both'
      })

  async function saveCat() {
    if (!$user || !catFName.trim()) return
    catFSaving = true
    const payload = {
      user_id:    $user.id,
      name:       catFName.trim(),
      emoji:      catFEmoji.trim() || null,
      group_name: catFGroup.trim() || 'Общее',
      is_quick:   catFIsQuick,
      applies_to: catFAppliesTo,
      sort_order: editingCatId
        ? (categories.find(c => c.id === editingCatId)?.sort_order ?? 99)
        : categories.length,
    }
    if (editingCatId) {
      const { data } = await supabase.from('expense_categories')
        .update(payload).eq('id', editingCatId).select().single()
      if (data) categories = categories.map(c => c.id === editingCatId ? data : c)
    } else {
      const { data } = await supabase.from('expense_categories').insert(payload).select().single()
      if (data) categories = [...categories, data]
    }
    catFSaving = false
    startAddCat()
  }

  async function deleteCat(id: string) {
    if (!$user) return
    await supabase.from('expense_categories').delete().eq('id', id).eq('user_id', $user.id)
    categories = categories.filter(c => c.id !== id)
    if (formCatId === id) formCatId = ''
  }
</script>

<div class="page-shell">
  <!-- Header -->
  <header class="page-header">
    <h1 class="section-title">Финансы</h1>
    <button class="add-btn" on:click={() => openAdd()}>+ Запись</button>
  </header>

  <!-- Period tabs -->
  <div class="period-tabs">
    <button class="period-tab" class:active={period === 'day'}
      on:click={() => { period = 'day'; monthOffset = 0 }}>День</button>
    <button class="period-tab" class:active={period === 'week'}
      on:click={() => { period = 'week'; monthOffset = 0 }}>Неделя</button>
    <button class="period-tab" class:active={period === 'month'}
      on:click={() => period = 'month'}>Месяц</button>
  </div>

  <!-- Month navigation -->
  {#if period === 'month'}
    <div class="month-nav">
      <button class="month-arrow" on:click={() => monthOffset--}>‹</button>
      <span class="month-label">{getMonthLabel()}</span>
      <button class="month-arrow" on:click={() => { if (monthOffset < 0) monthOffset++ }}
        disabled={monthOffset >= 0}>›</button>
    </div>
  {/if}

  <!-- Summary -->
  <div class="summary-grid">
    <div class="sum-card">
      <span class="sum-label">Расходы · {periodLabel()}</span>
      <span class="sum-amount exp-color">−{expenseTotal.toLocaleString('ru')} ₽</span>
    </div>
    <div class="sum-card">
      <span class="sum-label">Доходы · {periodLabel()}</span>
      <span class="sum-amount inc-color">+{incomeTotal.toLocaleString('ru')} ₽</span>
    </div>
  </div>

  <!-- Credit banner -->
  {#if installmentTotal > 0}
    <div class="credit-banner">
      <span class="credit-text">
        Из них в рассрочку: <strong>{installmentTotal.toLocaleString('ru')} ₽</strong>
      </span>
      <label class="toggle-wrap">
        <input type="checkbox" bind:checked={excludeCredit} />
        <span class="toggle-label">Не учитывать</span>
      </label>
    </div>
  {/if}

  <!-- Quick categories -->
  <div class="quick-section">
    <div class="quick-header">
      <span class="section-caption">Быстрый расход</span>
      <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
      <span class="icon-link" on:click={() => { showCatModal = true; startAddCat() }}
        role="button" tabindex="0">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="15" height="15">
          <circle cx="12" cy="12" r="3"/>
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>
        </svg>
      </span>
    </div>
    {#if quickCats.length > 0}
      <div class="quick-grid">
        {#each quickCats as cat}
          <button class="quick-btn" on:click={() => openAdd(cat.id)}>
            {cat.emoji ?? ''} {cat.name}
          </button>
        {/each}
        <button class="quick-btn other-btn" on:click={() => openAdd()}>Другое</button>
      </div>
    {:else if !loading}
      <button class="text-link" on:click={() => { showCatModal = true; startAddCat() }}>
        + Настроить категории
      </button>
    {/if}
  </div>

  <!-- Search -->
  <div class="search-row">
    <div class="search-wrap">
      <svg class="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" width="15" height="15">
        <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
      </svg>
      <input class="search-input" type="search" placeholder="Поиск по операциям…" bind:value={searchQuery} />
      {#if searchQuery}
        <button class="search-clear" on:click={() => searchQuery = ''}>×</button>
      {/if}
    </div>
  </div>

  <!-- List -->
  {#if loading || listLoading}
    <div class="skeleton-block" />
  {:else if filteredExpenses.length === 0}
    <div class="empty-state">
      {searchQuery ? 'Ничего не найдено' : 'Запиши первую трату →'}
    </div>
  {:else}
    <div class="expense-list">
      {#each groupByDate() as group}
        <div class="day-group">
          <div class="day-header">
            <span class="day-label">{dateLabel(group.date)}</span>
            {#if dayTotal(group.items) > 0}
              <span class="day-total">{dayTotal(group.items).toLocaleString('ru')} ₽</span>
            {/if}
          </div>
          <div class="day-card">
            {#each group.items as exp}
              <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
              <div class="exp-row" on:click={() => openEdit(exp)}>
                <div class="exp-info">
                  <span class="exp-primary">
                    {#if exp.tx_type === 'income'}Доход{:else if exp.tx_type === 'saving'}Накопление{:else}{exp.category?.name ?? '—'}{/if}
                    {#if exp.name}<span class="exp-name-dot"> · {exp.name}</span>{/if}
                  </span>
                  {#if exp.note}<span class="exp-note">{exp.note}</span>{/if}
                </div>
                <div class="exp-right">
                  <span class="exp-amount"
                    class:inc-color={exp.tx_type === 'income'}
                    class:sav-color={exp.tx_type === 'saving'}
                    class:exp-color={exp.tx_type === 'expense' || !exp.tx_type}>
                    {#if exp.tx_type === 'income'}+{:else if exp.tx_type !== 'saving'}−{/if}{Number(exp.amount).toLocaleString('ru')} ₽
                  </span>
                  {#if exp.payment_type === 'installment'}
                    <span class="badge-inst">рассрочка</span>
                  {/if}
                </div>
              </div>
            {/each}
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<!-- FAB -->
<button class="fab" on:click={() => openAdd()} aria-label="Добавить запись">+</button>

<!-- ── Entry modal ─────────────────────────────────────────────────────────── -->
<Modal title={editingId ? 'Редактировать' : 'Новая запись'} open={showModal}
  on:close={() => { showModal = false; resetForm() }}>
  <div class="mform">
    <!-- Type tabs -->
    <div class="type-tabs">
      <button class="type-tab" class:active={formTxType === 'expense'}
        on:click={() => { formTxType = 'expense'; formCatId = '' }}>Расход</button>
      <button class="type-tab" class:active={formTxType === 'income'}
        on:click={() => { formTxType = 'income'; formCatId = '' }}>Доход</button>
      <button class="type-tab" class:active={formTxType === 'saving'}
        on:click={() => { formTxType = 'saving'; formCatId = '' }}>Накопление</button>
    </div>

    <!-- Amount -->
    <div class="mf-field">
      <label class="mf-label" for="f-amount">Сумма ₽</label>
      <input id="f-amount" class="amount-input" type="number" inputmode="decimal" step="0.01"
        placeholder="0" bind:value={formAmount} on:input={() => formError = ''} />
    </div>

    <!-- Category dropdown -->
    {#if formTxType !== 'saving'}
      <div class="mf-field" style="position:relative">
        <label class="mf-label">Категория</label>
        <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
        <div class="cat-trigger" class:open={showCatDrop} on:click={() => showCatDrop = !showCatDrop}>
          {#if selectedCat}
            <span>{selectedCat.emoji ?? ''} {selectedCat.name}</span>
          {:else}
            <span class="placeholder">Выбери категорию</span>
          {/if}
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="13" height="13">
            <polyline points="6 9 12 15 18 9"/>
          </svg>
        </div>

        {#if showCatDrop}
          <!-- Backdrop to close on outside click -->
          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="drop-backdrop" on:click={() => { showCatDrop = false; catSearch = '' }} />
          <div class="cat-drop">
            <input class="cat-search" type="text" placeholder="Поиск категории…" bind:value={catSearch}
              on:click|stopPropagation />
            <div class="cat-options">
              {#each filteredFormCats as cat}
                <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
                <div class="cat-option" class:sel={formCatId === cat.id}
                  on:click={() => { formCatId = cat.id; showCatDrop = false; catSearch = ''; formError = '' }}>
                  <span>{cat.emoji ?? ''} {cat.name}</span>
                  {#if formCatId === cat.id}
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" width="13" height="13">
                      <polyline points="20 6 9 17 4 12"/>
                    </svg>
                  {/if}
                </div>
              {/each}
              {#if filteredFormCats.length === 0}
                <p class="cat-empty-msg">
                  Нет категорий.
                  <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
                  <span class="text-link-inline" on:click={() => { showCatDrop = false; showCatModal = true; startAddCat() }}>
                    Добавить
                  </span>
                </p>
              {/if}
            </div>
          </div>
        {/if}
      </div>
    {/if}

    <!-- Name with autocomplete -->
    <div class="mf-field" style="position:relative">
      <label class="mf-label" for="f-name">Название (необязательно)</label>
      <input id="f-name" type="text" bind:value={formName} on:input={onNameInput}
        placeholder="Яндекс Лавка, Самокат…" autocomplete="off" />
      {#if nameSuggs.length > 0}
        <div class="name-sugg">
          {#each nameSuggs as s}
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <div class="name-sugg-row" on:click={() => pickName(s)}>
              <span class="ns-name">{s.name}</span>
              {#if s.category_id}
                <span class="ns-cat">{categories.find(c => c.id === s.category_id)?.name ?? ''}</span>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <!-- Note -->
    <div class="mf-field">
      <label class="mf-label" for="f-note">Заметка (необязательно)</label>
      <input id="f-note" type="text" bind:value={formNote} placeholder="Комментарий…" />
    </div>

    <!-- Date -->
    <div class="mf-field">
      <label class="mf-label" for="f-date">Дата</label>
      <input id="f-date" type="date" bind:value={formDate} />
    </div>

    <!-- Payment type -->
    {#if formTxType === 'expense'}
      <div class="mf-field">
        <label class="mf-label">Тип оплаты</label>
        <div class="pay-type-row">
          <button class="pay-btn" class:active={formPayType === 'regular'}
            on:click={() => formPayType = 'regular'}>Обычная</button>
          <button class="pay-btn" class:active={formPayType === 'installment'}
            on:click={() => formPayType = 'installment'}>Рассрочка / Долями</button>
        </div>
      </div>
    {/if}

    <!-- Error -->
    {#if formError}
      <p class="form-error">{formError}</p>
    {/if}

    <!-- Actions -->
    <div class="modal-actions">
      {#if editingId}
        <button class="del-btn-action" on:click={() => deleteEntry(editingId ?? '')}>Удалить</button>
      {/if}
      <button class="save-btn-action" on:click={saveEntry} disabled={saving}>
        {saving ? 'Сохраняю…' : editingId ? 'Сохранить' : 'Добавить'}
      </button>
    </div>
  </div>
</Modal>

<!-- ── Category management modal ─────────────────────────────────────────── -->
<Modal title="Категории" open={showCatModal} on:close={() => { showCatModal = false; startAddCat() }}>
  <div class="catm">
    <!-- Filter tabs -->
    <div class="catm-tabs">
      <button class="catm-tab" class:active={catFilter === 'all'}      on:click={() => catFilter = 'all'}>Все</button>
      <button class="catm-tab" class:active={catFilter === 'expense'}  on:click={() => catFilter = 'expense'}>Расходы</button>
      <button class="catm-tab" class:active={catFilter === 'income'}   on:click={() => catFilter = 'income'}>Доходы</button>
    </div>

    <!-- Category list -->
    {#if visibleCats.length > 0}
      <div class="catm-list">
        {#each visibleCats as cat}
          <div class="catm-row" class:editing={editingCatId === cat.id}>
            <span class="catm-emoji">{cat.emoji ?? '·'}</span>
            <span class="catm-name">{cat.name}</span>
            <span class="catm-type">{(cat.applies_to ?? 'expense') === 'income' ? 'доход' : (cat.applies_to === 'both' ? 'оба' : 'расход')}</span>
            {#if cat.is_quick}<span class="catm-quick">⚡</span>{/if}
            <button class="catm-edit" on:click={() => startEditCat(cat)}>✏</button>
            <button class="catm-del"  on:click={() => deleteCat(cat.id)}>×</button>
          </div>
        {/each}
      </div>
    {:else}
      <p class="catm-empty">Нет категорий</p>
    {/if}

    <div class="catm-divider" />

    <!-- Add / edit form -->
    <p class="catm-form-title">{editingCatId ? 'Редактировать' : 'Новая категория'}</p>

    <div class="catm-form-row">
      <div class="mf-field" style="flex: 0 0 4.5rem">
        <label class="mf-label">Эмодзи</label>
        <input type="text" bind:value={catFEmoji} placeholder="🛒" maxlength="2" class="emoji-input" />
      </div>
      <div class="mf-field" style="flex: 1">
        <label class="mf-label">Название</label>
        <input type="text" bind:value={catFName} placeholder="Продукты" />
      </div>
    </div>

    <div class="mf-field">
      <label class="mf-label">Тип</label>
      <div class="pay-type-row">
        <button class="pay-btn" class:active={catFAppliesTo === 'expense'}
          on:click={() => catFAppliesTo = 'expense'}>Расходы</button>
        <button class="pay-btn" class:active={catFAppliesTo === 'income'}
          on:click={() => catFAppliesTo = 'income'}>Доходы</button>
        <button class="pay-btn" class:active={catFAppliesTo === 'both'}
          on:click={() => catFAppliesTo = 'both'}>Оба</button>
      </div>
    </div>

    <label class="checkbox-row">
      <input type="checkbox" bind:checked={catFIsQuick} />
      <span>Показывать в быстром доступе</span>
    </label>

    <div class="modal-actions">
      {#if editingCatId}
        <button class="del-btn-action" on:click={startAddCat}>Отмена</button>
      {/if}
      <button class="save-btn-action" on:click={saveCat}
        disabled={catFSaving || !catFName.trim()}>
        {catFSaving ? 'Сохраняю…' : editingCatId ? 'Сохранить' : 'Добавить'}
      </button>
    </div>
  </div>
</Modal>

<style>
  /* ── Page ── */
  .page-shell {
    max-width: 480px;
    margin: 0 auto;
    padding: 0 1.375rem 6rem;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 0 0.75rem;
  }

  .add-btn {
    background: var(--color-accent);
    color: white;
    border: none;
    border-radius: 0.875rem;
    padding: 0.5rem 1rem;
    font-size: 0.9375rem;
    cursor: pointer;
    transition: opacity 0.15s;
    -webkit-tap-highlight-color: transparent;
  }
  .add-btn:active { opacity: 0.8; }

  /* ── Period tabs ── */
  .period-tabs {
    display: flex;
    gap: 0.375rem;
    margin-bottom: 0.75rem;
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

  /* ── Month nav ── */
  .month-nav {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    padding: 0.375rem 0.5rem;
  }

  .month-arrow {
    background: none;
    border: none;
    font-size: 1.25rem;
    color: var(--color-accent);
    cursor: pointer;
    padding: 0.125rem 0.5rem;
    -webkit-tap-highlight-color: transparent;
  }
  .month-arrow:disabled { color: var(--color-muted); cursor: default; }

  .month-label {
    font-size: 0.9375rem;
    color: var(--color-text);
    text-transform: capitalize;
  }

  /* ── Summary ── */
  .summary-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.625rem;
    margin-bottom: 0.625rem;
  }

  .sum-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.125rem;
    padding: 0.875rem 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .sum-label {
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-muted);
  }

  .sum-amount {
    font-family: "JetBrains Mono", monospace;
    font-size: 1.25rem;
  }

  /* ── Colors ── */
  .exp-color { color: var(--color-text); }
  .inc-color { color: var(--color-success, #38a169); }
  .sav-color { color: var(--color-accent); }

  /* ── Credit banner ── */
  .credit-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 0.5rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    padding: 0.625rem 0.875rem;
    margin-bottom: 0.625rem;
  }

  .credit-text { font-size: 0.8125rem; color: var(--color-muted); }
  .credit-text strong { color: var(--color-text); }

  .toggle-wrap { display: flex; align-items: center; gap: 0.375rem; cursor: pointer; }
  .toggle-label { font-size: 0.8125rem; color: var(--color-muted); user-select: none; }

  /* ── Quick section ── */
  .quick-section { margin: 0.75rem 0 0.5rem; }

  .quick-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.5rem;
  }

  .section-caption {
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.07em;
    color: var(--color-muted);
  }

  .icon-link {
    color: var(--color-muted);
    cursor: pointer;
    padding: 0.25rem;
    -webkit-tap-highlight-color: transparent;
    display: flex;
    align-items: center;
  }
  .icon-link:active { color: var(--color-accent); }

  .quick-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 0.375rem;
  }

  .quick-btn {
    padding: 0.625rem 0.375rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    font-size: 0.8125rem;
    color: var(--color-text);
    cursor: pointer;
    text-align: center;
    line-height: 1.3;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .quick-btn:active { background: var(--color-card-hover, var(--color-border)); transform: scale(0.97); }
  .other-btn { color: var(--color-muted); }

  .text-link {
    background: none;
    border: none;
    color: var(--color-accent);
    font-size: 0.875rem;
    cursor: pointer;
    padding: 0.375rem 0;
    -webkit-tap-highlight-color: transparent;
  }

  /* ── Search ── */
  .search-row {
    margin: 0.625rem 0;
  }

  .search-wrap {
    position: relative;
    display: flex;
    align-items: center;
  }

  .search-icon {
    position: absolute;
    left: 0.75rem;
    color: var(--color-muted);
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    padding: 0.5625rem 0.875rem 0.5625rem 2.375rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    color: var(--color-text);
    font-size: 0.9375rem;
    font-family: inherit;
    box-sizing: border-box;
    -webkit-appearance: none;
  }
  .search-input:focus { outline: none; border-color: var(--color-accent); }
  .search-input::-webkit-search-cancel-button { display: none; }

  .search-clear {
    position: absolute;
    right: 0.75rem;
    background: none;
    border: none;
    color: var(--color-muted);
    font-size: 1.125rem;
    cursor: pointer;
    padding: 0;
    line-height: 1;
  }

  /* ── Expense list ── */
  .expense-list { display: flex; flex-direction: column; gap: 1.125rem; margin-top: 0.5rem; }

  .day-group { display: flex; flex-direction: column; gap: 0.375rem; }

  .day-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 0.25rem;
  }

  .day-label {
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--color-muted);
  }

  .day-total {
    font-family: "JetBrains Mono", monospace;
    font-size: 0.875rem;
    color: var(--color-text);
  }

  .day-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.125rem;
    overflow: hidden;
  }

  .exp-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.625rem 0.875rem;
    border-bottom: 1px solid var(--color-border);
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: background 0.1s;
  }
  .exp-row:last-child { border-bottom: none; }
  .exp-row:active { background: var(--color-bg); }

  .exp-info { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }

  .exp-primary {
    font-size: 0.9375rem;
    color: var(--color-text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .exp-name-dot {
    color: var(--color-muted);
    font-size: 0.875rem;
  }

  .exp-note {
    font-size: 0.75rem;
    color: var(--color-muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .exp-right {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 2px;
    flex-shrink: 0;
  }

  .exp-amount {
    font-family: "JetBrains Mono", monospace;
    font-size: 0.9375rem;
    white-space: nowrap;
  }

  .badge-inst {
    font-size: 0.625rem;
    background: var(--color-border);
    color: var(--color-muted);
    border-radius: 0.375rem;
    padding: 1px 5px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  /* ── FAB ── */
  .fab {
    position: fixed;
    bottom: calc(4.5rem + env(safe-area-inset-bottom));
    right: 1.25rem;
    width: 3.25rem;
    height: 3.25rem;
    border-radius: 50%;
    background: var(--color-accent);
    color: white;
    border: none;
    font-size: 1.75rem;
    line-height: 1;
    cursor: pointer;
    box-shadow: 0 4px 16px rgba(0,0,0,0.18);
    display: flex;
    align-items: center;
    justify-content: center;
    -webkit-tap-highlight-color: transparent;
    transition: transform 0.15s, opacity 0.15s;
    z-index: 50;
  }
  .fab:active { transform: scale(0.92); opacity: 0.85; }

  /* ── Modal form ── */
  .mform { display: flex; flex-direction: column; gap: 1rem; }

  .mf-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .mf-label {
    font-size: 0.6875rem;
    color: var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .type-tabs {
    display: flex;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    padding: 0.25rem;
    gap: 0.25rem;
  }

  .type-tab {
    flex: 1;
    padding: 0.5rem;
    border: none;
    border-radius: 0.625rem;
    font-size: 0.875rem;
    background: none;
    color: var(--color-muted);
    cursor: pointer;
    transition: all 0.15s;
    -webkit-tap-highlight-color: transparent;
  }
  .type-tab.active { background: var(--color-accent); color: white; }

  .amount-input {
    font-family: "JetBrains Mono", monospace !important;
    font-size: 1.75rem !important;
    text-align: center;
    padding: 0.75rem !important;
  }

  /* ── Category dropdown ── */
  .cat-trigger {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.625rem 0.875rem;
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    cursor: pointer;
    font-size: 1rem;
    color: var(--color-text);
    -webkit-tap-highlight-color: transparent;
    transition: border-color 0.15s;
  }
  .cat-trigger.open { border-color: var(--color-accent); }
  .placeholder { color: var(--color-muted); }

  .drop-backdrop {
    position: fixed;
    inset: 0;
    z-index: 90;
  }

  .cat-drop {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    right: 0;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    box-shadow: 0 6px 24px rgba(0,0,0,0.12);
    z-index: 100;
    overflow: hidden;
  }

  .cat-search {
    width: 100%;
    padding: 0.625rem 0.875rem;
    border: none;
    border-bottom: 1px solid var(--color-border);
    background: var(--color-bg);
    color: var(--color-text);
    font-size: 0.9375rem;
    font-family: inherit;
    box-sizing: border-box;
  }
  .cat-search:focus { outline: none; }

  .cat-options {
    max-height: 11rem;
    overflow-y: auto;
  }

  .cat-option {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.625rem 0.875rem;
    cursor: pointer;
    font-size: 0.9375rem;
    color: var(--color-text);
    border-bottom: 1px solid var(--color-border);
    -webkit-tap-highlight-color: transparent;
  }
  .cat-option:last-child { border-bottom: none; }
  .cat-option:active { background: var(--color-bg); }
  .cat-option.sel { color: var(--color-accent); }

  .cat-empty-msg {
    padding: 0.875rem;
    font-size: 0.875rem;
    color: var(--color-muted);
    margin: 0;
    text-align: center;
  }

  .text-link-inline {
    background: none;
    border: none;
    color: var(--color-accent);
    font-size: inherit;
    cursor: pointer;
    padding: 0;
    text-decoration: underline;
  }

  /* ── Name autocomplete ── */
  .name-sugg {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    box-shadow: 0 4px 16px rgba(0,0,0,0.1);
    z-index: 80;
    overflow: hidden;
    margin-top: 2px;
  }

  .name-sugg-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5625rem 0.875rem;
    cursor: pointer;
    border-bottom: 1px solid var(--color-border);
    -webkit-tap-highlight-color: transparent;
  }
  .name-sugg-row:last-child { border-bottom: none; }
  .name-sugg-row:active { background: var(--color-bg); }

  .ns-name { font-size: 0.9375rem; color: var(--color-text); }
  .ns-cat  { font-size: 0.75rem; color: var(--color-muted); }

  /* ── Payment type ── */
  .pay-type-row {
    display: flex;
    gap: 0.375rem;
  }

  .pay-btn {
    flex: 1;
    padding: 0.5rem 0.375rem;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-card);
    color: var(--color-muted);
    font-size: 0.8125rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
    line-height: 1.3;
    text-align: center;
  }
  .pay-btn.active {
    background: var(--color-accent);
    border-color: var(--color-accent);
    color: white;
  }

  /* ── Form error ── */
  .form-error {
    font-size: 0.8125rem;
    color: var(--color-danger, #e53e3e);
    margin: 0;
    padding: 0.375rem 0.5rem;
    background: rgba(229, 62, 62, 0.08);
    border-radius: 0.5rem;
  }

  /* ── Modal actions ── */
  .modal-actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 0.25rem;
  }

  .save-btn-action {
    flex: 1;
    padding: 0.875rem;
    background: var(--color-accent);
    color: white;
    border: none;
    border-radius: 1rem;
    font-size: 1rem;
    font-family: inherit;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
  }
  .save-btn-action:disabled { opacity: 0.5; cursor: default; }

  .del-btn-action {
    padding: 0.875rem 1.125rem;
    background: none;
    border: 1.5px solid var(--color-danger, #e53e3e);
    color: var(--color-danger, #e53e3e);
    border-radius: 1rem;
    font-size: 0.9375rem;
    font-family: inherit;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    white-space: nowrap;
    transition: opacity 0.15s;
  }
  .del-btn-action:active { opacity: 0.7; }

  /* ── Category management modal ── */
  .catm { display: flex; flex-direction: column; gap: 0.875rem; }

  .catm-tabs {
    display: flex;
    gap: 0.375rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    padding: 0.25rem;
  }

  .catm-tab {
    flex: 1;
    padding: 0.375rem 0.5rem;
    border: none;
    border-radius: 0.5rem;
    background: none;
    color: var(--color-muted);
    font-size: 0.8125rem;
    cursor: pointer;
    transition: all 0.15s;
  }
  .catm-tab.active { background: var(--color-accent); color: white; }

  .catm-list { display: flex; flex-direction: column; gap: 0; max-height: 12rem; overflow-y: auto; }

  .catm-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 0.25rem;
    border-bottom: 1px solid var(--color-border);
  }
  .catm-row:last-child { border-bottom: none; }
  .catm-row.editing { background: var(--color-bg); border-radius: 0.5rem; padding: 0.5rem; }

  .catm-emoji { font-size: 1.1rem; flex-shrink: 0; width: 1.5rem; text-align: center; }
  .catm-name  { flex: 1; font-size: 0.9375rem; color: var(--color-text); }
  .catm-type  { font-size: 0.6875rem; color: var(--color-muted); flex-shrink: 0; }
  .catm-quick { font-size: 0.75rem; }

  .catm-edit {
    background: none;
    border: none;
    color: var(--color-muted);
    cursor: pointer;
    padding: 0.25rem;
    font-size: 0.875rem;
    -webkit-tap-highlight-color: transparent;
  }

  .catm-del {
    background: none;
    border: none;
    color: var(--color-muted);
    cursor: pointer;
    padding: 0.25rem;
    font-size: 1.125rem;
    line-height: 1;
    -webkit-tap-highlight-color: transparent;
  }
  .catm-del:active { color: var(--color-danger, #e53e3e); }

  .catm-empty { font-size: 0.875rem; color: var(--color-muted); margin: 0; text-align: center; padding: 0.5rem 0; }

  .catm-divider { border: none; border-top: 1px solid var(--color-border); margin: 0; }

  .catm-form-title {
    font-size: 0.8125rem;
    font-weight: 500;
    color: var(--color-text);
    margin: 0;
  }

  .catm-form-row {
    display: flex;
    gap: 0.5rem;
    align-items: flex-end;
  }

  .emoji-input { text-align: center; font-size: 1.25rem; padding: 0.5rem !important; }

  .checkbox-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.875rem;
    color: var(--color-text);
    cursor: pointer;
  }

  /* ── Skeleton / empty ── */
  .skeleton-block {
    height: 8rem;
    border-radius: 1.25rem;
    margin-top: 0.5rem;
    background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover, var(--color-border)) 50%, var(--color-card) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.4s infinite;
  }

  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .empty-state {
    padding: 2.5rem 1rem;
    text-align: center;
    color: var(--color-muted);
    background: var(--color-card);
    border: 1px dashed var(--color-border);
    border-radius: 1.25rem;
    font-size: 0.9375rem;
    margin-top: 0.5rem;
  }
</style>
