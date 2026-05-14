<script lang="ts">
  import { onMount } from 'svelte'
  import { supabase, today, uploadFile } from '../../lib/supabase'
  import { user } from '../../stores/user'
  import Modal from '../../components/ui/Modal.svelte'
  import type { MedicalResearch } from '../../lib/types'

  let records: MedicalResearch[] = []
  let loading = true
  let showModal = false

  const TYPES = ['УЗИ','МРТ','КТ','ЭКГ','Эндоскопия','Биопсия','Рентген','Денситометрия','Другое']

  let rDate = today()
  let rType = 'УЗИ'
  let rBody = ''
  let rDesc = ''
  let rFiles: FileList | null = null
  let saving = false

  async function load() {
    if (!$user) return
    const { data } = await supabase.from('medical_research').select('*').eq('user_id', $user.id).order('date', { ascending: false }).limit(50)
    records = data ?? []
    loading = false
  }

  async function save() {
    if (!$user) return
    saving = true

    let fileUrls: string[] = []
    if (rFiles?.length) {
      for (const file of Array.from(rFiles)) {
        const path = `${$user.id}/research/${Date.now()}-${file.name}`
        const url = await uploadFile('medical-files', path, file)
        if (url) fileUrls.push(url)
      }
    }

    const { data } = await supabase.from('medical_research').insert({
      user_id: $user.id,
      date: rDate,
      research_type: rType,
      body_part: rBody || null,
      description: rDesc || null,
      file_urls: fileUrls,
    }).select().single()

    if (data) records = [data, ...records]
    showModal = false
    rDate = today(); rBody = ''; rDesc = ''; rFiles = null
    saving = false
  }

  function formatDate(d: string) {
    return new Date(d).toLocaleDateString('ru', { day: 'numeric', month: 'long', year: 'numeric' })
  }

  onMount(load)
</script>

<div>
  <div class="section-row">
    <h2 class="section-title">Исследования</h2>
    <button class="edit-btn" on:click={() => showModal = true}>+ Добавить</button>
  </div>

  {#if loading}
    {#each [1,2] as _}
      <div class="skeleton mt-2" style="height:5rem" />
    {/each}
  {:else if records.length === 0}
    <div class="empty-state mt-4">УЗИ, МРТ, КТ, ЭКГ и другие — всё здесь</div>
  {:else}
    <div class="record-list mt-3">
      {#each records as rec}
        <div class="record-card">
          <div class="record-header">
            <div class="record-type-badge">{rec.research_type}</div>
            <span class="label">{formatDate(rec.date)}</span>
          </div>
          {#if rec.body_part}
            <p class="record-body">{rec.body_part}</p>
          {/if}
          {#if rec.description}
            <p class="record-desc">{rec.description}</p>
          {/if}
          {#if rec.file_urls.length > 0}
            <div class="file-list">
              {#each rec.file_urls as url, i}
                <a href={url} target="_blank" rel="noopener" class="file-chip">📎 Файл {i+1}</a>
              {/each}
            </div>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</div>

<Modal title="Новое исследование" open={showModal} on:close={() => showModal = false}>
  <div class="form-stack">
    <div class="form-field">
      <label class="label" for="r-date">Дата</label>
      <input id="r-date" type="date" bind:value={rDate} />
    </div>

    <div class="form-field">
      <label class="label">Тип</label>
      <div class="type-grid">
        {#each TYPES as t}
          <button class="type-btn" class:selected={rType === t} on:click={() => rType = t}>{t}</button>
        {/each}
      </div>
    </div>

    <div class="form-field">
      <label class="label" for="r-body">Область / орган</label>
      <input id="r-body" type="text" bind:value={rBody} placeholder="Щитовидная железа, брюшная полость..." />
    </div>

    <div class="form-field">
      <label class="label" for="r-desc">Описание / результат</label>
      <textarea id="r-desc" bind:value={rDesc} rows="3" placeholder="Заключение врача..." />
    </div>

    <div class="form-field">
      <label class="label" for="r-files">Файлы (PDF, фото)</label>
      <input id="r-files" type="file" accept=".pdf,image/*" multiple bind:files={rFiles} class="file-input" />
    </div>

    <button class="btn-primary" on:click={save} disabled={saving}>
      {saving ? 'Сохраняю...' : 'Сохранить'}
    </button>
  </div>
</Modal>

<style>
  .section-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.875rem; }
  .edit-btn { background: none; border: 1px solid var(--color-border); border-radius: 0.625rem; padding: 0.375rem 0.875rem; font-size: 0.8125rem; color: var(--color-accent); cursor: pointer; }

  .record-list { display: flex; flex-direction: column; gap: 0.625rem; }

  .record-card {
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 1.125rem;
    padding: 0.875rem 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .record-header { display: flex; align-items: center; justify-content: space-between; gap: 0.75rem; }

  .record-type-badge {
    background: var(--color-accent);
    color: white;
    border-radius: 0.5rem;
    padding: 0.25rem 0.625rem;
    font-size: 0.8125rem;
  }

  .record-body { font-size: 0.9375rem; color: var(--color-text); margin: 0; }
  .record-desc { font-size: 0.8125rem; color: var(--color-muted); margin: 0; }

  .file-list { display: flex; gap: 0.375rem; flex-wrap: wrap; }
  .file-chip { font-size: 0.75rem; padding: 0.25rem 0.625rem; background: var(--color-bg); border: 1px solid var(--color-border); border-radius: 0.5rem; color: var(--color-accent); text-decoration: none; }

  .type-grid { display: flex; flex-wrap: wrap; gap: 0.375rem; }
  .type-btn { padding: 0.375rem 0.875rem; border: 1px solid var(--color-border); border-radius: 2rem; background: var(--color-card); font-size: 0.8125rem; cursor: pointer; -webkit-tap-highlight-color: transparent; transition: all 0.15s; }
  .type-btn.selected { background: var(--color-accent); border-color: var(--color-accent); color: white; }

  .empty-state { padding: 2rem; text-align: center; color: var(--color-muted); background: var(--color-card); border-radius: 1.25rem; border: 1px dashed var(--color-border); }

  .form-stack { display: flex; flex-direction: column; gap: 1rem; }
  .form-field { display: flex; flex-direction: column; gap: 0.375rem; }

  .file-input { padding: 0.5rem; border-radius: 0.75rem; background: var(--color-card); border: 1px solid var(--color-border); font-size: 0.875rem; color: var(--color-text); }

  .skeleton { border-radius: 1.125rem; background: linear-gradient(90deg, var(--color-card) 25%, var(--color-card-hover) 50%, var(--color-card) 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
  @keyframes shimmer { from { background-position: 200% 0; } to { background-position: -200% 0; } }

  .mt-2 { margin-top: 0.5rem; }
  .mt-3 { margin-top: 0.75rem; }
  .mt-4 { margin-top: 1rem; }
</style>
