/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './index.html',
    './src/**/*.{js,ts,jsx,tsx}'
  ],
  theme: {
    extend: {
      colors: {
        vscode: {
          bg: '#1e1e1e',
          sidebar: '#252526',
          panel: '#2d2d30',
          border: '#454545',
          text: '#cccccc',
          textMuted: '#858585',
          primary: '#007acc'
        }
      },
      fontFamily: {
        mono: ['Consolas','Monaco','Courier New','monospace']
      }
    }
  },
  plugins: [require('@tailwindcss/forms'), require('@tailwindcss/typography')],
  darkMode: 'class'
}
