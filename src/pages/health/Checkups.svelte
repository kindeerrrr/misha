<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today } from '../../lib/supabase'
  import { user } from '../../stores/user'
  import Modal from '../../components/ui/Modal.svelte'
  import type { AnnualCheckup } from '../../lib/types'

  let checkups: AnnualCheckup[] = []
  let loading = true
  let showModal = false
  let showMarkModal = false
  let markingId = ''

  let cName = ''
  let cFreq = 12
  let cNotes = ''
  let saving = false
  let markDate = today()

  async function load() {
    if (!$user) return
    const { data } = await supabase.from('annual_checkups').select('*').eq('user_id', $user.id).order('name')
    checkups = data ?? []
    loading = false
  }

  async function save() {
    if (!$user || !cName.trim()) return
    saving = true
    const { data } = await supabase.from('annual_checkups').insert({
      user_id: $user.id,
      name: cName.trim(),
      frequency_months: cFreq,
      reminder_2w: true,
      reminder_3d: true,
      notes: cNotes || null,
    }).select().single()
    if (data) checkups = [...checkups, data]
    showModal = false
    cName = ''; cFreq = 12; cNotes = ''
    saving = false
  }

  async function markDone(id: string, date: string) {
    if (!$user) return
    const checkup = checkups.find(c => c.id === id)
    if (!checkup) return
    const nextDue = new Date(date)
    nextDue.setMonth(nextDue.getMonth() + checkup.frequency_months)
    const nextDueStr = nextDue.toISOString().slice(0, 10)
    await supabase.from('annual_checkups').update({
      last_done_at: date,
      next_due_at: nextDueStr,
    }).eq('id', id)
    checkups = checkups.map(c => c.id === id ? { ...c, last_done_at: date, next_due_at: nextDueStr } : c)
    showMarkModal = false
    markingId = ''
    markDate = today()
  }

  function daysUntil(dateStr: string | null): number | null {
    if (!dateStr) return null
    const diff = new Date(dateStr).getTime() - Date.now()
    return Math.ceil(diff / (1000 * 60 * 60 * 24))
  }

  function urgencyClass(checkup: AnnualCheckup): string {
    const days = daysUntil(checkup.next_due_at)
    if (days === null) return ''
    if (days < 0) return 'overdue'
    if (days <= 14) return 'soon'
    return ''
  }

  function formatDue(checkup: AnnualCheckup): string {
    if (!checkup.next_due_at) return 'Дата неизвестна'
    const days = daysUntil(checkup.next_due_at)
    if (days === null) return ''
    if (days < 0) return `Просрочено на ${Math.abs(days)} д.`
    if (days === 0) return 'Сегодня'
    if (days <= 14) return `Через ${days} дн.`
    return new Date(checkup.next_due_at).toLocaleDateString('ru', { day: 'numeric', month: 'long' })
  }

  onMount(load)
</script>

<div>
  <div class="section-row">
    <h2 class="section-title">Ежегодные осмотры</h2>
    <button class="edit-btn" on:click={() => showModal = true}>+ Добавить</button>
  </div>

  {#if loading}
    {#each [1,2,3] as _}
      <div class="skeleton mt-2" style="height:4rem" />
    {/each}
  {:else if checkups.length === 0}
    <div class="empty-state mt-4">Добавь плановые осмотры, чтобы не пропустить</div>
  {:else}
    <div class="checkup-list mt-3">
      {#each checkups as c}
        <div class="checkup-card {urgencyClass(c)}">
          <div class="checkup-main">
            <div class="checkup-info">
              <span class="checkup-name">{c.name}</span>
              <span class="checkup-freq label">1 раз в {c.frequency_months} мес.</span>
            </div>
            <div class="checkup-right">
              <span class="due-text {urgencyClass(c)}">{formatDue(c)}</span>
              <button class="done-btn" on:click={() => { markingId = c.id; showMarkModal = true }}>
                ✓ Сделала
              </button>
            </div>
          </div>
          {#if c.last_done_at}
            <span class="last-done">Последний раз: {new Date(c.last_done_at).toLocaleDateString('ru', {day:'numeric', month:'long', year:'numeric'})}</span>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</div>

<!-- Add modal -->
<Modal title="Новый осмотр" open={showModal} on:close={() => showModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="c-name">Название</label>
      <input id="c-name" type="text" bind:value={cName} placeholder="Стоматолог, Гинеколог, ОАК..." />
    </div>

    <div class="form-field">
      <label class="label">Частота</label>
      <div class="freq-group">
        {#each [[6,'2 раза/год'],[12,'1 раз/год'],[24,'1 раз в 2 года']] as [val, lbl]}
          <label class="radio-pill" class:selected={cFreq === val}>
            <input type="radio" bind:group={cFreq} value={val} /> {lbl}
          </label>
        {/each}
        <label class="radio-pill custom-freq">
          Другое:
          <input type="number" bind:value={cFreq} min="1" max="60" style="width:3rem;background:none;border:none;outline:none;color:inherit;font-size:0.8125rem;" />
          мес.
        </label>
      </div>
    </div>

    <div class="form-field">
      <label class="label" for="c-notes">Заметка</label>
      <textarea id="c-notes" bind:value={cNotes} rows="2" placeholder="Дополнительно..." />
    </div>

    <button class="btn-primary" on:click={save} disabled={saving || !cName.trim()}>
      {saving ? 'Сохраняю...' : 'Добавить'}
    </button>
  </div>
</Modal>

<!-- Mark done modal -->
<Modal title="Отметить как пройденное" open={showMarkModal} on:close={() => { showMarkModal = false; markingId = '' }}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="mark-date">Дата визита</label>
      <input id="mark-date" type="date" bind:value={markDate} />
    </div>
    <button class="btn-primary" on:click={() => markDone(markingId, markDate)}>
      Сохранить
    </button>
  </div>
</Modal>

<style>
  .section-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.875rem; }
  .edit-btn { background: none; border: 1px solid var(--color-border); border-radius: 0.625rem; padding: 0.375rem 0.875rem; font-size: 0.8125rem; color: var(--color-accent); cursor: pointer; }

  .checkup-list { display: flex; flex-direction: column; gap: 0.625rem; }

  .checkup-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.125rem;
    padding: 0.875rem 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .checkup-card.soon { border-left: 3px solid var(--color-warning); }
  .checkup-card.overdue { border-left: 3px solid var(--color-danger); }

  .checkup-main { display: flex; align-items: flex-start; gap: 0.75rem; }
  .checkup-info { flex: 1; display: flex; flex-direction: column; gap: 2px; }
  .checkup-name { font-size: 0.9375rem; color: var(--color-text); }
  .checkup-freq { font-size: 0.75rem; }

  .checkup-right { display: flex; flex-direction: column; align-items: flex-end; gap: 0.375rem; }

  .due-text { font-size: 0.8125rem; color: var(--color-muted); }
  .due-text.soon { color: var(--color-warning); font-weight: 500; }
  .due-text.overdue { color: var(--color-danger); font-weight: 500; }

  .done-btn {
    padding: 0.3rem 0.75rem;
    background: var(--color-accent);
    color: white;
    border: none;
    border-radius: 0.5rem;
    font-size: 0.8125rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    white-space: nowrap;
  }

  .last-done { font-size: 0.75rem; color: var(--color-muted); }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .freq-group { display: flex; flex-wrap: wrap; gap: 0.375rem; }

  .radio-pill { padding: 0.375rem 0.875rem; border: 1px solid var(--color-border); border-radius: 2rem; font-size: 0.8125rem; cursor: pointer; display: flex; align-items: center; gap: 0.25rem; -webkit-tap-highlight-color: transparent; transition: all 0.15s; }
  .radio-pill.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }
  .radio-pill input[type="radio"] { display: none; }

  .skeleton { border-radius: 1.125rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-2 { margin-top: 0.5rem; }
  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
</style>
