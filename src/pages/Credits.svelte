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
  */

  import { onMount } from 'svelte'
  import { supabase, today } from '../lib/supabase'
  import { user } from '../stores/user'
  import { icons } from '../lib/icons'
  import Modal from '../components/ui/Modal.svelte'
  import { showToast } from '../stores/toast'
  import type { Credit, CreditPayment } from '../lib/types'

  const todayDate = today()
  const RU_MONTHS = ['янв','фев','мар','апр','мая','июн','июл','авг','сен','окт','ноя','дек']

  function fmt(d: string | null | undefined): string {
    if (!d) return ''
    const p = d.split('-')
    return p.length < 3 ? '' : `${parseInt(p[2])} ${RU_MONTHS[parseInt(p[1]) - 1]} ${p[0]}`
  }

  function nextPaymentDate(paymentDay: number | null): string | null {
    if (!paymentDay) return null
    const now = new Date()
    const y = now.getFullYear()
    const m = now.getMonth()
    const d = now.getDate()
    // this month's payment date
    const thisMonth = new Date(y, m, paymentDay)
    if (thisMonth.getDate() !== paymentDay) {
      // day doesn't exist in this month (e.g. 31 in April) → use last day
      thisMonth.setDate(0)
    }
    const candidate = d <= paymentDay ? thisMonth : new Date(y, m + 1, paymentDay)
    return candidate.toISOString().slice(0, 10)
  }

  function daysUntil(dateStr: string | null): number | null {
    if (!dateStr) return null
    const diff = new Date(dateStr + 'T12:00:00').getTime() - new Date(todayDate + 'T12:00:00').getTime()
    return Math.round(diff / 86400000)
  }

  function daysUntilLabel(d: number | null): string {
    if (d === null) return ''
    if (d === 0) return 'сегодня'
    if (d === 1) return 'завтра'
    if (d < 0) return `${Math.abs(d)} дн. назад`
    return `через ${d} дн.`
  }

  function paidPct(c: Credit): number {
    if (!c.total_amount) return 0
    return Math.min(100, Math.round(((c.total_amount - c.remaining) / c.total_amount) * 100))
  }

  function totalRemaining(cs: Credit[]): number {
    return cs.reduce((s, c) => s + c.remaining, 0)
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
  let fNotes = ''

  // ── Payment form ───────────────────────────────────────────────────────────
  let fPayDate = todayDate
  let fPayAmount = ''
  let fPayNotes = ''

  // ── Derived ───────────────────────────────────────────────────────────────
  $: activePayments = payments.filter(p => p.credit_id === activeCredit?.id)
    .sort((a, b) => b.date.localeCompare(a.date))

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
    activeCredit = c
    view = 'detail'
    await loadPayments(c.id)
  }

  function backToList() { view = 'list'; activeCredit = null }

  // ── Credit CRUD ────────────────────────────────────────────────────────────
  function openNewCredit() {
    editingCredit = null
    fName = ''; fTotal = ''; fRemaining = ''; fMonthly = ''; fPaymentDay = ''
    fStartDate = todayDate; fEndDate = ''; fNotes = ''
    showCreditModal = true
  }

  function openEditCredit(c: Credit) {
    editingCredit = c
    fName = c.name
    fTotal = String(c.total_amount)
    fRemaining = String(c.remaining)
    fMonthly = c.monthly_payment != null ? String(c.monthly_payment) : ''
    fPaymentDay = c.payment_day != null ? String(c.payment_day) : ''
    fStartDate = c.start_date
    fEndDate = c.end_date ?? ''
    fNotes = c.notes ?? ''
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
      notes: fNotes.trim() || null,
    }
    if (editingCredit) {
      const { data } = await supabase.from('credits').update(payload).eq('id', editingCredit.id).select().single()
      if (data) {
        credits = credits.map(c => c.id === data.id ? data : c)
        if (activeCredit?.id === data.id) activeCredit = data
      }
    } else {
      const { data } = await supabase.from('credits').insert(payload).select().single()
      if (data) credits = [...credits, data]
    }
    showCreditModal = false
  }

  async function deleteCredit(id: string) {
    await supabase.from('credits').delete().eq('id', id)
    credits = credits.filter(c => c.id !== id)
    showCreditModal = false
    backToList()
    showToast('Кредит удалён', 'success')
  }

  // ── Payment CRUD ───────────────────────────────────────────────────────────
  function openAddPayment() {
    fPayDate = todayDate
    fPayAmount = activeCredit?.monthly_payment ? String(activeCredit.monthly_payment) : ''
    fPayNotes = ''
    showPaymentModal = true
  }

  async function savePayment() {
    if (!fPayAmount || !activeCredit) return
    const amount = parseFloat(fPayAmount)
    const newRemaining = Math.max(0, activeCredit.remaining - amount)

    const { data } = await supabase.from('credit_payments').insert({
      user_id: $user!.id,
      credit_id: activeCredit.id,
      date: fPayDate,
      amount,
      paid: true,
      notes: fPayNotes.trim() || null,
    }).select().single()
    if (data) payments = [data, ...payments]

    // update remaining on credit
    const { data: updated } = await supabase.from('credits')
      .update({ remaining: newRemaining }).eq('id', activeCredit.id).select().single()
    if (updated) {
      credits = credits.map(c => c.id === updated.id ? updated : c)
      activeCredit = updated
    }
    showPaymentModal = false
    showToast('Платёж записан', 'success')
  }

  async function deletePayment(p: CreditPayment) {
    // restore remaining
    if (activeCredit) {
      const restored = activeCredit.remaining + p.amount
      const { data: updated } = await supabase.from('credits')
        .update({ remaining: restored }).eq('id', activeCredit.id).select().single()
      if (updated) {
        credits = credits.map(c => c.id === updated.id ? updated : c)
        activeCredit = updated
      }
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
      <!-- Total summary -->
      <div class="summary-card">
        <span class="summary-label">Общий долг</span>
        <span class="summary-amount">{totalRemaining(credits).toLocaleString('ru')} ₽</span>
        <span class="summary-sub">{credits.length} {credits.length === 1 ? 'кредит' : credits.length < 5 ? 'кредита' : 'кредитов'}</span>
      </div>

      <div class="credit-list">
        {#each credits as credit}
          {@const pct = paidPct(credit)}
          {@const nextDate = nextPaymentDate(credit.payment_day)}
          {@const days = daysUntil(nextDate)}
          <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
          <div class="credit-card" on:click={() => openDetail(credit)}>
            <div class="credit-top">
              <span class="credit-name">{credit.name}</span>
              <span class="credit-remaining">{credit.remaining.toLocaleString('ru')} ₽</span>
            </div>

            <div class="progress-bar">
              <div class="progress-fill" style="width:{pct}%"></div>
            </div>
            <div class="progress-labels">
              <span class="progress-pct">{pct}% выплачено</span>
              <span class="progress-total">из {credit.total_amount.toLocaleString('ru')} ₽</span>
            </div>

            {#if credit.monthly_payment || nextDate}
              <div class="credit-meta">
                {#if credit.monthly_payment}
                  <span class="meta-chip">{credit.monthly_payment.toLocaleString('ru')} ₽/мес</span>
                {/if}
                {#if nextDate && days !== null}
                  <span class="meta-chip" class:urgent={days <= 3 && days >= 0}>
                    {#if days === 0}платёж сегодня
                    {:else if days === 1}платёж завтра
                    {:else if days < 0}просрочен {Math.abs(days)} дн.
                    {:else}платёж {fmt(nextDate)}
                    {/if}
                  </span>
                {/if}
              </div>
            {/if}
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

  <div class="page-shell">
    <header class="page-header">
      <button class="back-btn" on:click={backToList} aria-label="Назад">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M15 18l-6-6 6-6"/>
        </svg>
      </button>
      <div class="header-text">
        <h1 class="page-title" style="font-size:1.25rem">{activeCredit.name}</h1>
      </div>
      <button class="icon-btn" on:click={() => activeCredit && openEditCredit(activeCredit)} aria-label="Редактировать">
        {@html icons.edit}
      </button>
    </header>

    <!-- Hero block -->
    <div class="detail-hero">
      <div class="detail-remaining">
        <span class="detail-remaining-label">Осталось</span>
        <span class="detail-remaining-amount">{activeCredit.remaining.toLocaleString('ru')} ₽</span>
      </div>
      <div class="detail-total-row">
        <span>из {activeCredit.total_amount.toLocaleString('ru')} ₽</span>
        <span>· {pct}% выплачено</span>
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
        {#if activeCredit.payment_day}
          <div class="detail-meta-block">
            <span class="detail-meta-label">Число</span>
            <span class="detail-meta-val">{activeCredit.payment_day}</span>
          </div>
        {/if}
        {#if nextDate}
          <div class="detail-meta-block">
            <span class="detail-meta-label">Следующий</span>
            <span class="detail-meta-val" class:urgent={days !== null && days <= 3 && days >= 0}>
              {daysUntilLabel(days)}
            </span>
          </div>
        {/if}
        {#if activeCredit.end_date}
          <div class="detail-meta-block">
            <span class="detail-meta-label">До</span>
            <span class="detail-meta-val">{fmt(activeCredit.end_date)}</span>
          </div>
        {/if}
      </div>

      {#if activeCredit.notes}
        <p class="detail-notes">{activeCredit.notes}</p>
      {/if}
    </div>

    <!-- Payment history -->
    <div class="section-row">
      <p class="section-label">История платежей</p>
      <button class="add-pay-btn" on:click={openAddPayment}>+ Внести платёж</button>
    </div>

    {#if activePayments.length === 0}
      <p class="muted-hint" style="margin-top:0.75rem">Нет платежей</p>
    {:else}
      <div class="payment-list">
        {#each activePayments as p}
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
    {/if}
  </div>
{/if}

<!-- ══════════════════════════════════════════════════════════ MODALS ══ -->

<!-- Credit modal -->
<Modal title={editingCredit ? 'Редактировать кредит' : 'Новый кредит'} open={showCreditModal} on:close={() => showCreditModal = false}>
  <div class="form-group">
    <label class="form-label">Название *</label>
    <input class="form-input" bind:value={fName} placeholder="Ипотека, Автокредит, Долг Пете…" />
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

<!-- Payment modal -->
<Modal title="Внести платёж" open={showPaymentModal} on:close={() => showPaymentModal = false}>
  <div class="form-group">
    <label class="form-label">Сумма *</label>
    <input class="form-input" type="number" bind:value={fPayAmount} placeholder="15 000" />
  </div>
  <div class="form-group">
    <label class="form-label">Дата</label>
    <input class="form-input" type="date" bind:value={fPayDate} />
  </div>
  <div class="form-group">
    <label class="form-label">Заметки</label>
    <input class="form-input" bind:value={fPayNotes} placeholder="…" />
  </div>
  <div class="form-actions">
    <button class="btn-primary" on:click={savePayment}>Записать</button>
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

  .header-text { flex: 1; }

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
    cursor: pointer; padding: 0.25rem;
    -webkit-tap-highlight-color: transparent;
  }

  .icon-btn {
    background: none; border: none; cursor: pointer;
    color: var(--color-muted); padding: 0.25rem;
    width: 1.75rem; height: 1.75rem;
    -webkit-tap-highlight-color: transparent;
  }
  .icon-btn :global(svg) { width: 100%; height: 100%; }

  .fab-inline {
    width: 2.25rem; height: 2.25rem;
    border-radius: 50%;
    background: var(--color-accent);
    color: white; border: none;
    cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    padding: 0.55rem;
    -webkit-tap-highlight-color: transparent;
    flex-shrink: 0;
  }
  .fab-inline :global(svg) { width: 100%; height: 100%; }
  .fab-inline:active { opacity: 0.8; }

  /* ── Summary ── */
  .summary-card {
    background: var(--color-accent);
    border-radius: 1.25rem;
    padding: 1.25rem;
    margin-bottom: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .summary-label { font-size: 0.8125rem; color: rgba(255,255,255,0.75); }
  .summary-amount {
    font-family: "Fraunces", serif;
    font-size: 2rem;
    font-weight: 300;
    color: white;
    letter-spacing: -0.02em;
    line-height: 1;
  }
  .summary-sub { font-size: 0.75rem; color: rgba(255,255,255,0.6); }

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
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: 0.75rem;
    gap: 0.5rem;
  }

  .credit-name {
    font-size: 1rem;
    font-weight: 500;
    color: var(--color-text);
    font-family: "Fraunces", serif;
  }

  .credit-remaining {
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-text);
    font-family: "JetBrains Mono", monospace;
    flex-shrink: 0;
  }

  /* ── Progress bar ── */
  .progress-bar {
    height: 4px;
    background: var(--color-border);
    border-radius: 2px;
    overflow: hidden;
    margin-bottom: 0.375rem;
  }
  .progress-bar.big { height: 6px; margin-bottom: 0.75rem; }

  .progress-fill {
    height: 100%;
    background: var(--color-accent);
    border-radius: 2px;
    transition: width 0.4s;
  }

  .progress-labels {
    display: flex;
    justify-content: space-between;
    font-size: 0.6875rem;
    color: var(--color-muted);
    margin-bottom: 0.625rem;
  }

  /* ── Meta chips ── */
  .credit-meta { display: flex; gap: 0.375rem; flex-wrap: wrap; margin-top: 0.25rem; }

  .meta-chip {
    font-size: 0.75rem;
    color: var(--color-muted);
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 999px;
    padding: 0.1875rem 0.625rem;
  }
  .meta-chip.urgent { color: #e53935; border-color: #e5393540; background: #e5393510; }

  /* ── Detail hero ── */
  .detail-hero {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 1.25rem;
    margin-bottom: 1.25rem;
  }

  .detail-remaining { margin-bottom: 0.25rem; }
  .detail-remaining-label { font-size: 0.75rem; color: var(--color-muted); display: block; }
  .detail-remaining-amount {
    font-family: "Fraunces", serif;
    font-size: 2.25rem;
    font-weight: 300;
    color: var(--color-text);
    letter-spacing: -0.02em;
    line-height: 1.1;
  }

  .detail-total-row {
    font-size: 0.8125rem;
    color: var(--color-muted);
    margin-bottom: 1rem;
    display: flex;
    gap: 0.5rem;
  }

  .detail-meta-row {
    display: flex;
    gap: 1rem;
    flex-wrap: wrap;
  }

  .detail-meta-block {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .detail-meta-label { font-size: 0.6875rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.05em; }
  .detail-meta-val { font-size: 0.9375rem; color: var(--color-text); font-weight: 500; }
  .detail-meta-val.urgent { color: #e53935; }

  .detail-notes {
    font-size: 0.8125rem;
    color: var(--color-muted);
    margin: 0.75rem 0 0;
    font-style: italic;
  }

  /* ── Payments ── */
  .section-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
  }

  .section-label {
    flex: 1;
    font-size: 0.8125rem;
    color: var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    margin: 0;
  }

  .add-pay-btn {
    background: none; border: none; cursor: pointer;
    font-size: 0.875rem; color: var(--color-accent);
    padding: 0; -webkit-tap-highlight-color: transparent;
    font-family: inherit;
  }
  .add-pay-btn:active { opacity: 0.6; }

  .payment-list { display: flex; flex-direction: column; gap: 0.5rem; }

  .payment-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
  }

  .payment-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .payment-amount { font-size: 1rem; color: var(--color-text); font-weight: 500; }
  .payment-date { font-size: 0.75rem; color: var(--color-muted); }
  .payment-note { font-size: 0.75rem; color: var(--color-muted); font-style: italic; }

  .delete-btn-sm {
    background: none; border: none; cursor: pointer;
    color: var(--color-muted); font-size: 1.125rem; line-height: 1;
    width: 1.5rem; height: 1.5rem;
    display: flex; align-items: center; justify-content: center;
    flex-shrink: 0; -webkit-tap-highlight-color: transparent;
  }
  .delete-btn-sm:active { opacity: 0.5; }

  /* ── Empty / hints ── */
  .empty-state {
    display: flex; flex-direction: column;
    align-items: center; gap: 0.75rem;
    padding: 3rem 1rem;
  }

  .empty-icon { width: 3rem; height: 3rem; color: var(--color-muted); }
  .empty-icon :global(svg) { width: 100%; height: 100%; }

  .empty-title {
    font-family: "Fraunces", serif;
    font-size: 1.25rem; font-weight: 300;
    color: var(--color-text); margin: 0;
  }
  .empty-sub { font-size: 0.875rem; color: var(--color-muted); margin: 0; }
  .muted-hint { color: var(--color-muted); font-size: 0.875rem; text-align: center; }

  /* ── Forms ── */
  .form-group { margin-bottom: 0.875rem; }
  .form-label { display: block; font-size: 0.8125rem; color: var(--color-muted); margin-bottom: 0.375rem; }
  .form-input {
    width: 100%; padding: 0.625rem 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    font-size: 0.9375rem; color: var(--color-text);
    font-family: inherit; box-sizing: border-box;
    -webkit-appearance: none;
  }
  .form-input:focus { outline: none; border-color: var(--color-accent); }
  .form-row { display: flex; gap: 0.75rem; }
  .form-actions { display: flex; gap: 0.625rem; justify-content: flex-end; margin-top: 0.5rem; }

  .btn-primary {
    padding: 0.625rem 1.25rem;
    background: var(--color-accent); color: white;
    border: none; border-radius: 0.75rem;
    font-size: 0.9375rem; cursor: pointer;
    font-family: inherit; -webkit-tap-highlight-color: transparent;
  }
  .btn-primary:active { opacity: 0.8; }

  .btn-danger {
    padding: 0.625rem 1rem;
    background: none; color: #e53935;
    border: 1px solid #e53935; border-radius: 0.75rem;
    font-size: 0.9375rem; cursor: pointer;
    font-family: inherit; -webkit-tap-highlight-color: transparent;
  }
  .btn-danger:active { opacity: 0.7; }
</style>
