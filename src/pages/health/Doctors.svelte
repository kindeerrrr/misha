<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today, uploadFile } from '../../lib/supabase'
  import { user } from '../../stores/user'
  import Modal from '../../components/ui/Modal.svelte'
  import type { DoctorVisit } from '../../lib/types'

  let visits: DoctorVisit[] = []
  let loading = true
  let showModal = false
  let search = ''

  const DOCTOR_CATEGORIES: Record<string, string[]> = {
    'Стоматолог': ['Чистка','Пломба','КТ','Удаление','Коронка','Другое'],
    'Гинеколог':  ['Плановый осмотр','Мазок','УЗИ','Кольпоскопия','Другое'],
    'Терапевт':   ['Плановый','Больничный','Профосмотр','Другое'],
    'Окулист':    ['Плановый','Подбор линз','Другое'],
    'Дерматолог': ['Осмотр родинок','Другое'],
    'Эндокринолог':['Консультация','Другое'],
    'Другое':     ['Консультация','Другое'],
  }

  let vDate = today()
  let vCategory = 'Стоматолог'
  let vProcedure = 'Чистка'
  let vNotes = ''
  let vFiles: FileList | null = null
  let saving = false

  $: procedures = DOCTOR_CATEGORIES[vCategory] ?? ['Другое']
  $: if (procedures.length > 0 && !procedures.includes(vProcedure)) vProcedure = procedures[0]

  async function load() {
    if (!$user) return
    const { data } = await supabase.from('doctor_visits').select('*').eq('user_id', $user.id).order('date', { ascending: false }).limit(50)
    visits = data ?? []
    loading = false
  }

  async function save() {
    if (!$user) return
    saving = true

    let fileUrls: string[] = []
    if (vFiles?.length) {
      for (const file of Array.from(vFiles)) {
        const path = `${$user.id}/doctors/${Date.now()}-${file.name}`
        const url = await uploadFile('medical-files', path, file)
        if (url) fileUrls.push(url)
      }
    }

    const { data } = await supabase.from('doctor_visits').insert({
      user_id: $user.id,
      date: vDate,
      doctor_category: vCategory,
      procedure: vProcedure,
      notes: vNotes || null,
      file_urls: fileUrls,
    }).select().single()

    if (data) visits = [data, ...visits]
    showModal = false
    vDate = today(); vNotes = ''; vFiles = null
    saving = false
  }

  $: filtered = search
    ? visits.filter(v => v.doctor_category.toLowerCase().includes(search.toLowerCase()) || v.procedure.toLowerCase().includes(search.toLowerCase()) || (v.notes ?? '').toLowerCase().includes(search.toLowerCase()))
    : visits

  function formatDate(d: string) {
    return new Date(d).toLocaleDateString('ru', { day: 'numeric', month: 'long', year: 'numeric' })
  }

  onMount(load)
</script>

<div>
  <div class="section-row">
    <h2 class="section-title">Врачи и анализы</h2>
    <button class="edit-btn" on:click={() => showModal = true}>+ Визит</button>
  </div>

  <input
    type="search"
    bind:value={search}
    placeholder="Поиск по врачу или процедуре..."
    class="search-input"
  />

  {#if loading}
    {#each [1,2,3] as _}
      <div class="skeleton mt-2" style="height:4.5rem" />
    {/each}
  {:else if filtered.length === 0}
    <div class="empty-state mt-4">
      {search ? 'Ничего не найдено' : 'Визиты появятся здесь'}
    </div>
  {:else}
    <div class="visit-list mt-3">
      {#each filtered as visit}
        <div class="visit-card">
          <div class="visit-header">
            <div>
              <span class="visit-category">{visit.doctor_category}</span>
              <span class="visit-procedure">{visit.procedure}</span>
            </div>
            <span class="visit-date label">{formatDate(visit.date)}</span>
          </div>
          {#if visit.notes}
            <p class="visit-notes">{visit.notes}</p>
          {/if}
          {#if visit.file_urls.length > 0}
            <div class="file-list">
              {#each visit.file_urls as url}
                <a href={url} target="_blank" rel="noopener" class="file-chip">📎 Файл</a>
              {/each}
            </div>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</div>

<Modal title="Визит к врачу" open={showModal} on:close={() => showModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="v-date">Дата</label>
      <input id="v-date" type="date" bind:value={vDate} />
    </div>

    <div class="form-field">
      <label class="label" for="v-cat">Врач</label>
      <select id="v-cat" bind:value={vCategory}>
        {#each Object.keys(DOCTOR_CATEGORIES) as cat}
          <option value={cat}>{cat}</option>
        {/each}
      </select>
    </div>

    <div class="form-field">
      <label class="label" for="v-proc">Процедура</label>
      <select id="v-proc" bind:value={vProcedure}>
        {#each procedures as p}
          <option value={p}>{p}</option>
        {/each}
      </select>
    </div>

    <div class="form-field">
      <label class="label" for="v-notes">Заметка</label>
      <textarea id="v-notes" bind:value={vNotes} rows="3" placeholder="Результаты, назначения, рекомендации..." />
    </div>

    <div class="form-field">
      <label class="label" for="v-files">Файлы (PDF, фото)</label>
      <input id="v-files" type="file" accept=".pdf,image/*" multiple bind:files={vFiles} class="file-input" />
    </div>

    <button class="btn-primary" on:click={save} disabled={saving}>
      {saving ? 'Сохраняю...' : 'Сохранить'}
    </button>
  </div>
</Modal>

<style>
  .section-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.875rem; }
  .edit-btn { background: none; border: 1px solid var(--color-border); border-radius: 0.625rem; padding: 0.375rem 0.875rem; font-size: 0.8125rem; color: var(--color-accent); cursor: pointer; }

  .search-input { margin-top: 0.25rem; }

  .visit-list { display: flex; flex-direction: column; gap: 0.625rem; }

  .visit-card {
    background-color: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.125rem;
    padding: 0.875rem 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .visit-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 0.75rem; }
  .visit-category { font-size: 0.9375rem; color: var(--color-text); margin-right: 0.375rem; }
  .visit-procedure { font-size: 0.875rem; color: var(--color-accent); }
  .visit-date { font-size: 0.75rem; white-space: nowrap; }
  .visit-notes { font-size: 0.8125rem; color: var(--color-muted); margin: 0; }

  .file-list { display: flex; gap: 0.375rem; flex-wrap: wrap; }
  .file-chip { font-size: 0.75rem; padding: 0.25rem 0.625rem; background: var(--color-bg); border: 1px solid var(--color-border); border-radius: 0.5rem; color: var(--color-accent); text-decoration: none; }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .file-input {
    padding: 0.5rem;
    border-radius: 0.75rem;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    font-size: 0.875rem;
    color: var(--color-text);
  }

  .skeleton { border-radius: 1.125rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-2 { margin-top: 0.5rem; }
  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
</style>
