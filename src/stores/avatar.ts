import { writable } from 'svelte/store'
import type { AvatarVariant } from '../lib/types'

const STORAGE_KEY = 'misha_avatar'

function createAvatarStore() {
  const saved = (localStorage.getItem(STORAGE_KEY) as AvatarVariant) ?? 'sage'
  const { subscribe, set } = writable<AvatarVariant>(saved)

  function apply(v: AvatarVariant) {
    localStorage.setItem(STORAGE_KEY, v)
    set(v)
  }

  apply(saved)

  return {
    subscribe,
    set: apply,
  }
}

export const avatar = createAvatarStore()

export function avatarSrc(variant: AvatarVariant, size: 192 | 512 | 1024 = 192) {
  return `/icons/${variant}/${size}.png`
}
