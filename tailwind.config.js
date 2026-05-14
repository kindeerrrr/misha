/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{svelte,ts,js}'],
  theme: {
    extend: {
      fontFamily: {
        serif: ['"Source Serif 4"', 'Lora', 'Georgia', 'serif'],
        display: ['"Fraunces"', '"Playfair Display"', 'Georgia', 'serif'],
        mono: ['"JetBrains Mono"', '"SF Mono"', 'monospace'],
      },
      colors: {
        accent: 'var(--color-accent)',
        accent2: 'var(--color-accent2)',
        bg: 'var(--color-bg)',
        card: 'var(--color-card)',
        text: 'var(--color-text)',
        muted: 'var(--color-muted)',
        border: 'var(--color-border)',
      },
      borderRadius: {
        xl: '1rem',
        '2xl': '1.25rem',
        '3xl': '1.5rem',
      },
    },
  },
  plugins: [],
}
