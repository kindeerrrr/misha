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
  const CREDIT_COLORS = ['#4f8ef7','#f7994f','#52c97a','#f76f6f','#a78bfa','#fb923c','#38bdf8','#f472b6']

  function fmtNum(n: number): string {
    return Math.round(n).toLocaleString('ru-RU')
  }

  function parseNum(s: string): number {
    return parseFloat(s.replace(/\s/g, '').replace(',', '.')) || 0
  }

  function formatInput(s: string): string {
    const n = parseFloat(s.replace(/\s/g, '').replace(',', '.'))
    if (isNaN(n)) return s
    return Math.round(n).toLocaleString('ru-RU')
  }

  function fmt(d: string | null | undefined): string {
    if (!d) return ''
    const p = d.split('-')
    return p.length < 3 ? '' : `${parseInt(p[2])} ${RU_MONTHS_SHORT[parseInt(p[1]) - 1]} ${p[0]}`
  }

  function monthLabel(key: string): string {
    const [y, m] = key.split('-')
    return `${RU_MONTHS_FULL[parseInt(m) - 1]} ${y}`
  }

  function localDateStr(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }

  function nextPaymentDate(paymentDay: number | null): string | null {
    if (!paymentDay) return null
    const now = new Date()
    const y = now.getFullYear(), m = now.getMonth(), d = now.getDate()
    const clamp = (yr: number, mo: number, day: number) =>
      Math.min(day, new Date(yr, mo + 1, 0).getDate())
    if (d <= paymentDay) return localDateStr(new Date(y, m, clamp(y, m, paymentDay)))
    return localDateStr(new Date(y, m + 1, clamp(y, m + 1, paymentDay)))
  }

  function daysUntil(dateStr: string | null): number | null {
    if (!dateStr) return null
    return Math.round((new Date(dateStr + 'T12:00:00').getTime() - new Date(todayDate + 'T12:00:00').getTime()) / 86400000)
  }

  function closureForecast(c: Credit): string | null {
    // Prefer end_date if it's set and in the future
    if (c.end_date) {
      const parts = c.end_date.split('-')
      if (parts.length === 3) {
        const endDate = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
        if (endDate >= new Date()) return `${RU_MONTHS_SHORT[endDate.getMonth()]} ${endDate.getFullYear()}`
      }
    }
    // Fallback: estimate from remaining / monthly
    if (!c.monthly_payment || c.monthly_payment <= 0 || c.remaining <= 0) return null
    const months = Math.ceil(c.remaining / c.monthly_payment)
    const d = new Date()
    d.setMonth(d.getMonth() + months - 1) // -1: current month counts as first payment
    return `${RU_MONTHS_SHORT[d.getMonth()]} ${d.getFullYear()}`
  }

  // Count payment dates remaining from today up to end_date
  function remainingPaymentsCount(c: Credit): number | null {
    if (!c.payment_day || !c.end_date) return null
    const now = new Date()
    const end = new Date(c.end_date + 'T12:00:00')
    let count = 0
    let d = new Date(now.getFullYear(), now.getMonth(), c.payment_day)
    if (d.getTime() < now.setHours(0,0,0,0)) d = new Date(d.getFullYear(), d.getMonth() + 1, c.payment_day)
    while (d <= end) {
      count++
      d = new Date(d.getFullYear(), d.getMonth() + 1, c.payment_day)
    }
    return count
  }

  // Total to pay including interest = remaining payments × monthly
  function totalWithInterest(c: Credit): number | null {
    if (!c.monthly_payment) return null
    const count = remainingPaymentsCount(c)
    if (count === null) return null
    return count * c.monthly_payment
  }

  function paidPct(c: Credit): number {
    if (c.is_complex) {
      const total = complexTotalSum(c.id)
      if (total <= 0) return 0
      return Math.min(100, Math.round((complexPaidSum(c.id) / total) * 100))
    }
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
  type MainTab = 'credits' | 'payments' | 'analytics'
  let mainTab: MainTab = 'credits'
  let view: 'list' | 'detail' = 'list'
  let activeCredit: Credit | null = null
  let loading = true

  // ── Payments tab ───────────────────────────────────────────────────────────
  type PayFilter = 'week' | 'month' | 'all'
  let payFilter: PayFilter = 'week'

  type FlatPayment = { creditId: string; creditName: string; colorIdx: number; date: string; amount: number; paid: boolean; paymentId: string | null }

  $: allUpcomingFlat = (() => {
    const result: FlatPayment[] = []
    const creditIdx = new Map(credits.map((c, i) => [c.id, i]))

    // Simple credits: project from next payment date
    for (const c of credits) {
      if (c.is_complex || !c.monthly_payment || !c.payment_day) continue
      const now = new Date()
      const day = c.payment_day
      let d = new Date(now.getFullYear(), now.getMonth(), day)
      if (d.getTime() < now.setHours(0, 0, 0, 0)) d = new Date(d.getFullYear(), d.getMonth() + 1, day)
      const end = c.end_date ? new Date(c.end_date + 'T12:00:00') : null
      let count = 0
      while ((!end || d <= end) && count < 36) {
        result.push({ creditId: c.id, creditName: c.name, colorIdx: creditIdx.get(c.id) ?? 0, date: localDateStr(d), amount: c.monthly_payment!, paid: false, paymentId: null })
        d = new Date(d.getFullYear(), d.getMonth() + 1, day)
        count++
      }
    }

    // Complex credits: use actual unpaid scheduled payments
    for (const p of payments) {
      if (p.paid) continue
      const c = credits.find(x => x.id === p.credit_id)
      if (!c) continue
      result.push({ creditId: c.id, creditName: c.name, colorIdx: creditIdx.get(c.id) ?? 0, date: p.date, amount: p.amount, paid: false, paymentId: p.id })
    }

    return result.sort((a, b) => a.date.localeCompare(b.date))
  })()

  $: filteredPayments = (() => {
    const now = new Date(); now.setHours(0, 0, 0, 0)
    if (payFilter === 'all') return allUpcomingFlat
    let cutoff: Date
    if (payFilter === 'week') { cutoff = new Date(now); cutoff.setDate(cutoff.getDate() + 7) }
    else { cutoff = new Date(now.getFullYear(), now.getMonth() + 1, 0) } // last day of current month
    return allUpcomingFlat.filter(p => new Date(p.date + 'T12:00:00') <= cutoff)
  })()

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

  // Formatted display values for number inputs
  let fTotalDisplay = ''
  let fRemainingDisplay = ''
  let fMonthlyDisplay = ''

  // ── Payment form ───────────────────────────────────────────────────────────
  let fPayDate = todayDate
  let fPayAmount = ''
  let fPayAmountDisplay = ''
  let fPayPaid = true
  let fPayNotes = ''

  // ── Sort ──────────────────────────────────────────────────────────────────
  type SortMode = 'date' | 'name' | 'amount'
  let sortMode: SortMode = 'date'

  // ── Derived ───────────────────────────────────────────────────────────────
  $: activePayments = payments.filter(p => p.credit_id === activeCredit?.id)
  $: upcomingPayments = activePayments.filter(p => !p.paid).sort((a, b) => a.date.localeCompare(b.date))
  $: historyPayments = activePayments.filter(p => p.paid).sort((a, b) => b.date.localeCompare(a.date))
  $: historyByMonth = groupByMonth(historyPayments)
  // Next unpaid payment date for a complex credit (from payments array)
  function complexNextDate(creditId: string): string | null {
    return payments
      .filter(p => p.credit_id === creditId && !p.paid)
      .sort((a, b) => a.date.localeCompare(b.date))[0]?.date ?? null
  }

  // Sum of unpaid payments in the nearest upcoming month for a complex credit
  function complexMonthlySum(creditId: string): number {
    const upcoming = payments
      .filter(p => p.credit_id === creditId && !p.paid)
      .sort((a, b) => a.date.localeCompare(b.date))
    if (upcoming.length === 0) return 0
    const nearestMonth = upcoming[0].date.slice(0, 7)
    return upcoming.filter(p => p.date.slice(0, 7) === nearestMonth).reduce((s, p) => s + p.amount, 0)
  }

  // For complex credits: total = sum of ALL payments (paid + unpaid)
  function complexTotalSum(creditId: string): number {
    return payments.filter(p => p.credit_id === creditId).reduce((s, p) => s + p.amount, 0)
  }

  // For complex credits: paid = sum of paid payments
  function complexPaidSum(creditId: string): number {
    return payments.filter(p => p.credit_id === creditId && p.paid).reduce((s, p) => s + p.amount, 0)
  }

  $: totalRemaining = credits.reduce((s, c) => s + c.remaining, 0)
  // payments referenced directly so Svelte tracks the dependency
  $: totalMonthly = credits.reduce((s, c) => {
    if (c.is_complex) {
      const upcoming = payments
        .filter(p => p.credit_id === c.id && !p.paid)
        .sort((a, b) => a.date.localeCompare(b.date))
      if (upcoming.length === 0) return s
      const nm = upcoming[0].date.slice(0, 7)
      return s + upcoming.filter(p => p.date.slice(0, 7) === nm).reduce((sum, p) => sum + p.amount, 0)
    }
    return s + (c.monthly_payment ?? 0)
  }, 0)
  $: totalWithInterestAll = credits.reduce((s, c) => {
    const t = totalWithInterest(c)
    return s + (t !== null ? t : c.remaining)
  }, 0)
  $: sortedCredits = [...credits].sort((a, b) => {
    if (sortMode === 'name') return a.name.localeCompare(b.name, 'ru')
    if (sortMode === 'amount') return b.remaining - a.remaining
    // payments referenced directly so Svelte tracks the dependency
    const da = a.is_complex
      ? (payments.filter(p => p.credit_id === a.id && !p.paid).sort((x, y) => x.date.localeCompare(y.date))[0]?.date ?? null)
      : nextPaymentDate(a.payment_day)
    const db = b.is_complex
      ? (payments.filter(p => p.credit_id === b.id && !p.paid).sort((x, y) => x.date.localeCompare(y.date))[0]?.date ?? null)
      : nextPaymentDate(b.payment_day)
    if (!da && !db) return 0
    if (!da) return 1
    if (!db) return -1
    return da.localeCompare(db)
  })

  // ── Chart ──────────────────────────────────────────────────────────────────
  const BAR_W = 36, BAR_GAP = 6, CHART_H = 96
  const LINE_STEP = 52, LINE_H = 108

  $: chartData = (() => {
    if (credits.length === 0) return null
    const monthMap = new Map<string, Map<string, number>>()

    // Simple credits: project future payments from today to end_date
    for (const c of credits) {
      if (c.is_complex || !c.monthly_payment || !c.payment_day) continue
      const now = new Date()
      const day = c.payment_day
      let d = new Date(now.getFullYear(), now.getMonth(), day)
      if (d.getTime() < now.setHours(0, 0, 0, 0)) d = new Date(d.getFullYear(), d.getMonth() + 1, day)
      const end = c.end_date ? new Date(c.end_date + 'T12:00:00') : null
      let count = 0
      while ((!end || d <= end) && count < 48) {
        const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
        if (!monthMap.has(k)) monthMap.set(k, new Map())
        monthMap.get(k)!.set(c.id, (monthMap.get(k)!.get(c.id) ?? 0) + c.monthly_payment!)
        d = new Date(d.getFullYear(), d.getMonth() + 1, day)
        count++
      }
    }

    // Complex credits: use actual unpaid scheduled payments
    for (const p of payments) {
      if (p.paid) continue
      const k = p.date.slice(0, 7)
      if (!monthMap.has(k)) monthMap.set(k, new Map())
      monthMap.get(k)!.set(p.credit_id, (monthMap.get(k)!.get(p.credit_id) ?? 0) + p.amount)
    }

    if (monthMap.size === 0) return null

    const sorted = Array.from(monthMap.entries()).sort(([a], [b]) => a.localeCompare(b))
    const maxTotal = Math.max(1, ...sorted.map(([, m]) => Array.from(m.values()).reduce((s, v) => s + v, 0)))
    const creditIdx = new Map(credits.map((c, i) => [c.id, i]))

    const bars = sorted.map(([key, segMap], i) => {
      const total = Array.from(segMap.values()).reduce((s, v) => s + v, 0)
      let yOff = CHART_H
      const segments = Array.from(segMap.entries()).map(([cid, amount]) => {
        const h = Math.max(2, (amount / maxTotal) * CHART_H)
        yOff -= h
        return { cid, amount, x: i * (BAR_W + BAR_GAP), y: yOff, w: BAR_W, h, color: CREDIT_COLORS[(creditIdx.get(cid) ?? 0) % CREDIT_COLORS.length] }
      })
      const mi = parseInt(key.slice(5, 7)) - 1
      const prevKey = i > 0 ? sorted[i - 1][0] : null
      return {
        key, segments, total,
        x: i * (BAR_W + BAR_GAP),
        label: RU_MONTHS_SHORT[mi],
        year: (!prevKey || prevKey.slice(0, 4) !== key.slice(0, 4)) ? `'${key.slice(2, 4)}` : '',
      }
    })

    return { bars, maxTotal, totalW: sorted.length * (BAR_W + BAR_GAP) }
  })()

  // ── Line chart: one line per credit ────────────────────────────────────────
  $: lineChartData = (() => {
    if (!chartData || chartData.bars.length === 0) return null
    const bars = chartData.bars
    const months = bars.map(b => b.key)
    const barMap = new Map(bars.map(b => [b.key, b]))
    const creditIdx = new Map(credits.map((c, i) => [c.id, i]))
    const PAD_TOP = 14, PAD_BOT = 6

    const lines = credits.map(c => {
      const amounts = months.map(month => {
        const seg = barMap.get(month)?.segments.find(s => s.cid === c.id)
        return seg?.amount ?? 0
      })
      if (!amounts.some(v => v > 0)) return null
      return { credit: c, amounts, colorIdx: creditIdx.get(c.id) ?? 0 }
    }).filter((l): l is NonNullable<typeof l> => l !== null)

    if (lines.length === 0) return null
    const maxVal = Math.max(1, ...lines.flatMap(l => l.amounts))

    const svgLines = lines.map(l => {
      let pathD = '', inLine = false, lastActiveI = 0
      l.amounts.forEach((v, i) => {
        const x = i * LINE_STEP + LINE_STEP / 2
        const y = PAD_TOP + (1 - v / maxVal) * (LINE_H - PAD_TOP - PAD_BOT)
        if (v > 0) {
          pathD += inLine ? ` L${x.toFixed(1)},${y.toFixed(1)}` : `M${x.toFixed(1)},${y.toFixed(1)}`
          inLine = true; lastActiveI = i
        } else { inLine = false }
      })
      const lastV = l.amounts[lastActiveI]
      const lastX = lastActiveI * LINE_STEP + LINE_STEP / 2
      const lastY = PAD_TOP + (1 - lastV / maxVal) * (LINE_H - PAD_TOP - PAD_BOT)
      return { ...l, pathD, lastX, lastY }
    })

    return { months, svgLines, maxVal, PAD_TOP, PAD_BOT, totalW: months.length * LINE_STEP }
  })()

  // ── Credit ranking ─────────────────────────────────────────────────────────
  $: creditRanking = (() => {
    const total = totalMonthly || 1
    return credits.map(c => {
      const monthly = c.is_complex
        ? (() => {
            const upcoming = payments.filter(p => p.credit_id === c.id && !p.paid).sort((a, b) => a.date.localeCompare(b.date))
            if (!upcoming.length) return 0
            const nm = upcoming[0].date.slice(0, 7)
            return upcoming.filter(p => p.date.slice(0, 7) === nm).reduce((s, p) => s + p.amount, 0)
          })()
        : (c.monthly_payment ?? 0)
      const monthsLeft = monthly > 0 ? Math.ceil(c.remaining / monthly) : null
      const pct = Math.round((monthly / total) * 100)
      return { credit: c, monthly, monthsLeft, pct, forecast: closureForecast(c), remaining: c.remaining }
    }).sort((a, b) => b.remaining - a.remaining)
  })()

  // ── Load ───────────────────────────────────────────────────────────────────
  async function load() {
    const { data: creditsData } = await supabase.from('credits')
      .select('*').eq('user_id', $user!.id).order('created_at')
    credits = creditsData ?? []
    // Pre-load payments for complex credits so list-view chips work immediately
    const complexIds = credits.filter(c => c.is_complex).map(c => c.id)
    if (complexIds.length > 0) {
      const { data: paymentsData } = await supabase.from('credit_payments')
        .select('*').in('credit_id', complexIds)
      payments = paymentsData ?? []
    }
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
    // Auto-sync remaining for complex credits in case payments were added before this feature
    if (c.is_complex) await syncRemaining(c.id, payments)
  }

  function backToList() { view = 'list'; activeCredit = null }

  // ── Credit CRUD ────────────────────────────────────────────────────────────
  function openNewCredit() {
    editingCredit = null
    fName = ''; fTotal = ''; fRemaining = ''; fMonthly = ''; fPaymentDay = ''
    fTotalDisplay = ''; fRemainingDisplay = ''; fMonthlyDisplay = ''
    fStartDate = todayDate; fEndDate = ''; fIsComplex = false; fNotes = ''
    showCreditModal = true
  }

  function openEditCredit(c: Credit) {
    editingCredit = c
    fName = c.name
    fTotal = String(c.total_amount); fTotalDisplay = fmtNum(c.total_amount)
    fRemaining = String(c.remaining); fRemainingDisplay = fmtNum(c.remaining)
    fMonthly = c.monthly_payment != null ? String(c.monthly_payment) : ''
    fMonthlyDisplay = c.monthly_payment != null ? fmtNum(c.monthly_payment) : ''
    fPaymentDay = c.payment_day != null ? String(c.payment_day) : ''
    fStartDate = c.start_date; fEndDate = c.end_date ?? ''
    fIsComplex = c.is_complex; fNotes = c.notes ?? ''
    showCreditModal = true
  }

  async function saveCredit() {
    const totalVal = parseNum(fTotalDisplay || fTotal)
    const remainingVal = parseNum(fRemainingDisplay || fRemaining)
    if (!fName.trim() || !totalVal || !remainingVal) return
    const monthlyVal = fMonthlyDisplay || fMonthly ? parseNum(fMonthlyDisplay || fMonthly) : null
    const payload = {
      user_id: $user!.id,
      name: fName.trim(),
      total_amount: totalVal,
      remaining: remainingVal,
      monthly_payment: monthlyVal || null,
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

  // ── Early repayment ────────────────────────────────────────────────────────
  let showEarlyModal = false
  let fEarlyAmount = ''
  let fEarlyAmountDisplay = ''
  let fEarlyDate = todayDate
  let fEarlyMode: 'term' | 'payment' = 'term' // уменьшить срок или платёж

  $: earlyAmount = parseNum(fEarlyAmountDisplay || fEarlyAmount)
  $: earlyNewRemaining = activeCredit ? Math.max(0, activeCredit.remaining - earlyAmount) : 0

  $: earlyPreview = (() => {
    if (!activeCredit || !earlyAmount || earlyAmount <= 0) return null
    const c = activeCredit
    const newRem = Math.max(0, c.remaining - earlyAmount)
    if (newRem <= 0) return { paid: true, label: 'Кредит будет полностью закрыт' }

    if (!c.monthly_payment) return null

    if (fEarlyMode === 'term') {
      // same monthly, fewer months
      const newMonths = Math.ceil(newRem / c.monthly_payment)
      const d = new Date()
      d.setMonth(d.getMonth() + newMonths)
      const newEnd = `${RU_MONTHS_SHORT[d.getMonth()]} ${d.getFullYear()}`
      const savedMonths = (earlyPaymentsLeft ?? 0) - newMonths
      return { paid: false, label: `Закроется ~${newEnd}`, sub: savedMonths > 0 ? `на ${savedMonths} мес. раньше` : null }
    } else {
      // same term, smaller monthly
      const months = earlyPaymentsLeft ?? Math.ceil(newRem / c.monthly_payment)
      if (months <= 0) return null
      const newMonthly = Math.ceil(newRem / months)
      const saved = c.monthly_payment - newMonthly
      return { paid: false, label: `Новый платёж ~${fmtNum(newMonthly)} ₽/мес`, sub: saved > 0 ? `экономия ${fmtNum(saved)} ₽/мес` : null }
    }
  })()

  // paymentsLeft is defined in the detail view block, need it here too
  $: earlyPaymentsLeft = activeCredit ? remainingPaymentsCount(activeCredit) : null

  function openEarlyRepayment() {
    fEarlyAmount = ''; fEarlyAmountDisplay = ''
    fEarlyDate = todayDate; fEarlyMode = 'term'
    showEarlyModal = true
  }

  async function saveEarlyRepayment() {
    if (!activeCredit || !earlyAmount) return
    const c = activeCredit
    const newRemaining = Math.max(0, c.remaining - earlyAmount)

    // Log as a payment
    const { data: payData } = await supabase.from('credit_payments').insert({
      user_id: $user!.id, credit_id: c.id,
      date: fEarlyDate, amount: earlyAmount, paid: true,
      notes: 'Досрочное погашение',
    }).select().single()
    if (payData) payments = [payData, ...payments]

    // Update remaining + optionally end_date or monthly_payment
    const update: Record<string, unknown> = { remaining: newRemaining }

    if (newRemaining <= 0) {
      update.remaining = 0
    } else if (c.monthly_payment && c.monthly_payment > 0) {
      if (fEarlyMode === 'term') {
        const newMonths = Math.ceil(newRemaining / c.monthly_payment)
        const d = new Date()
        d.setMonth(d.getMonth() + newMonths)
        // find the payment_day in that month
        const day = c.payment_day ?? 1
        const newEnd = new Date(d.getFullYear(), d.getMonth(), Math.min(day, new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()))
        update.end_date = newEnd.toISOString().slice(0, 10)
      } else {
        const months = earlyPaymentsLeft ?? Math.ceil(newRemaining / c.monthly_payment)
        if (months > 0) update.monthly_payment = Math.ceil(newRemaining / months)
      }
    }

    const { data: updated } = await supabase.from('credits').update(update).eq('id', c.id).select().single()
    if (updated) { credits = credits.map(x => x.id === updated.id ? updated : x); activeCredit = updated }

    showEarlyModal = false
    showToast(newRemaining <= 0 ? 'Кредит закрыт!' : 'Досрочный платёж внесён', 'success')
  }

  // ── Edit scheduled payment ─────────────────────────────────────────────────
  let showEditPaymentModal = false
  let editingPayment: CreditPayment | null = null
  let fEditDay = ''
  let fEditMonth = ''
  let fEditYear = ''
  let fEditAmount = ''
  let fEditAmountDisplay = ''
  let fEditNotes = ''

  $: fEditDate = (() => {
    const d = parseInt(fEditDay), m = parseInt(fEditMonth), y = parseInt(fEditYear)
    if (!d || !m || !y || y < 2020 || y > 2040 || m < 1 || m > 12 || d < 1 || d > 31 || fEditYear.length < 4) return ''
    return `${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`
  })()

  function openEditPayment(p: CreditPayment) {
    editingPayment = p
    const parts = p.date.split('-')
    fEditDay = parts[2] ?? ''
    fEditMonth = parts[1] ?? ''
    fEditYear = parts[0] ?? ''
    fEditAmount = String(p.amount)
    fEditAmountDisplay = fmtNum(p.amount)
    fEditNotes = p.notes ?? ''
    showEditPaymentModal = true
  }

  async function saveEditPayment() {
    if (!editingPayment || !fEditDate || !activeCredit) return
    const amount = parseNum(fEditAmountDisplay || fEditAmount)
    if (!amount) return
    const { data } = await supabase.from('credit_payments')
      .update({ date: fEditDate, amount, notes: fEditNotes.trim() || null })
      .eq('id', editingPayment.id).select().single()
    if (!data) return
    const newPayments = payments.map(x => x.id === data.id ? data : x)
    payments = newPayments
    if (activeCredit.is_complex) await syncRemaining(activeCredit.id, newPayments)
    showEditPaymentModal = false
    showToast('Сохранено', 'success')
  }

  // ── Payment CRUD ───────────────────────────────────────────────────────────
  function openAddPayment() {
    fPayDate = todayDate
    fPayAmount = activeCredit?.monthly_payment ? String(activeCredit.monthly_payment) : ''
    fPayAmountDisplay = activeCredit?.monthly_payment ? fmtNum(activeCredit.monthly_payment) : ''
    fPayPaid = !activeCredit?.is_complex
    fPayNotes = ''
    showPaymentModal = true
  }

  // For complex credits: remaining = sum of all unpaid payments
  async function syncRemaining(creditId: string, allPayments: CreditPayment[]) {
    const c = credits.find(x => x.id === creditId)
    if (!c) return
    let newRemaining: number
    if (c.is_complex) {
      newRemaining = allPayments.filter(p => p.credit_id === creditId && !p.paid).reduce((s, p) => s + p.amount, 0)
    } else {
      return // simple credits manage remaining manually
    }
    const { data: updated } = await supabase.from('credits')
      .update({ remaining: newRemaining }).eq('id', creditId).select().single()
    if (updated) { credits = credits.map(c => c.id === updated.id ? updated : c); if (activeCredit?.id === updated.id) activeCredit = updated }
  }

  async function savePayment() {
    if (!activeCredit) return
    const amount = parseNum(fPayAmountDisplay || fPayAmount)
    if (!amount) return
    const { data } = await supabase.from('credit_payments').insert({
      user_id: $user!.id, credit_id: activeCredit.id,
      date: fPayDate, amount, paid: fPayPaid, notes: fPayNotes.trim() || null,
    }).select().single()
    if (!data) return
    const newPayments = [data, ...payments]
    payments = newPayments

    if (activeCredit.is_complex) {
      await syncRemaining(activeCredit.id, newPayments)
    } else if (fPayPaid) {
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
    const newPayments = payments.map(x => x.id === p.id ? { ...x, paid: true } : x)
    payments = newPayments

    if (activeCredit.is_complex) {
      await syncRemaining(activeCredit.id, newPayments)
    } else {
      const newRemaining = Math.max(0, activeCredit.remaining - p.amount)
      const { data: updated } = await supabase.from('credits')
        .update({ remaining: newRemaining }).eq('id', activeCredit.id).select().single()
      if (updated) { credits = credits.map(c => c.id === updated.id ? updated : c); activeCredit = updated }
    }
    showToast('Оплачено', 'success')
  }

  async function deletePayment(p: CreditPayment) {
    await supabase.from('credit_payments').delete().eq('id', p.id)
    const newPayments = payments.filter(x => x.id !== p.id)
    payments = newPayments

    if (activeCredit?.is_complex) {
      await syncRemaining(activeCredit.id, newPayments)
    } else if (p.paid && activeCredit) {
      const restored = activeCredit.remaining + p.amount
      const { data: updated } = await supabase.from('credits')
        .update({ remaining: restored }).eq('id', activeCredit.id).select().single()
      if (updated) { credits = credits.map(c => c.id === updated.id ? updated : c); activeCredit = updated }
    }
  }

  // ── Bulk schedule (for complex credits) ───────────────────────────────────
  let showBulkModal = false
  let fBulkDay = ''
  let fBulkMonth = ''
  let fBulkYear = ''
  let fBulkAmount = ''
  let fBulkAmountDisplay = ''
  let fBulkCount = ''
  let fBulkInterval: 'month' | 'week' | 'day' = 'month'
  let fBulkPaid = false
  let bulkSaving = false

  $: fBulkStartDate = (() => {
    const d = parseInt(fBulkDay), m = parseInt(fBulkMonth), y = parseInt(fBulkYear)
    if (!d || !m || !y || y < 2020 || y > 2040 || m < 1 || m > 12 || d < 1 || d > 31 || fBulkYear.length < 4) return ''
    return `${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`
  })()

  $: bulkAmount = parseNum(fBulkAmountDisplay || fBulkAmount)
  $: bulkCount = parseInt(fBulkCount) || 0

  $: bulkPreviewDates = (() => {
    if (!fBulkStartDate || bulkCount <= 0 || bulkAmount <= 0) return []
    const dates: string[] = []
    let d = new Date(fBulkStartDate + 'T12:00:00')
    for (let i = 0; i < Math.min(bulkCount, 36); i++) {
      dates.push(localDateStr(d))
      if (fBulkInterval === 'month') d = new Date(d.getFullYear(), d.getMonth() + 1, d.getDate())
      else if (fBulkInterval === 'week') d = new Date(d.getTime() + 7 * 86400000)
      else d = new Date(d.getTime() + 86400000)
    }
    return dates
  })()

  function openBulkSchedule() {
    const now = new Date()
    fBulkDay = String(now.getDate()).padStart(2, '0')
    fBulkMonth = String(now.getMonth() + 1).padStart(2, '0')
    fBulkYear = String(now.getFullYear())
    fBulkAmount = activeCredit?.monthly_payment ? String(activeCredit.monthly_payment) : ''
    fBulkAmountDisplay = activeCredit?.monthly_payment ? fmtNum(activeCredit.monthly_payment) : ''
    fBulkCount = ''
    fBulkInterval = 'month'
    fBulkPaid = false
    showBulkModal = true
  }

  async function saveBulkSchedule() {
    if (!activeCredit || bulkPreviewDates.length === 0 || bulkAmount <= 0) return
    bulkSaving = true
    const rows = bulkPreviewDates.map(date => ({
      user_id: $user!.id,
      credit_id: activeCredit!.id,
      date,
      amount: bulkAmount,
      paid: fBulkPaid,
      notes: null,
    }))
    const { data } = await supabase.from('credit_payments').insert(rows).select()
    if (!data) { bulkSaving = false; return }
    const newPayments = [...data, ...payments]
    payments = newPayments
    await syncRemaining(activeCredit.id, newPayments)

    bulkSaving = false
    showBulkModal = false
    showToast(`${bulkPreviewDates.length} платежей добавлено`, 'success')
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
      {#if mainTab === 'credits'}
        <button class="fab-inline" on:click={openNewCredit} aria-label="Добавить">
          {@html icons.plus}
        </button>
      {/if}
    </header>

    <div class="main-tabs">
      <button class="main-tab" class:active={mainTab === 'credits'}   on:click={() => mainTab = 'credits'}>Кредиты</button>
      <button class="main-tab" class:active={mainTab === 'payments'}  on:click={() => mainTab = 'payments'}>Платежи</button>
      <button class="main-tab" class:active={mainTab === 'analytics'} on:click={() => mainTab = 'analytics'}>Аналитика</button>
    </div>

    <!-- ══ Вкладка: Кредиты ══ -->
    {#if mainTab === 'credits'}
      {#if credits.length > 1}
        <div class="sort-row">
          <button class="sort-chip" class:active={sortMode === 'date'}   on:click={() => sortMode = 'date'}>По дате</button>
          <button class="sort-chip" class:active={sortMode === 'name'}   on:click={() => sortMode = 'name'}>По алфавиту</button>
          <button class="sort-chip" class:active={sortMode === 'amount'} on:click={() => sortMode = 'amount'}>По сумме</button>
        </div>
      {/if}
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
              <span class="summary-label">Итого к выплате</span>
              <span class="summary-amount">{totalWithInterestAll.toLocaleString('ru-RU')} ₽</span>
              {#if totalWithInterestAll !== totalRemaining}
                <span class="summary-principal">тело долга {totalRemaining.toLocaleString('ru-RU')} ₽</span>
              {/if}
            </div>
            {#if totalMonthly > 0}
              <div class="summary-monthly">
                <span class="summary-label">В месяц</span>
                <span class="summary-monthly-val">{totalMonthly.toLocaleString('ru-RU')} ₽</span>
              </div>
            {/if}
          </div>
        </div>
        <div class="credit-list">
          {#each sortedCredits as credit}
            {@const pct = paidPct(credit)}
            {@const nextDate = credit.is_complex ? complexNextDate(credit.id) : nextPaymentDate(credit.payment_day)}
            {@const days = daysUntil(nextDate)}
            {@const forecast = closureForecast(credit)}
            {@const twi = credit.is_complex ? null : totalWithInterest(credit)}
            {@const cMonthly = credit.is_complex ? complexMonthlySum(credit.id) : 0}
            {@const cTotal = credit.is_complex ? complexTotalSum(credit.id) : credit.total_amount}
            <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
            <div class="credit-card" on:click={() => openDetail(credit)}>
              <div class="credit-top">
                <div class="credit-name-row">
                  <span class="credit-name">{credit.name}</span>
                  {#if credit.is_complex}<span class="complex-badge">Сплит</span>{/if}
                </div>
                <div class="credit-amounts">
                  <span class="credit-remaining">{(twi ?? credit.remaining).toLocaleString('ru-RU')} ₽</span>
                  {#if twi !== null && twi !== credit.remaining}
                    <span class="credit-principal">тело {credit.remaining.toLocaleString('ru-RU')} ₽</span>
                  {/if}
                </div>
              </div>
              <div class="progress-bar">
                <div class="progress-fill" style="width:{pct}%"></div>
              </div>
              <div class="progress-labels">
                <span>{pct}% выплачено</span>
                <span>из {cTotal.toLocaleString('ru-RU')} ₽</span>
              </div>
              <div class="credit-meta">
                {#if credit.is_complex && cMonthly > 0}
                  <span class="meta-chip">{cMonthly.toLocaleString('ru-RU')} ₽/мес</span>
                {:else if credit.monthly_payment}
                  <span class="meta-chip">{credit.monthly_payment.toLocaleString('ru-RU')} ₽/мес</span>
                {/if}
                {#if nextDate && days !== null}
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

    <!-- ══ Вкладка: Платежи ══ -->
    {:else if mainTab === 'payments'}
      <div class="sort-row">
        <button class="sort-chip" class:active={payFilter === 'week'}  on:click={() => payFilter = 'week'}>Неделя</button>
        <button class="sort-chip" class:active={payFilter === 'month'} on:click={() => payFilter = 'month'}>Месяц</button>
        <button class="sort-chip" class:active={payFilter === 'all'}   on:click={() => payFilter = 'all'}>Все</button>
      </div>
      {#if filteredPayments.length === 0}
        <div class="empty-state">
          <p class="empty-title">Платежей нет</p>
          <p class="empty-sub">В выбранном периоде ничего не запланировано</p>
        </div>
      {:else}
        {@const totalPeriod = filteredPayments.reduce((s, p) => s + p.amount, 0)}
        <div class="pay-period-total">
          Итого за период: <strong>{totalPeriod.toLocaleString('ru-RU')} ₽</strong>
        </div>
        <div class="pay-flat-list">
          {#each filteredPayments as p}
            {@const d = daysUntil(p.date)}
            <div class="pay-flat-row" class:urgent={d !== null && d <= 3 && d >= 0} class:overdue={d !== null && d < 0}>
              <span class="pay-flat-dot" style="background:{CREDIT_COLORS[p.colorIdx % CREDIT_COLORS.length]}"></span>
              <div class="pay-flat-info">
                <span class="pay-flat-name">{p.creditName}</span>
                <span class="pay-flat-date">
                  {fmt(p.date)}
                  {#if d !== null}
                    · {d < 0 ? `просрочен ${Math.abs(d)} дн.` : d === 0 ? 'сегодня' : d === 1 ? 'завтра' : `через ${d} дн.`}
                  {/if}
                </span>
              </div>
              <span class="pay-flat-amount">{p.amount.toLocaleString('ru-RU')} ₽</span>
              {#if p.paymentId}
                {@const realP = payments.find(x => x.id === p.paymentId)}
                {#if realP}
                  <button class="pay-btn" on:click={() => markPaid(realP)}>Оплатить</button>
                {/if}
              {:else}
                {@const c = credits.find(x => x.id === p.creditId)}
                {#if c}
                  <button class="pay-btn outline" on:click={() => openDetail(c)}>Внести</button>
                {/if}
              {/if}
            </div>
          {/each}
        </div>
      {/if}

    <!-- ══ Вкладка: Аналитика ══ -->
    {:else if mainTab === 'analytics'}
      {#if !chartData || chartData.bars.length < 2}
        <div class="empty-state" style="padding-top:3rem">
          <p class="empty-title">Недостаточно данных</p>
          <p class="empty-sub">Добавь кредиты с расписанием платежей</p>
        </div>
      {:else}

        <!-- Линейный график: 1 линия = 1 кредит -->
        {#if lineChartData}
          <div class="chart-card">
            <p class="chart-title">Платёж по кредиту / месяц</p>
            <div class="chart-legend">
              {#each lineChartData.svgLines as l}
                <div class="legend-item">
                  <span class="legend-dot" style="background:{CREDIT_COLORS[l.colorIdx % CREDIT_COLORS.length]}"></span>
                  <span class="legend-name">{l.credit.name}</span>
                </div>
              {/each}
            </div>
            <div class="chart-scroll">
              <svg width={lineChartData.totalW} height={LINE_H + 28} style="display:block;overflow:visible">
                <!-- Grid lines -->
                {#each [0.5, 1] as frac}
                  {@const gy = lineChartData.PAD_TOP + (1 - frac) * (LINE_H - lineChartData.PAD_TOP - lineChartData.PAD_BOT)}
                  <line x1="0" y1={gy} x2={lineChartData.totalW} y2={gy} stroke="var(--color-border)" stroke-width="1"/>
                  <text x="2" y={gy - 2} class="chart-yr">{fmtNum(lineChartData.maxVal * frac / 1000)}к</text>
                {/each}
                <!-- Lines -->
                {#each lineChartData.svgLines as l}
                  {@const color = CREDIT_COLORS[l.colorIdx % CREDIT_COLORS.length]}
                  <path d={l.pathD} stroke={color} stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round" opacity="0.9"/>
                  <circle cx={l.lastX} cy={l.lastY} r="3.5" fill={color}/>
                {/each}
                <!-- Month labels -->
                {#each lineChartData.months as month, i}
                  {@const mi = parseInt(month.slice(5,7)) - 1}
                  {@const prev = lineChartData.months[i - 1]}
                  <text x={i * LINE_STEP + LINE_STEP / 2} y={LINE_H + 14} text-anchor="middle" class="chart-lbl">{RU_MONTHS_SHORT[mi]}</text>
                  {#if !prev || prev.slice(0,4) !== month.slice(0,4)}
                    <text x={i * LINE_STEP + LINE_STEP / 2} y={LINE_H + 24} text-anchor="middle" class="chart-yr">'{month.slice(2,4)}</text>
                  {/if}
                {/each}
              </svg>
            </div>
          </div>
        {/if}

        <!-- Стековый бар: итого в месяц -->
        <div class="chart-card">
          <p class="chart-title">Итоговая нагрузка в месяц</p>
          <div class="chart-legend">
            {#each credits as c, i}
              <div class="legend-item">
                <span class="legend-dot" style="background:{CREDIT_COLORS[i % CREDIT_COLORS.length]}"></span>
                <span class="legend-name">{c.name}</span>
              </div>
            {/each}
          </div>
          <div class="chart-scroll">
            <svg width={chartData.totalW} height={CHART_H + 30} style="display:block;overflow:visible">
              {#each chartData.bars as bar}
                {#each bar.segments as seg}
                  <rect x={seg.x} y={seg.y} width={seg.w} height={seg.h} fill={seg.color} rx="2" opacity="0.85"/>
                {/each}
                {#if bar.segments.length > 0}
                  <text x={bar.x + BAR_W / 2} y={bar.segments[0].y - 3} text-anchor="middle" class="chart-yr">{fmtNum(bar.total / 1000)}к</text>
                {/if}
                <text x={bar.x + BAR_W / 2} y={CHART_H + 13} text-anchor="middle" class="chart-lbl">{bar.label}</text>
                {#if bar.year}
                  <text x={bar.x + BAR_W / 2} y={CHART_H + 24} text-anchor="middle" class="chart-yr">{bar.year}</text>
                {/if}
              {/each}
            </svg>
          </div>
        </div>

        <!-- Рейтинг нагрузки -->
        <div class="chart-card">
          <p class="chart-title">Рейтинг по долгу</p>
          <div class="ranking-list">
            {#each creditRanking as item, i}
              {@const color = CREDIT_COLORS[i % CREDIT_COLORS.length]}
              <div class="ranking-row">
                <div class="ranking-top">
                  <div class="ranking-name-row">
                    <span class="ranking-dot" style="background:{color}"></span>
                    <span class="ranking-name">{item.credit.name}</span>
                  </div>
                  <span class="ranking-remaining">{fmtNum(item.remaining)} ₽</span>
                </div>
                <div class="ranking-bar-wrap">
                  <div class="ranking-bar-fill" style="width:{item.pct}%;background:{color}opacity:0.7"></div>
                </div>
                <div class="ranking-meta">
                  <span>{fmtNum(item.monthly)} ₽/мес · {item.pct}% бюджета</span>
                  {#if item.forecast}<span>~{item.forecast}</span>{/if}
                </div>
              </div>
            {/each}
          </div>
        </div>

      {/if}
    {/if}

  </div>

<!-- ══════════════════════════════════════════════════════════ DETAIL VIEW ══ -->
{:else if view === 'detail' && activeCredit}
  {@const pct = paidPct(activeCredit)}
  {@const nextDate = activeCredit.is_complex ? complexNextDate(activeCredit.id) : nextPaymentDate(activeCredit.payment_day)}
  {@const days = daysUntil(nextDate)}
  {@const forecast = closureForecast(activeCredit)}
  {@const spark = sparkline(historyPayments, detailTotal)}
  {@const twi = activeCredit.is_complex ? null : totalWithInterest(activeCredit)}
  {@const paymentsLeft = remainingPaymentsCount(activeCredit)}
  {@const detailMonthly = activeCredit.is_complex ? complexMonthlySum(activeCredit.id) : (activeCredit.monthly_payment ?? 0)}
  {@const detailTotal = activeCredit.is_complex ? complexTotalSum(activeCredit.id) : activeCredit.total_amount}

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
          <span class="detail-remaining-label">{activeCredit.is_complex ? 'Запланировано платежей' : twi !== null ? 'К выплате с процентами' : 'Осталось'}</span>
          <span class="detail-remaining-amount">{(twi ?? activeCredit.remaining).toLocaleString('ru-RU')} ₽</span>
          {#if twi !== null && twi !== activeCredit.remaining}
            <span class="detail-principal-sub">
              тело долга {activeCredit.remaining.toLocaleString('ru-RU')} ₽
              {#if paymentsLeft !== null} · {paymentsLeft} платежей{/if}
            </span>
          {/if}
          <span class="detail-total-sub">из {detailTotal.toLocaleString('ru-RU')} ₽ · {pct}% выплачено</span>
        </div>
        {#if spark}
          <div class="sparkline" style="color:var(--color-accent)">{@html spark}</div>
        {/if}
      </div>

      <div class="progress-bar big">
        <div class="progress-fill" style="width:{pct}%"></div>
      </div>

      <div class="detail-meta-row">
        {#if detailMonthly > 0}
          <div class="detail-meta-block">
            <span class="detail-meta-label">{activeCredit.is_complex ? 'Ближайший мес' : 'Платёж'}</span>
            <span class="detail-meta-val">{detailMonthly.toLocaleString('ru-RU')} ₽</span>
          </div>
        {/if}
        {#if activeCredit.payment_day && !activeCredit.is_complex}
          <div class="detail-meta-block">
            <span class="detail-meta-label">Число</span>
            <span class="detail-meta-val">{activeCredit.payment_day}</span>
          </div>
        {/if}
        {#if nextDate}
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

    <!-- Early repayment button -->
    {#if !activeCredit.is_complex && activeCredit.remaining > 0}
      <button class="early-btn" on:click={openEarlyRepayment}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M13 5H5a2 2 0 00-2 2v10a2 2 0 002 2h14a2 2 0 002-2v-4"/><path d="M17 3l4 4-4 4M21 7H9"/></svg>
        Досрочное погашение
      </button>
    {/if}

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
              <span class="payment-amount">{p.amount.toLocaleString('ru-RU')} ₽</span>
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
            <button class="edit-pay-btn" on:click={() => openEditPayment(p)} aria-label="Редактировать">{@html icons.edit}</button>
            <button class="pay-btn" on:click={() => markPaid(p)}>Оплатить</button>
            <button class="delete-btn-sm" on:click={() => deletePayment(p)} aria-label="Удалить">×</button>
          </div>
        {/each}
      </div>
    {/if}

    <!-- History -->
    <div class="section-row">
      <p class="section-label">История</p>
      <div class="section-actions">
        {#if activeCredit.is_complex}
          <button class="add-pay-btn" on:click={openBulkSchedule}>+ Расписание</button>
          <span class="section-divider">·</span>
        {/if}
        <button class="add-pay-btn" on:click={openAddPayment}>
          {activeCredit.is_complex ? '+ Один платёж' : '+ Внести платёж'}
        </button>
      </div>
    </div>

    {#if historyByMonth.length === 0}
      <p class="muted-hint" style="margin-top:0.75rem">Нет платежей</p>
    {:else}
      {#each historyByMonth as group}
        <div class="month-group">
          <div class="month-header">
            <span class="month-label">{group.label}</span>
            <span class="month-sum">−{group.payments.reduce((s, p) => s + p.amount, 0).toLocaleString('ru-RU')} ₽</span>
          </div>
          <div class="payment-list">
            {#each group.payments as p}
              <div class="payment-row">
                <div class="payment-info">
                  <span class="payment-amount">−{p.amount.toLocaleString('ru-RU')} ₽</span>
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
      <input
        class="form-input"
        type="text"
        inputmode="numeric"
        bind:value={fTotalDisplay}
        on:blur={() => { fTotal = fTotalDisplay.replace(/\s/g,''); fTotalDisplay = fTotal ? formatInput(fTotal) : '' }}
        placeholder="99 999"
      />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Осталось *</label>
      <input
        class="form-input"
        type="text"
        inputmode="numeric"
        bind:value={fRemainingDisplay}
        on:blur={() => { fRemaining = fRemainingDisplay.replace(/\s/g,''); fRemainingDisplay = fRemaining ? formatInput(fRemaining) : '' }}
        placeholder="83 884"
      />
    </div>
  </div>

  {#if !fIsComplex}
    <div class="form-row">
      <div class="form-group" style="flex:1">
        <label class="form-label">Платёж/мес</label>
        <input
          class="form-input"
          type="text"
          inputmode="numeric"
          bind:value={fMonthlyDisplay}
          on:blur={() => { fMonthly = fMonthlyDisplay.replace(/\s/g,''); fMonthlyDisplay = fMonthly ? formatInput(fMonthly) : '' }}
          placeholder="6 836"
        />
      </div>
      <div class="form-group" style="flex:1">
        <label class="form-label">Число платежа</label>
        <input class="form-input" type="number" min="1" max="31" bind:value={fPaymentDay} placeholder="8" />
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
      <input
        class="form-input"
        type="text"
        inputmode="numeric"
        bind:value={fPayAmountDisplay}
        on:blur={() => { fPayAmount = fPayAmountDisplay.replace(/\s/g,''); fPayAmountDisplay = fPayAmount ? formatInput(fPayAmount) : '' }}
        placeholder="6 836"
      />
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

<Modal title="Редактировать платёж" open={showEditPaymentModal} on:close={() => showEditPaymentModal = false}>
  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Сумма *</label>
      <input
        class="form-input"
        type="text"
        inputmode="numeric"
        bind:value={fEditAmountDisplay}
        on:blur={() => { fEditAmount = fEditAmountDisplay.replace(/\s/g,''); fEditAmountDisplay = fEditAmount ? formatInput(fEditAmount) : '' }}
        placeholder="6 836"
      />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Дата</label>
      <div class="date-trio">
        <input
          class="date-part" type="text" inputmode="numeric" maxlength="2"
          bind:value={fEditDay} placeholder="дд"
          on:input={e => { if (e.currentTarget.value.length === 2) e.currentTarget.nextElementSibling?.nextElementSibling?.focus() }}
        />
        <span class="date-sep">.</span>
        <input
          class="date-part" type="text" inputmode="numeric" maxlength="2"
          bind:value={fEditMonth} placeholder="мм"
          on:input={e => { if (e.currentTarget.value.length === 2) e.currentTarget.nextElementSibling?.nextElementSibling?.focus() }}
        />
        <span class="date-sep">.</span>
        <input class="date-part year" type="text" inputmode="numeric" maxlength="4" bind:value={fEditYear} placeholder="гггг" />
      </div>
    </div>
  </div>
  <div class="form-group">
    <label class="form-label">Заметки</label>
    <input class="form-input" bind:value={fEditNotes} placeholder="…" />
  </div>
  <div class="form-actions">
    <button class="btn-primary" on:click={saveEditPayment} disabled={!fEditDate}>Сохранить</button>
  </div>
</Modal>

<Modal title="Создать расписание" open={showBulkModal} on:close={() => showBulkModal = false}>
  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Сумма платежа *</label>
      <input
        class="form-input"
        type="text"
        inputmode="numeric"
        bind:value={fBulkAmountDisplay}
        on:blur={() => { fBulkAmount = fBulkAmountDisplay.replace(/\s/g,''); fBulkAmountDisplay = fBulkAmount ? formatInput(fBulkAmount) : '' }}
        placeholder="6 836"
      />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Количество *</label>
      <input class="form-input" type="number" min="1" max="36" bind:value={fBulkCount} placeholder="20" />
    </div>
  </div>

  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Первая дата</label>
      <div class="date-trio">
        <input
          class="date-part"
          type="text"
          inputmode="numeric"
          maxlength="2"
          bind:value={fBulkDay}
          placeholder="дд"
          on:input={e => { if (e.currentTarget.value.length === 2) e.currentTarget.nextElementSibling?.nextElementSibling?.focus() }}
        />
        <span class="date-sep">.</span>
        <input
          class="date-part"
          type="text"
          inputmode="numeric"
          maxlength="2"
          bind:value={fBulkMonth}
          placeholder="мм"
          on:input={e => { if (e.currentTarget.value.length === 2) e.currentTarget.nextElementSibling?.nextElementSibling?.focus() }}
        />
        <span class="date-sep">.</span>
        <input
          class="date-part year"
          type="text"
          inputmode="numeric"
          maxlength="4"
          bind:value={fBulkYear}
          placeholder="гггг"
        />
      </div>
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Интервал</label>
      <div class="mode-toggle">
        <button class="mode-btn" class:active={fBulkInterval === 'month'} on:click={() => fBulkInterval = 'month'}>Мес</button>
        <button class="mode-btn" class:active={fBulkInterval === 'week'}  on:click={() => fBulkInterval = 'week'}>Нед</button>
        <button class="mode-btn" class:active={fBulkInterval === 'day'}   on:click={() => fBulkInterval = 'day'}>День</button>
      </div>
    </div>
  </div>

  <div class="form-group">
    <div class="toggle-row">
      <div class="toggle-text">
        <span class="toggle-label">Все уже оплачены</span>
        <span class="toggle-sub">Для занесения прошлых платежей</span>
      </div>
      <button class="toggle-btn" class:on={fBulkPaid} on:click={() => fBulkPaid = !fBulkPaid} role="switch" aria-checked={fBulkPaid}>
        <span class="toggle-knob"></span>
      </button>
    </div>
  </div>

  {#if bulkPreviewDates.length > 0}
    <div class="bulk-preview">
      <div class="bulk-preview-header">
        <span class="bulk-preview-title">{bulkPreviewDates.length} платежей · {fmtNum(bulkAmount * bulkPreviewDates.length)} ₽ итого</span>
      </div>
      <div class="bulk-dates">
        {#each bulkPreviewDates as d, i}
          <span class="bulk-date-chip" class:paid={fBulkPaid}>{fmt(d)}</span>
        {/each}
      </div>
    </div>
  {/if}

  <div class="form-actions">
    <button class="btn-primary" on:click={saveBulkSchedule} disabled={bulkSaving || bulkPreviewDates.length === 0}>
      {bulkSaving ? 'Создаю…' : `Создать ${bulkPreviewDates.length > 0 ? bulkPreviewDates.length + ' платежей' : ''}`}
    </button>
  </div>
</Modal>

<Modal title="Досрочное погашение" open={showEarlyModal} on:close={() => showEarlyModal = false}>
  <div class="form-row">
    <div class="form-group" style="flex:1">
      <label class="form-label">Сумма *</label>
      <input
        class="form-input"
        type="text"
        inputmode="numeric"
        bind:value={fEarlyAmountDisplay}
        on:blur={() => { fEarlyAmount = fEarlyAmountDisplay.replace(/\s/g,''); fEarlyAmountDisplay = fEarlyAmount ? formatInput(fEarlyAmount) : '' }}
        placeholder="20 000"
      />
    </div>
    <div class="form-group" style="flex:1">
      <label class="form-label">Дата</label>
      <input class="form-input" type="date" bind:value={fEarlyDate} />
    </div>
  </div>

  <div class="form-group">
    <label class="form-label">Что пересчитать</label>
    <div class="mode-toggle">
      <button
        class="mode-btn"
        class:active={fEarlyMode === 'term'}
        on:click={() => fEarlyMode = 'term'}
      >Уменьшить срок</button>
      <button
        class="mode-btn"
        class:active={fEarlyMode === 'payment'}
        on:click={() => fEarlyMode = 'payment'}
      >Уменьшить платёж</button>
    </div>
  </div>

  {#if earlyPreview}
    <div class="early-preview" class:paid={earlyPreview.paid}>
      <span class="early-preview-label">{earlyPreview.label}</span>
      {#if earlyPreview.sub}<span class="early-preview-sub">{earlyPreview.sub}</span>{/if}
      {#if !earlyPreview.paid && earlyNewRemaining > 0}
        <span class="early-preview-remaining">Остаток: {fmtNum(earlyNewRemaining)} ₽</span>
      {/if}
    </div>
  {/if}

  <div class="form-actions">
    <button class="btn-primary" on:click={saveEarlyRepayment}>Внести</button>
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
  .summary-principal { display: block; font-size: 0.75rem; color: rgba(255,255,255,0.55); margin-top: 0.25rem; }
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
  .credit-amounts { display: flex; flex-direction: column; align-items: flex-end; flex-shrink: 0; gap: 1px; }
  .credit-remaining { font-size: 1rem; font-weight: 600; color: var(--color-text); font-family: "JetBrains Mono", monospace; }
  .credit-principal { font-size: 0.6875rem; color: var(--color-muted); }

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
  .detail-principal-sub { font-size: 0.8125rem; color: var(--color-muted); display: block; margin-top: 0.125rem; }
  .detail-total-sub { font-size: 0.8125rem; color: var(--color-muted); display: block; margin-top: 0.125rem; margin-bottom: 0.875rem; }

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

  .section-actions { display: flex; align-items: center; gap: 0.375rem; }
  .section-divider { color: var(--color-border); font-size: 0.875rem; }

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

  .edit-pay-btn {
    background: none; border: none; cursor: pointer;
    color: var(--color-muted); padding: 0.25rem;
    width: 1.5rem; height: 1.5rem; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    -webkit-tap-highlight-color: transparent;
  }
  .edit-pay-btn :global(svg) { width: 100%; height: 100%; }
  .edit-pay-btn:active { opacity: 0.5; }

  .pay-btn {
    padding: 0.375rem 0.75rem;
    background: var(--color-accent); color: white;
    border: none; border-radius: 0.625rem;
    font-size: 0.8125rem; cursor: pointer;
    font-family: inherit; -webkit-tap-highlight-color: transparent; flex-shrink: 0;
  }
  .pay-btn:active { opacity: 0.8; }
  .pay-btn.outline {
    background: transparent;
    color: var(--color-accent);
    border: 1px solid var(--color-accent);
  }

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

  /* ── Chart ── */
  .chart-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.25rem;
    padding: 1rem;
    margin-bottom: 0.75rem;
    overflow: hidden;
  }
  .chart-title {
    font-size: 0.75rem; color: var(--color-muted);
    text-transform: uppercase; letter-spacing: 0.06em; margin: 0 0 0.5rem;
  }
  .chart-legend {
    display: flex; flex-wrap: wrap; gap: 0.25rem 0.75rem; margin-bottom: 0.75rem;
  }
  .legend-item { display: flex; align-items: center; gap: 0.3rem; }
  .legend-dot { width: 7px; height: 7px; border-radius: 50%; flex-shrink: 0; }
  .legend-name { font-size: 0.75rem; color: var(--color-muted); }
  .chart-scroll {
    overflow-x: auto; overflow-y: visible;
    -webkit-overflow-scrolling: touch;
    scrollbar-width: none; padding-bottom: 0.25rem;
  }
  .chart-scroll::-webkit-scrollbar { display: none; }
  :global(.chart-lbl) { font-size: 9px; fill: var(--color-muted); font-family: inherit; }
  :global(.chart-yr)  { font-size: 8px; fill: var(--color-muted); font-family: inherit; opacity: 0.6; }

  /* ── Sort chips ── */
  .sort-row {
    display: flex; gap: 0.375rem;
    margin-bottom: 0.75rem;
  }
  .sort-chip {
    padding: 0.3125rem 0.75rem;
    font-size: 0.8125rem; font-family: inherit;
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 999px; cursor: pointer; color: var(--color-muted);
    -webkit-tap-highlight-color: transparent; transition: all 0.15s;
  }
  .sort-chip.active {
    background: var(--color-accent); border-color: var(--color-accent);
    color: white;
  }

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

  /* ── Three-part date input ── */
  .date-trio {
    display: flex; align-items: center; gap: 0;
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 0.75rem; overflow: hidden; height: 2.5rem;
  }
  .date-trio:focus-within { border-color: var(--color-accent); }
  .date-part {
    flex: 1; border: none; background: transparent;
    font-size: 0.9375rem; color: var(--color-text); font-family: inherit;
    text-align: center; padding: 0; height: 100%;
    -webkit-appearance: none; -moz-appearance: textfield;
  }
  .date-part:focus { outline: none; }
  .date-part.year { flex: 1.6; }
  .date-sep { color: var(--color-muted); font-size: 1rem; padding: 0 0.125rem; user-select: none; }

  /* ── Bulk schedule preview ── */
  .bulk-preview {
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    padding: 0.75rem;
    margin-bottom: 0.75rem;
  }
  .bulk-preview-header { margin-bottom: 0.5rem; }
  .bulk-preview-title { font-size: 0.875rem; color: var(--color-text); font-weight: 500; }
  .bulk-dates { display: flex; flex-wrap: wrap; gap: 0.3rem; }
  .bulk-date-chip {
    font-size: 0.75rem; color: var(--color-muted);
    background: var(--color-card); border: 1px solid var(--color-border);
    border-radius: 0.5rem; padding: 0.1875rem 0.5rem;
  }
  .bulk-date-chip.paid { color: #43a047; border-color: #43a04730; background: #43a04710; }

  /* ── Early repayment ── */
  .early-btn {
    display: flex; align-items: center; gap: 0.5rem;
    width: 100%; padding: 0.75rem 1rem;
    background: var(--color-card); border: 1.5px dashed var(--color-accent);
    border-radius: 1rem; cursor: pointer; font-family: inherit;
    font-size: 0.9375rem; color: var(--color-accent);
    -webkit-tap-highlight-color: transparent;
    margin-bottom: 1.25rem; transition: opacity 0.15s;
  }
  .early-btn:active { opacity: 0.7; }
  .early-btn svg { flex-shrink: 0; }

  .mode-toggle {
    display: flex; gap: 0.375rem;
    background: var(--color-bg); border: 1px solid var(--color-border);
    border-radius: 0.75rem; padding: 0.25rem;
  }
  .mode-btn {
    flex: 1; padding: 0.5rem 0.75rem;
    border: none; border-radius: 0.5rem;
    font-size: 0.875rem; font-family: inherit;
    cursor: pointer; color: var(--color-muted);
    background: transparent; -webkit-tap-highlight-color: transparent;
    transition: all 0.15s;
  }
  .mode-btn.active {
    background: var(--color-card);
    color: var(--color-text);
    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
  }

  .early-preview {
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    padding: 0.875rem 1rem;
    margin-bottom: 0.75rem;
    display: flex; flex-direction: column; gap: 0.25rem;
  }
  .early-preview.paid { border-color: #43a047; background: #43a04710; }
  .early-preview-label {
    font-size: 1rem; font-weight: 500; color: var(--color-text);
  }
  .early-preview.paid .early-preview-label { color: #43a047; }
  .early-preview-sub { font-size: 0.8125rem; color: var(--color-accent); }
  .early-preview-remaining { font-size: 0.8125rem; color: var(--color-muted); }

  /* ── Main tabs ── */
  .main-tabs {
    display: flex; gap: 0.25rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 999px;
    padding: 0.25rem;
    margin-bottom: 1rem;
  }
  .main-tab {
    flex: 1; padding: 0.4375rem 0.5rem;
    border: none; border-radius: 999px;
    font-size: 0.875rem; font-family: inherit;
    cursor: pointer; color: var(--color-muted);
    background: transparent; -webkit-tap-highlight-color: transparent;
    transition: all 0.15s; white-space: nowrap;
  }
  .main-tab.active {
    background: var(--color-accent);
    color: white;
    box-shadow: 0 1px 3px rgba(0,0,0,0.15);
  }

  /* ── Payments tab ── */
  .pay-period-total {
    font-size: 0.875rem; color: var(--color-muted);
    margin-bottom: 0.75rem;
    padding: 0 0.25rem;
  }
  .pay-period-total strong { color: var(--color-text); font-weight: 600; }

  .pay-flat-list { display: flex; flex-direction: column; gap: 0.5rem; }

  .pay-flat-row {
    display: flex; align-items: center; gap: 0.75rem;
    padding: 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.875rem;
    transition: border-color 0.15s;
  }
  .pay-flat-row.urgent { border-color: #e6510050; background: #e6510008; }
  .pay-flat-row.overdue { border-color: #e5393550; background: #e5393508; }

  .pay-flat-dot {
    width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0;
  }

  .pay-flat-info { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .pay-flat-name { font-size: 0.9375rem; font-weight: 500; color: var(--color-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .pay-flat-date { font-size: 0.75rem; color: var(--color-muted); }

  .pay-flat-amount {
    font-size: 0.9375rem; font-weight: 600; color: var(--color-text);
    font-family: "JetBrains Mono", monospace; flex-shrink: 0;
  }

  /* ── Credit ranking ── */
  .ranking-list { display: flex; flex-direction: column; gap: 0.875rem; }
  .ranking-row { display: flex; flex-direction: column; gap: 0.3rem; }
  .ranking-top { display: flex; justify-content: space-between; align-items: center; }
  .ranking-name-row { display: flex; align-items: center; gap: 0.375rem; min-width: 0; }
  .ranking-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .ranking-name { font-size: 0.9375rem; font-weight: 500; color: var(--color-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .ranking-remaining { font-size: 0.9375rem; font-weight: 600; color: var(--color-text); font-family: "JetBrains Mono", monospace; flex-shrink: 0; margin-left: 0.5rem; }
  .ranking-bar-wrap { height: 4px; background: var(--color-border); border-radius: 2px; overflow: hidden; }
  .ranking-bar-fill { height: 100%; border-radius: 2px; opacity: 0.75; transition: width 0.4s; }
  .ranking-meta { display: flex; justify-content: space-between; font-size: 0.75rem; color: var(--color-muted); }
</style>
