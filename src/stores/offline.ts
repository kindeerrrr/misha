import { readable } from 'svelte/store'

export const isOnline = readable(navigator.onLine, (set) => {
  const onOnline = () => set(true)
  const onOffline = () => set(false)
  window.addEventListener('online', onOnline)
  window.addEventListener('offline', onOffline)
  return () => {
    window.removeEventListener('online', onOnline)
    window.removeEventListener('offline', onOffline)
  }
})
