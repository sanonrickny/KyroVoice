/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        display: ['"Instrument Serif"', 'serif'],
        sans: ['"General Sans"', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
      },
      colors: {
        ink: {
          900: '#08080b',
          800: '#0d0d12',
          700: '#101015',
          600: '#16161d',
          500: '#1d1d26',
          400: '#272731',
        },
        bone: {
          100: '#f3f3f7',
          200: '#dcdce2',
          300: '#a8a8b2',
          400: '#787884',
          500: '#5d5d68',
          600: '#3f3f48',
        },
        plum: '#b76fff',
        rose: '#ff6cb6',
        amber: '#ffa86c',
        mint: '#5cdc9b',
      },
      boxShadow: {
        keycap:
          '0 1px 0 rgba(255,255,255,0.07) inset, 0 -2px 0 rgba(0,0,0,0.5) inset, 0 4px 12px rgba(0,0,0,0.6)',
        glow: '0 0 36px -8px rgba(183,111,255,0.45), 0 0 80px -20px rgba(255,108,182,0.35)',
      },
      backgroundImage: {
        'plum-rose': 'linear-gradient(135deg, #b76fff 0%, #ff6cb6 100%)',
      },
    },
  },
  plugins: [],
}
