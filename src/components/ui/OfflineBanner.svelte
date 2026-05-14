<script lang="ts">
  import { isOnline } from '../../stores/offline'
</script>

{#if !$isOnline}
  <div class="banner">
    <span>Нет сети — работаем офлайн, данные сохранятся автоматически</span>
  </div>
{/if}

<style>
  .banner {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    z-index: 300;
    background-color: var(--color-accent2);
    color: white;
    text-align: center;
    font-size: 0.75rem;
    padding: 0.4rem 1rem;
    letter-spacing: 0.01em;
  }
</style>
