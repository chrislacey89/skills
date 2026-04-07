import { useState, useCallback } from 'react'
import V1Terminal from './versions/v1-terminal'
import V2Editorial from './versions/v2-editorial'
import V3CRT from './versions/v3-crt'
import V4Blueprint from './versions/v4-blueprint'
import V5Organic from './versions/v5-organic'
import V6Brutalist from './versions/v6-brutalist'
import VersionSwitcher from './VersionSwitcher'

const VERSIONS = [V1Terminal, V2Editorial, V3CRT, V4Blueprint, V5Organic, V6Brutalist]

function App() {
  const [activeVersion, setActiveVersion] = useState(0)
  const [fading, setFading] = useState(false)

  const handleChange = useCallback((idx) => {
    if (idx === activeVersion) return
    setFading(true)
    setTimeout(() => {
      setActiveVersion(idx)
      setFading(false)
    }, 120)
  }, [activeVersion])

  const ActiveComponent = VERSIONS[activeVersion]

  return (
    <>
      <div style={{
        opacity: fading ? 0 : 1,
        transition: 'opacity 0.12s ease',
      }}>
        <ActiveComponent />
      </div>
      <VersionSwitcher active={activeVersion} onChange={handleChange} />
    </>
  )
}

export default App
