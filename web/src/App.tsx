import { useState } from 'react'
import { Sidebar } from './components/Sidebar'
import {
  GeneralSection,
  HotkeySection,
  ModelsSection,
  PermissionsSection,
  AdvancedSection,
  AboutSection,
} from './sections'
import { Waveform } from './components/Waveform'
import { AppSettings, SectionId } from './types'
import { Search } from 'lucide-react'

const INITIAL: AppSettings = {
  mode: 'normal',
  hotkeyMode: 'pushToTalk',
  cloudCleanup: false,
  model: 'smallEN',
  injection: 'pasteboard',
  permissions: {
    microphone: 'granted',
    accessibility: 'granted',
    inputMonitoring: 'notGranted',
  },
  hotkey: { keys: ['⌘', '⇧', 'Space'] },
}

export default function App() {
  const [section, setSection] = useState<SectionId>('general')
  const [settings, setSettings] = useState<AppSettings>(INITIAL)
  const [listening, setListening] = useState(false)

  const set = (patch: Partial<AppSettings>) =>
    setSettings((prev) => ({ ...prev, ...patch }))

  return (
    <>
      <div className="bg-aurora" />
      <div className="bg-grain" />

      <div className="relative z-10 flex h-screen w-screen text-bone-100">
        <Sidebar
          current={section}
          onChange={setSection}
          listening={listening}
          onToggleListen={() => setListening((v) => !v)}
        />

        <main className="relative flex-1 flex flex-col min-w-0">
          {/* Top bar */}
          <div className="flex items-center justify-between gap-6 px-12 pt-6 pb-2">
            <div className="flex items-center gap-3 text-bone-500">
              <Search size={14} strokeWidth={1.7} />
              <input
                placeholder="Search settings…"
                className="bg-transparent outline-none text-[13px] placeholder:text-bone-500 text-bone-200 w-72"
              />
              <span className="font-mono text-[10px] uppercase tracking-wider hairline rounded px-1.5 py-[1px]">
                ⌘K
              </span>
            </div>
            <div className="flex items-center gap-4 text-bone-500">
              <Waveform bars={14} active={listening} className="opacity-80" />
              <span className="font-mono text-[10.5px] uppercase tracking-[0.18em]">
                {listening ? 'Mic Active' : 'Mic Standby'}
              </span>
            </div>
          </div>

          <div className="px-12 pb-12 pt-4 overflow-y-auto scroll-thin flex-1">
            <div className="max-w-[820px] mx-auto">
              {section === 'general' && <GeneralSection s={settings} set={set} />}
              {section === 'hotkey' && <HotkeySection s={settings} set={set} />}
              {section === 'models' && <ModelsSection s={settings} set={set} />}
              {section === 'permissions' && <PermissionsSection s={settings} set={set} />}
              {section === 'advanced' && <AdvancedSection s={settings} set={set} />}
              {section === 'about' && <AboutSection listening={listening} />}
            </div>
          </div>
        </main>
      </div>
    </>
  )
}
