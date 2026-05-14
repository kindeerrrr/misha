import { get, set, del, keys } from 'idb-keyval'

// Thin wrapper around idb-keyval with namespace prefixing

const prefix = (ns: string, key: string) => `${ns}:${key}`

export const cache = {
  async get<T>(ns: string, key: string): Promise<T | undefined> {
    return get<T>(prefix(ns, key))
  },

  async set<T>(ns: string, key: string, value: T): Promise<void> {
    return set(prefix(ns, key), value)
  },

  async del(ns: string, key: string): Promise<void> {
    return del(prefix(ns, key))
  },

  async keys(ns: string): Promise<string[]> {
    const all = await keys()
    return (all as string[]).filter(k => k.startsWith(`${ns}:`)).map(k => k.slice(ns.length + 1))
  },
}

// Pending queue for offline writes
export interface PendingWrite {
  id: string
  table: string
  op: 'insert' | 'update' | 'delete'
  payload: Record<string, unknown>
  created_at: number
}

export async function enqueuePendingWrite(write: PendingWrite): Promise<void> {
  const existing = (await get<PendingWrite[]>('pending_writes')) ?? []
  existing.push(write)
  await set('pending_writes', existing)
}

export async function getPendingWrites(): Promise<PendingWrite[]> {
  return (await get<PendingWrite[]>('pending_writes')) ?? []
}

export async function clearPendingWrite(id: string): Promise<void> {
  const existing = (await get<PendingWrite[]>('pending_writes')) ?? []
  await set('pending_writes', existing.filter(w => w.id !== id))
}
