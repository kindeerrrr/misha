// Notion mirror — stub for Phase 0/1
// Real implementation: Supabase Edge Function → Notion API (Phase 1.5)

export interface NotionSyncPayload {
  table: string
  record_id: string
  data: Record<string, unknown>
  synced_at: string
}

export async function mirrorToNotion(_payload: NotionSyncPayload): Promise<void> {
  // TODO Phase 1.5: call /api/notion-sync edge function
  console.debug('[notion-stub] mirror skipped for now', _payload.table)
}
