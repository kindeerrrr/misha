<script lang="ts">
  /*
    SQL migration:

    create table if not exists credits (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references auth.users not null,
      name text not null,
      total_amount numeric not null,
      remaining numeric not null,
      monthly_payment numeric,
      payment_day int,
      start_date date not null,
      end_date date,
      is_complex boolean default false,
      notes text,
      created_at timestamptz default now()
    );
    alter table credits enable row level security;
    create policy "credits: own" on credits for all using (auth.uid() = user_id);

    create table if not exists credit_payments (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references auth.users not null,
      credit_id uuid references credits on delete cascade not null,
      date date not null,
      amount numeric not null,
      paid boolean default true,
      notes text,
      created_at timestamptz default now()
    );
    alter table credit_payments enable row level security;
    create policy "credit_payments: own" on credit_payments for all using (auth.uid() = user_id);

    -- if tables already exist, run these to add new columns:
    -- alter table credits add column if not exists is_complex boolean default false;
  */

  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import { icons } from '../lib/icons'
  import Modal from '../components/ui/Modal.svelte'
  import { showToast } from '../stores/toast'
  import type { Credit, CreditPayment } from '../lib/types'

  const todayDate = today()
  const RU_MONTHS_SHORT = ['янв','фев','мар','апр','мая','июн','июл','авг','сен','окт','ноя','дек']
  const RU_MONTHS_FULL  = ['Январь','Февраль','Март','Апрель','Май','Июнь','Июль','Август','Сентябрь','Октябрь','Ноябрь','Декабрь']

  function fmt(d: string | null | undefined): string {
    if (!d) return ''
    const p = d.split('-')
    return p.length < 3 ? '' : `${parseInt(p[2])} ${RU_MONTHS_SHORT[parseInt(p[1]) - 1]} ${p[0]}`
  }

  function monthLabel(key: string): string {
    const [y, m] = key.split('-')
    return `${RU_MONTHS_FULL[parseInt(m) - 1]} ${y}`
  }

  function nextPaymentDate(paymentDay: number | null): string | null {
    if (!paymentDay) return null
    const now = new Date()
    const y = now.getFullYear(), m = now.getMonth(), d = now.getDate()
    const thisMonth = new Date(y, m, Math.min(paymentDay, new Date(y, m + 1, 0).getDate()))
    return (d <= paymentDay ? thisMonth : new Date(y, m + 1, Math.min(paymentDay, new Date(y, m + 2, 0).getDate())))
      .toISOString().slice(0, 10)
  }

  function daysUntil(dateStr: string | null): number | null {
    if (!dateStr) return null
    return Math.round((new Date(dateStr + 'T12:00:00').getTime() - new Date(todayDate + 'T12:00:00').getTime()) / 86400000)
  }

  function closureForecast(c: Credit): string | null {
    if (!c.monthly_payment || c.monthly_payment <= 0 || c.remaining <= 0) return null
    const months = Math.ceil(c.remaining / c.monthly_payment)
    const d = new Date()
    d.setMonth(d.getMonth() + months)
    return `${RU_MONTHS_SHORT[d.getMonth()]} ${d.getFullYear()}`
  }

  function paidPct(c: Credit): number {
    if (!c.total_amount) return 0
    return Math.min(100, Math.round(((c.total_amount - c.remaining) / c.total_amount) * 100))
  }

  function groupByMonth(ps: CreditPayment[]): { key: string; label: string; payments: CreditPayment[] }[] {
    const map = new Map<string, CreditPayment[]>()
    for (const p of ps) {
      const k = p.date.slice(0, 7)
      if (!map.has(k)) map.set(k, [])
      map.get(k)!.push(p)
    }
    return Array.from(map.entries())
      .sort((a, b) => b[0].localeCompare(a[0]))
      .map(([key, payments]) => ({ key, label: monthLabel(key), payments }))
  }

  // Simple sparkline SVG from payment history
  function sparkline(ps: CreditPayment[], totalAmount: number): string {
    const paid = [...ps].filter(p => p.paid).sort((a, b) => a.date.localeCompare(b.date))
    if (paid.length < 2) return ''
    let running = totalAmount
    const points: number[] = [totalAmount]
    for (const p of paid) { running = Math.max(0, running - p.amount); points.push(running) }
    const max = Math.max(...points), min = Math.min(...points, 0)
    const range = max - min || 1
    const W = 120, H = 32
    const coords = points.map((v, i) => {
      const x = (i / (points.length - 1)) * W
      const y = H - ((v - min) / range) * H
      return `${x.toFixed(1)},${y.toFixed(1)}`
    }).join(' ')
    return `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" fill="none" xmlns="http://www.w3.org/2000/svg">
      <polyline points="${coords}" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none" opacity="0.6"/>
      <circle cx="${(points.length-1)/(points.length-1)*W}" cy="${(H - ((points[points.length-1]-min)/range)*H).toFixed(1)}" r="2.5" fill="currentColor"/>
    </svg>`
  }

  // ── View state ─────────────────────────────────────────────────────────────
  let view: 'list' | 'detail' = 'list'
  let activeCredit: Credit | null = null
  let loading = true

  // ── Data ───────────────────────────────────────────────────────────────────
  let credits: Credit[] = []
  let payments: CreditPayment[] = []

  // ── Modals ─────────────────────────────────────────────────────────────────
  let showCreditModal = false
  let showPaymentModal = false
  let editingCredit: Credit | null = null

  // ── Credit form ────────────────────────────────────────────────────────────
  let fName = ''
  let fTotal = ''
  let fRemaining = ''
  let fMonthly = ''
  let fPaymentDay = ''
  let fStartDate = todayDate
  let fEndDate = ''
  let fIsComplex = false
  let fNotes = ''

  // ── Payment form ───────────────────────────────────────────────────────────
  let fPayDate = todayDate
  let fPayAmount = ''
  let fPayPaid = true
  let fPayNotes = ''

  // ── Derived ───────────────────────────────────────────────────────────────
  $: activePayments = payments.filter(p => p.credit_id === activeCredit?.id)
  $: upcomingPayments = activePayments.filter(p => !p.paid).sort((a, b) => a.date.localeCompare(b.date))
  $: historyPayments = activePayments.filter(p => p.paid).sort((a, b) => b.date.localeCompare(a.date))
  $: historyByMonth = groupByMonth(historyPayments)
  $: totalRemaining = credits.reduce((s, c) => s + c.remaining, 0)
  $: totalMonthly = credits.filter(c => c.monthly_payment).reduce((s, c) => s + (c.monthly_payment ?? 0), 0)

  // ── Load ───────────────────────────────────────────────────────────────────
  async function load() {
    const { data } = await supabase.from('credits')
      .select('*').eq('user_id', $user!.id).order('created_at')
    credits = data ?? []
    loading = false
  }

  async function loadPayments(creditId: string) {
    const { data } = await supabase.from('credit_payments')
      .select('*').eq('credit_id', creditId).order('date', { ascending: false })
    payments = [...payments.filter(p => p.credit_id !== creditId), ...(data ?? [])]
  }

  async function openDetail(c: Credit) {
    activeCredit = c; view = 'detail'
    await loadPayments(c.id)
  }

  function backToList() { view = 'list'; activeCredit = null }

  // ── Credit CRUD ────────────────────────────────────────────────────────────
  function openNewCredit() {
    editingCredit = null
    fName = ''; fTotal = ''; fRemaining = ''; fMonthly = ''; fPaymentDay = ''
    fStartDate = todayDate; fEndDate = ''; fIsComplex = false; fNotes = ''
    showCreditModal = true
  }

  function openEditCredit(c: Credit) {
    editingCredit = c
    fName = c.name; fTotal = String(c.total_amount); fRemaining = String(c.remaining)
    fMonthly = c.monthly_payment != null ? String(c.monthly_payment) : ''
    fPaymentDay = c.payment_day != null ? String(c.payment_day) : ''
    fStartDate = c.start_date; fEndDate = c.end_date ?? ''
    fIsComplex = c.is_complex; fNotes = c.notes ?? ''
    showCreditModal = true
  }

  async function saveCredit() {
    if (!fName.trim() || !fTotal || !fRemaining) return
    const payload = {
      user_id: $user!.id,
      name: fName.trim(),
      total_amount: parseFloat(fTotal),
      remaining: parseFloat(fRemaining),
      monthly_payment: fMonthly ? parseFloat(fMonthly) : null,
      payment_day: fPaymentDay ? parseInt(fPaymentDay) : null,
      start_date: fStartDate,
      end_date: fEndDate || null,
      is_complex: fIsComplex,
      notes: fNotes.trim() || null,
    }
    if (editingCredit) {
      const { data } = await supabase.from('credits').update(payload).eq('id', editingCredit.id).select().single()
      if (data) { credits = credits.map(c => c.id === data.id ? data : c); if (activeCredit?.id === data.id) activeCredit = data }
    } else {
      const { data } = await supabase.from('credits').insert(payload).select().single()
      if (data) credits = [...credits, data]
    }
    showCreditModal = false
  }

  async function deleteCredit(id: string) {
    await supabase.from('credits').delete().eq('id', id)
    credits = credits.filter(c => c.id !== id)
    showCreditModal = false; backToList()
    showToast('Удалено', 'success')
  }

  // ── Payment CRUD ───────────────────────────────────────────────────────────
  function openAddPayment() {
    fPayDate = todayDate
    fPayAmount = activeCredit?.monthly_payment ? String(activeCredit.monthly_payment) : ''
    fPayPaid = !activeCredit?.is_complex  // simple → always paid; complex → default unpaid (scheduled)
    fPayNotes = ''
    showPaymentModal = true
  }

  async function savePayment() {
    if (!fPayAmount || !activeCredit) return
    const amount = parseFloat(fPayAmount)
    const { data } = await supabase.from('credit_payments').insert({
      user_id: $user!.id, credit_id: activeCredit.id,
      date: fPayDate, amount, paid: fPayPaid, notes: fPayNotes.trim() || null,
    }).select().single()
    if (data) payments = [data, ...payments]

    if (fPayPaid) {
      const newRemaining = Math.max(0, activeCredit.remaining - amount)
      const { data: updated } = await supabase.from('credits')
        .update({ remaining: newRemaining }).eq('id', activeCredit.id).select().single()
      if (updated) { credits = credits.map(c => c.id === updated.id ? updated : c); activeCredit = updated }
    }
    showPaymentModal = false
    showToast(fPayPaid ? 'Платёж записан' : 'Запланировано', 'success')
  }

  async function markPaid(p: CreditPayment) {
    if (!activeCredit) return
    await supabase.from('credit_payments').update({ paid: true }).eq('id', p.id)
    payments = payments.map(x => x.id === p.id ? { ...x, paid: true } : x)
    const newRemaining = Math.max(0, activeCredit.remaining - p.amount)
    const { data: updated } = await supabase.from('credits')
      .update({ remaining: newRemaining }).eq('id', activeCredit.id).select().single()
    if (updated) { credits = credits.map(c => c.id === updated.id ? updated : c); activeCredit = updated }
    showToast('Оплачено', 'success')
  }

  async function deletePayment(p: CreditPayment) {
    if (p.paid && activeCredit) {
      const restored = activeCredit.remaining + p.amount
      const { data: updated } = await supabase.from('credits')
        .update({ remaining: restored }).eq('id', activeCredit.id).select().single()
      if (updated) { credits = credits.map(c => c.id === updated.id ? updated : c); activeCredit = updated }
    }
    await supabase.from('credit_payments').delete().eq('id', p.id)
    payments = payments.filter(x => x.id !== p.id)
  }

  onMount(load)
</script>

<!-- ══════════════════════════════════════════════════════════ LIST VIEW ══ -->
{#if view === 'list'}
  <div class="page-shell">
    <header class="page-header">
      <div class="header-text">
        <h1 class="page-title">Кредиты</h1>
      </div>
      <button class="fab-inline" on:click={openNewCredit} aria-label="Добавить">
        {@html icons.plus}
      </button>
    </header>

    {#if loading}
      <p class="muted-hint">Загрузка...</p>
    {:else if credits.length === 0}
      <div class="empty-state">
        <div class="empty-icon">{@html icons.credit_card}</div>
        <p class="empty-title">Нет кредитов</p>
        <p class="empty-sub">Добавь кредит или долг</p>
      </div>
    {:else}
      <div class="summary-card">
        <div class="summary-row">
          <div>
            <span class="summary-label">Общий долг</span>
            <span class="summary-amount">{totalRemaining.toLocaleString('ru')} ₽</span>
          </div>
          {#if totalMonthly > 0}
            <div class="summary-monthly">
              <span class="summary-label">В месяц</span>
              <span class="summary-monthly-val">{totalMonthly.toLocaleString('ru')} ₽</span>
            </div>
          {/if}
        </div>
      </div>

      <div class="credit-list">
        {#each credits as credit}
          {@const pct = paidPct(credit)}
          {@const nextDate = nextPaymentDate(credit.payment_day)}
          {@const days = daysUntil(nextDate)}
          {@const forecast = closureForecast(credit)}
          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="credit-card" on:click={() => openDetail(credit)}>
            <div class="credit-top">
              <div class="credit-name-row">
                <span class="credit-name">{credit.name}</span>
                {#if credit.is_complex}
                  <span class="complex-badge">Сплит</span>
                {/if}
              </div>
              <span class="credit-remaining">{credit.remaining.toLocaleString('ru')} ₽</span>
            </div>

            <div class="progress-bar">
              <div class="progress-fill" style="width:{pct}%"></div>
            </div>
            <div class="progress-labels">
              <span>{pct}% выплачено</span>
              <span>из {credit.total_amount.toLocaleString('ru')} ₽</span>
            </div>

            <div class="credit-meta">
              {#if credit.monthly_payment}
                <span class="meta-chip">{credit.monthly_payment.toLocaleString('ru')} ₽/мес</span>
              {/if}
              {#if nextDate && days !== null && !credit.is_complex}
                <span class="meta-chip" class:urgent={days <= 3 && days >= 0} class:overdue={days < 0}>
                  {#if days < 0}просрочен {Math.abs(days)} дн.
                  {:else if days === 0}платёж сегодня
                  {:else if days === 1}платёж завтра
                  {:else}платёж {fmt(nextDate)}
                  {/if}
                </span>
              {/if}
              {#if forecast}
                <span class="meta-chip">закроется ~{forecast}</span>
              {/if}
            </div>
          </div>
        {/each}
      </div>
    {/if}
  </div>

<!-- ══════════════════════════════════════════════════════════ DETAIL VIEW ══ -->
{:else if view === 'detail' && activeCredit}
  {@const pct = paidPct(activeCredit)}
  {@const nextDate = nextPaymentDate(activeCredit.payment_day)}
  {@const days = daysUntil(nextDate)}
  {@const forecast = closureForecast(activeCredit)}
  {@const spark = sparkline(historyPayments, activeCredit.total_amount)}

  <div class="page-shell">
    <header class="page-header">
      <button class="back-btn" on:click={backToList} aria-label="Назад">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M15 18l-6-6 6-6"/></svg>
      </button>
      <div class="header-text">
        <h1 class="page-title" style="font-size:1.25rem">{activeCredit.name}</h1>
        {#if activeCredit.is_complex}<span class="complex-badge">Сложный долг</span>{/if}
      </div>
      <button class="icon-btn" on:click={() => activeCredit && openEditCredit(activeCredit)} aria-label="Редактировать">
        {@html icons.edit}
      </button>
    </header>

    <!-- Hero -->
    <div class="detail-hero">
      <div class="hero-top">
        <div>
          <span class="detail-remaining-label">Осталось</span>
          <span class="detail-remaining-amount">{activeCredit.remaining.toLocaleString('ru')} ₽</span>
          <span class="detail-total-sub">из {activeCredit.total_amount.toLocaleString('ru')} ₽ · {pct}% выплачено</span>
        </div>
        {#if spark}
          <div class="sparkline" style="color:var(--color-accent)">{@html spark}</div>
        {/if}
      </div>

      <div class="progress-bar big">
        <div class="progress-fill" style="width:{pct}%"></div>
      </div>

      <div class="detail-meta-row">
        {#if activeCredit.monthly_payment}
          <div class="detail-meta-block">
            <span class="detail-meta-label">Платёж</span>
            <span class="detail-meta-val">{activeCredit.monthly_payment.toLocaleString('ru')} ₽</span>
          </div>
        {/if}
        {#if activeCredit.payment_day && !activeCredit.is_complex}
          <div class="detail-meta-block">
            <span class="detail-meta-label">Число</span>
            <span class="detail-meta-val">{activeCredit.payment_day}</span>
          </div>
        {/if}
        {#if nextDate && !activeCredit.is_complex}
          <div class="detail-meta-block">
            <span class="detail-meta-label">Следующий</span>
            <span class="detail-meta-val" class:urgent={days !== null && days <= 3 && days >= 0} class:overdue={days !== null && days < 0}>
              {#if days === null}—
              {:else if days < 0}просрочен {Math.abs(days)} дн.
              {:else if days === 0}сегодня
              {:else if days === 1}завтра
              {:else}через {days} дн.
              {/if}
            </span>
          </div>
        {/if}
        {#if forecast}
          <div class="detail-meta-block">
            <span class="detail-meta-label">Прогноз</span>
            <span class="detail-meta-val">~{forecast}</span>
          </div>
        {/if}
        {#if activeCredit.end_date}
          <div class="detail-meta-block">
            <span class="detail-meta-label">Срок</span>
            <span class="detail-meta-val">{fmt(activeCredit.end_date)}</span>
          </div>
        {/if}
      </div>

      {#if activeCredit.notes}
        <p class="detail-notes">{activeCredit.notes}</p>
      {/if}
    </div>

    <!-- Upcoming (complex mode) -->
    {#if activeCredit.is_complex && upcomingPayments.length > 0}
      <div class="section-row">
        <p class="section-label">Предстоящие платежи</p>
      </div>
      <div class="payment-list mb-4">
        {#each upcomingPayments as p}
          {@const d = daysUntil(p.date)}
          <div class="payment-row upcoming">
            <div class="payment-info">
              <span class="payment-amount">{p.amount.toLocaleString('ru')} ₽</span>
              <span class="payment-date">
                {fmt(p.date)}
                {#if d !== null}
                  · <span class:urgent-text={d <= 3 && d >= 0} class:overdue-text={d < 0}>
                    {d < 0 ? `просрочен ${Math.abs(d)} дн.` : d === 0 ? 'сегодня' : d === 1 ? 'завтра' : `через ${d} дн.`}
                  </span>
                {/if}
              </span>
              {#if p.notes}<span class="payment-note">{p.notes}</span>{/if}
            </div>
            <button class="pay-btn" on:click={() => markPaid(p)}>Оплатить</button>
            <button class="delete-btn-sm" on:click={() => deletePayment(p)} aria-label="Удалить">×</button>
          </div>
        {/each}
      </div>
    {/if}

    <!-- History -->
    <div class="section-row">
      <p class="section-label">История</p>
      <button class="add-pay-btn" on:click={openAddPayment}>
        {activeCredit.is_complex ? '+ Добавить' : '+ Внести платёж'}
      </button>
    </div>

    {#if historyByMonth.length === 0}
      <p class="muted-hint" style="margin-top:0.75rem">Нет платежей</p>
    {:else}
      {#each historyByMonth as group}
        <div class="month-group">
          <div class="month-header">
            <span class="month-label">{group.label}</span>
            <span class="month-sum">−{group.payments.reduce((s, p) => s + p.amount, 0).toLocaleString('ru')} ₽</span>
          </div>
          <div class="payment-list">
            {#each group.payments as p}
              <div class="payment-row">
                <div class="payment-info">
                  <span class="payment-amount">−{p.amount.toLocaleString('ru')} ₽</span>
                  <span class="payment-date">{fmt(p.date)}</span>
                  {#if p.notes}<span class="payment-note">{p.notes}</span>{/if}
                </div>
                <button class="delete-btn-sm" on:click={() => deletePayment(p)} aria-label="Удалить">×</button>
              </div>
            {/each}
          </div>
        </div>
      {/each}
    {/if}
  </div>
{/if}

<!-- ══════════════════════════════════════════════════════════ MODALS ══ -->

<Modal title={editingCredit ? 'Редактировать' : 'Новый кредит'} open={showCreditModal} on:close={() => showCreditModal = false}>
  <div class="form-group">
    <label class="form-label">Название *</label>
    <input class="form-input" bind:value={fName} placeholder="Ипотека, Сплит, Долг Пете…" />
  </div>

  <!-- Тумблер простой/сложный -->
  <div class="form-group">
    <div class="toggle-row">
      <div class="toggle-text">
        <span class="toggle-label">Сложный долг</span>
        <span class="toggle-sub">Платежи в разные даты и суммы (Сплит, рассрочка)</span>
      </div>
      <button
        class="toggle-btn"
        class:on={fIsComplex}
        on:click={() => fIsComplex = !fIsComplex}
        role="switch"
        aria-checked={fIsComplex}
      >
        <span class="toggle-knob"></span>
      </button>
    </div>
  </div>

  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Сумма всего *</label>
      <input class="form-input" type="number" bind:value={fTotal} placeholder="500 000" />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Осталось *</label>
      <input class="form-input" type="number" bind:value={fRemaining} placeholder="320 000" />
    </div>
  </div>

  {#if !fIsComplex}
    <div class="form-row">
      <div class="form-group" style="flex:1">
        <label class="form-label">Платёж/мес</label>
        <input class="form-input" type="number" bind:value={fMonthly} placeholder="15 000" />
      </div>
      <div class="form-group" style="flex:1">
        <label class="form-label">Число платежа</label>
        <input class="form-input" type="number" min="1" max="31" bind:value={fPaymentDay} placeholder="15" />
      </div>
    </div>
  {/if}

  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Начало</label>
      <input class="form-input" type="date" bind:value={fStartDate} />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Конец</label>
      <input class="form-input" type="date" bind:value={fEndDate} />
    </div>
  </div>
  <div class="form-group">
    <label class="form-label">Заметки</label>
    <textarea class="form-input" rows="2" bind:value={fNotes} placeholder="…"></textarea>
  </div>
  <div class="form-actions">
    {#if editingCredit}
      {@const toDelete = editingCredit}
      <button class="btn-danger" on:click={() => deleteCredit(toDelete.id)}>Удалить</button>
    {/if}
    <button class="btn-primary" on:click={saveCredit}>Сохранить</button>
  </div>
</Modal>

<Modal title={activeCredit?.is_complex ? 'Добавить платёж' : 'Внести платёж'} open={showPaymentModal} on:close={() => showPaymentModal = false}>
  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Сумма *</label>
      <input class="form-input" type="number" bind:value={fPayAmount} placeholder="15 000" />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Дата</label>
      <input class="form-input" type="date" bind:value={fPayDate} />
    </div>
  </div>
  {#if activeCredit?.is_complex}
    <div class="form-group">
      <div class="toggle-row">
        <div class="toggle-text">
          <span class="toggle-label">Уже оплачен</span>
          <span class="toggle-sub">Если нет — сохранится как запланированный</span>
        </div>
        <button class="toggle-btn" class:on={fPayPaid} on:click={() => fPayPaid = !fPayPaid} role="switch" aria-checked={fPayPaid}>
          <span class="toggle-knob"></span>
        </button>
      </div>
    </div>
  {/if}
  <div class="form-group">
    <label class="form-label">Заметки</label>
    <input class="form-input" bind:value={fPayNotes} placeholder="…" />
  </div>
  <div class="form-actions">
    <button class="btn-primary" on:click={savePayment}>
      {fPayPaid ? 'Записать' : 'Запланировать'}
    </button>
  </div>
</Modal>

<style>
  .page-shell {
    max-width: 480px;
    margin: 0 auto;
    padding: 0 1.375rem 6rem;
    min-height: 100dvh;
  }

  .page-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 1rem 0 0.75rem;
  }

  .header-text { flex: 1; display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; }

  .page-title {
    font-family: "Fraunces", serif;
    font-size: 1.75rem;
    font-weight: 300;
    color: var(--color-text);
    margin: 0;
    letter-spacing: -0.02em;
  }

  .back-btn {
    background: none; border: none; color: var(--color-accent);
    cursor: pointer; padding: 0.25rem; -webkit-tap-highlight-color: transparent;
  }

  .icon-btn {
    background: none; border: none; cursor: pointer;
    color: var(--color-muted); padding: 0.25rem;
    width: 1.75rem; height: 1.75rem; -webkit-tap-highlight-color: transparent;
  }
  .icon-btn :global(svg) { width: 100%; height: 100%; }

  .fab-inline {
    width: 2.25rem; height: 2.25rem; border-radius: 50%;
    background: var(--color-accent); color: white; border: none;
    cursor: pointer; display: flex; align-items: center; justify-content: center;
    padding: 0.55rem; -webkit-tap-highlight-color: transparent; flex-shrink: 0;
  }
  .fab-inline :global(svg) { width: 100%; height: 100%; }
  .fab-inline:active { opacity: 0.8; }

  /* ── Summary ── */
  .summary-card {
    background: var(--color-accent);
    border-radius: 1.25rem;
    padding: 1.25rem;
    margin-bottom: 1rem;
  }

  .summary-row { display: flex; justify-content: space-between; align-items: flex-end; }

  .summary-label { display: block; font-size: 0.75rem; color: rgba(255,255,255,0.7); margin-bottom: 0.125rem; }
  .summary-amount {
    font-family: "Fraunces", serif;
    font-size: 2rem; font-weight: 300;
    color: white; letter-spacing: -0.02em; line-height: 1;
    display: block;
  }
  .summary-monthly { text-align: right; }
  .summary-monthly-val { font-size: 1.125rem; color: rgba(255,255,255,0.9); font-weight: 500; display: block; }

  /* ── Complex badge ── */
  .complex-badge {
    font-size: 0.625rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--color-accent);
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.375rem;
    padding: 0.125rem 0.4rem;
    flex-shrink: 0;
  }

  /* ── Credit list ── */
  .credit-list { display: flex; flex-direction: column; gap: 0.75rem; }

  .credit-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 1rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    transition: opacity 0.15s;
  }
  .credit-card:active { opacity: 0.8; }

  .credit-top {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: 0.75rem;
    gap: 0.5rem;
  }

  .credit-name-row { display: flex; align-items: center; gap: 0.5rem; flex: 1; }
  .credit-name { font-size: 1rem; font-weight: 500; color: var(--color-text); font-family: "Fraunces", serif; }
  .credit-remaining { font-size: 1rem; font-weight: 600; color: var(--color-text); font-family: "JetBrains Mono", monospace; flex-shrink: 0; }

  /* ── Progress ── */
  .progress-bar {
    height: 4px; background: var(--color-border);
    border-radius: 2px; overflow: hidden; margin-bottom: 0.375rem;
  }
  .progress-bar.big { height: 6px; margin-bottom: 0.875rem; }
  .progress-fill { height: 100%; background: var(--color-accent); border-radius: 2px; transition: width 0.4s; }

  .progress-labels {
    display: flex; justify-content: space-between;
    font-size: 0.6875rem; color: var(--color-muted); margin-bottom: 0.625rem;
  }

  /* ── Meta chips ── */
  .credit-meta { display: flex; gap: 0.375rem; flex-wrap: wrap; }

  .meta-chip {
    font-size: 0.75rem; color: var(--color-muted);
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 999px;
    padding: 0.1875rem 0.625rem;
  }
  .meta-chip.urgent { color: #e65100; border-color: #e6510030; background: #e6510010; }
  .meta-chip.overdue { color: #e53935; border-color: #e5393530; background: #e5393510; }

  /* ── Detail hero ── */
  .detail-hero {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 1.25rem;
    margin-bottom: 1.25rem;
  }

  .hero-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 0.5rem; }

  .sparkline { flex-shrink: 0; opacity: 0.8; }

  .detail-remaining-label { font-size: 0.75rem; color: var(--color-muted); display: block; }
  .detail-remaining-amount {
    font-family: "Fraunces", serif;
    font-size: 2.25rem; font-weight: 300;
    color: var(--color-text); letter-spacing: -0.02em; line-height: 1.1; display: block;
  }
  .detail-total-sub { font-size: 0.8125rem; color: var(--color-muted); display: block; margin-bottom: 0.875rem; }

  .detail-meta-row { display: flex; gap: 1.25rem; flex-wrap: wrap; }
  .detail-meta-block { display: flex; flex-direction: column; gap: 2px; }
  .detail-meta-label { font-size: 0.6875rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .detail-meta-val { font-size: 0.9375rem; color: var(--color-text); font-weight: 500; }
  .detail-meta-val.urgent { color: #e65100; }
  .detail-meta-val.overdue { color: #e53935; }

  .detail-notes { font-size: 0.8125rem; color: var(--color-muted); margin: 0.75rem 0 0; font-style: italic; }

  /* ── Section header ── */
  .section-row { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; }
  .section-label { flex: 1; font-size: 0.75rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.06em; margin: 0; }

  .add-pay-btn {
    background: none; border: none; cursor: pointer;
    font-size: 0.875rem; color: var(--color-accent);
    padding: 0; -webkit-tap-highlight-color: transparent; font-family: inherit;
  }
  .add-pay-btn:active { opacity: 0.6; }

  /* ── Month groups ── */
  .month-group { margin-bottom: 1rem; }
  .month-header {
    display: flex; justify-content: space-between; align-items: baseline;
    margin-bottom: 0.375rem;
  }
  .month-label { font-size: 0.8125rem; color: var(--color-muted); font-weight: 500; }
  .month-sum { font-size: 0.8125rem; color: var(--color-muted); font-family: "JetBrains Mono", monospace; }

  /* ── Payments ── */
  .payment-list { display: flex; flex-direction: column; gap: 0.5rem; }
  .mb-4 { margin-bottom: 1rem; }

  .payment-row {
    display: flex; align-items: center; gap: 0.75rem;
    padding: 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
  }
  .payment-row.upcoming { border-color: var(--color-accent); border-style: dashed; }

  .payment-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .payment-amount { font-size: 1rem; color: var(--color-text); font-weight: 500; }
  .payment-date { font-size: 0.75rem; color: var(--color-muted); }
  .payment-note { font-size: 0.75rem; color: var(--color-muted); font-style: italic; }

  .urgent-text { color: #e65100; }
  .overdue-text { color: #e53935; }

  .pay-btn {
    padding: 0.375rem 0.75rem;
    background: var(--color-accent); color: white;
    border: none; border-radius: 0.625rem;
    font-size: 0.8125rem; cursor: pointer;
    font-family: inherit; -webkit-tap-highlight-color: transparent; flex-shrink: 0;
  }
  .pay-btn:active { opacity: 0.8; }

  .delete-btn-sm {
    background: none; border: none; cursor: pointer;
    color: var(--color-muted); font-size: 1.125rem; line-height: 1;
    width: 1.5rem; height: 1.5rem;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0; -webkit-tap-highlight-color: transparent;
  }
  .delete-btn-sm:active { opacity: 0.5; }

  /* ── Toggle switch ── */
  .toggle-row { display: flex; align-items: center; gap: 0.75rem; }
  .toggle-text { flex: 1; }
  .toggle-label { font-size: 0.9375rem; color: var(--color-text); display: block; }
  .toggle-sub { font-size: 0.75rem; color: var(--color-muted); display: block; margin-top: 1px; }

  .toggle-btn {
    width: 2.75rem; height: 1.5rem;
    border-radius: 999px;
    background: var(--color-border);
    border: none; cursor: pointer; position: relative;
    transition: background 0.2s;
    -webkit-tap-highlight-color: transparent;
    flex-shrink: 0;
    padding: 0;
  }
  .toggle-btn.on { background: var(--color-accent); }

  .toggle-knob {
    position: absolute;
    top: 2px; left: 2px;
    width: 1.25rem; height: 1.25rem;
    border-radius: 50%;
    background: white;
    transition: transform 0.2s;
    box-shadow: 0 1px 3px rgba(0,0,0,0.2);
  }
  .toggle-btn.on .toggle-knob { transform: translateX(1.25rem); }

  /* ── Empty/hints ── */
  .empty-state { display: flex; flex-direction: column; align-items: center; gap: 0.75rem; padding: 3rem 1rem; }
  .empty-icon { width: 3rem; height: 3rem; color: var(--color-muted); }
  .empty-icon :global(svg) { width: 100%; height: 100%; }
  .empty-title { font-family: "Fraunces", serif; font-size: 1.25rem; font-weight: 300; color: var(--color-text); margin: 0; }
  .empty-sub { font-size: 0.875rem; color: var(--color-muted); margin: 0; }
  .muted-hint { color: var(--color-muted); font-size: 0.875rem; text-align: center; }

  /* ── Forms ── */
  .form-group { margin-bottom: 0.875rem; }
  .form-label { display: block; font-size: 0.8125rem; color: var(--color-muted); margin-bottom: 0.375rem; }
  .form-input {
    width: 100%; padding: 0.625rem 0.75rem;
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 0.75rem; font-size: 0.9375rem; color: var(--color-text);
    font-family: inherit; box-sizing: border-box; -webkit-appearance: none;
  }
  .form-input:focus { outline: none; border-color: var(--color-accent); }
  .form-row { display: flex; gap: 0.75rem; }
  .form-actions { display: flex; gap: 0.625rem; justify-content: flex-end; margin-top: 0.5rem; }

  .btn-primary {
    padding: 0.625rem 1.25rem; background: var(--color-accent); color: white;
    border: none; border-radius: 0.75rem; font-size: 0.9375rem; cursor: pointer;
    font-family: inherit; -webkit-tap-highlight-color: transparent;
  }
  .btn-primary:active { opacity: 0.8; }

  .btn-danger {
    padding: 0.625rem 1rem; background: none; color: #e53935;
    border: 1px solid #e53935; border-radius: 0.75rem; font-size: 0.9375rem;
    cursor: pointer; font-family: inherit; -webkit-tap-highlight-color: transparent;
  }
  .btn-danger:active { opacity: 0.7; }
</style>
