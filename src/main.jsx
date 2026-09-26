import React from 'react'
import ReactDOM from 'react-dom/client'
import App from '@/App.jsx'
import '@/index.css'
import { registerServiceWorker } from '@/lib/pwa'
import { initNative } from '@/lib/native'

registerServiceWorker()
initNative()
ReactDOM.createRoot(document.getElementById('root')).render(<App />)