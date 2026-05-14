import { writable } from 'svelte/store'

export type ToastType = 'success' | 'error' | 'info'
interface Toast { id: number; message: string; type: ToastType }

export const toasts = writable<Toast[]>([])

let counter = 0
export function showToast(message: string, type: ToastType = 'success', duration = 2500) {
  const id = ++counter
  toasts.update(t => [...t, { id, message, type }])
  setTimeout(() => toasts.update(t => t.filter(x => x.id !== id)), duration)
}
