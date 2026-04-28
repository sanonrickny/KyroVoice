import { SectionId } from '../types'
import {
  Settings2,
  Command,
  Cpu,
  ShieldCheck,
  SlidersHorizontal,
  Info,
  Circle,
} from 'lucide-react'
import { Waveform } from './Waveform'

interface NavItem {
  id: SectionId
  label: string
  number: string
  /** Lucide icons accept `size`/`strokeWidth` as string | number — keep this compatible. */
  icon: React.ComponentType<{
    size?: number | string
    strokeWidth?: number | string
    className?: string
  }>
}

const NAV: NavItem[] = [
  { id: 'general', label: 'General', number: '01', icon: Settings2 },
  { id: 'hotkey', label: 'Hotkey', number: '02', icon: Command },
  { id: 'models', label: 'Models', number: '03', icon: Cpu },
  { id: 'permissions', label: 'Permissions', number: '04', icon: ShieldCheck },
  { id: 'advanced', label: 'Advanced', number: '05', icon: SlidersHorizontal },
  { id: 'about', label: 'About', number: '06', icon: Info },
]

export function Sidebar({
  current,
  onChange,
  listening,
  onToggleListen,
}: {
  current: SectionId
  onChange: (s: SectionId) => void
  listening: boolean
  onToggleListen: () => void
}) {
  return (
    <aside className="relative z-20 flex h-full w-[284px] shrink-0 flex-col border-r border-white/[0.05] bg-ink-900/55 backdrop-blur-xl">
      {/* Top — app identity */}
      <div className="px-6 pt-7 pb-8">
        <div className="flex items-center gap-3.5">
          <div className="relative">
            <img
              src="/app-icon.png"
              alt="WisperFlo"
              className="h-12 w-12 rounded-[12px] shadow-[0_8px_24px_rgba(183,111,255,0.35)]"
            />
            <span className="absolute -inset-1 -z-10 rounded-[16px] bg-plum-rose opacity-30 blur-xl" />
          </div>
          <div className="min-w-0">
            <div className="font-display italic text-[26px] leading-none text-bone-100">
              WisperFlo
            </div>
            <div className="mt-1 font-mono text-[10.5px] uppercase tracking-[0.18em] text-bone-500">
              v0.2.1 · macOS
            </div>
          </div>
        </div>
      </div>

      {/* Section divider with label */}
      <div className="px-6 mb-2 flex items-center gap-3">
        <span className="font-mono text-[10px] uppercase tracking-[0.22em] text-bone-500">
          Settings
        </span>
        <span className="h-px flex-1 bg-white/[0.05]" />
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3">
        <ul className="space-y-0.5">
          {NAV.map((item) => {
            const active = item.id === current
            const Icon = item.icon
            return (
              <li key={item.id}>
                <button
                  onClick={() => onChange(item.id)}
                  className={`group relative flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-all duration-200 ${
                    active
                      ? 'bg-gradient-to-r from-white/[0.06] to-white/[0.02] text-bone-100'
                      : 'text-bone-400 hover:text-bone-200 hover:bg-white/[0.025]'
                  }`}
                >
                  {/* Active accent bar */}
                  <span
                    className={`absolute left-0 top-1/2 -translate-y-1/2 h-5 w-[2px] rounded-r-full bg-plum-rose transition-all duration-300 ${
                      active ? 'opacity-100' : 'opacity-0'
                    }`}
                  />
                  <span
                    className={`font-mono text-[10px] tracking-wider w-5 ${
                      active ? 'text-rose' : 'text-bone-500 group-hover:text-bone-400'
                    }`}
                  >
                    {item.number}
                  </span>
                  <Icon
                    size={15}
                    strokeWidth={1.6}
                    className={
                      active ? 'text-bone-100' : 'text-bone-400 group-hover:text-bone-200'
                    }
                  />
                  <span className="text-[13.5px] font-medium tracking-tight">
                    {item.label}
                  </span>
                </button>
              </li>
            )
          })}
        </ul>
      </nav>

      {/* Bottom — status */}
      <div className="px-3 pb-4">
        <button
          onClick={onToggleListen}
          className="lift hairline w-full rounded-xl bg-ink-800/70 px-4 py-3 text-left hover:border-white/15"
        >
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <span className="relative inline-flex h-2 w-2">
                <span
                  className={`absolute inline-flex h-full w-full rounded-full ${
                    listening ? 'bg-rose pulse-ring' : 'bg-bone-500'
                  }`}
                />
                <span
                  className={`relative inline-flex h-2 w-2 rounded-full ${
                    listening ? 'bg-rose' : 'bg-bone-500'
                  }`}
                />
              </span>
              <span className="font-mono text-[11px] uppercase tracking-[0.18em] text-bone-200">
                {listening ? 'Listening' : 'Idle'}
              </span>
            </div>
            <Waveform bars={9} active={listening} className="opacity-90" />
          </div>
          <div className="mt-2 flex items-center gap-1.5 text-[11px] text-bone-500">
            <Circle size={3.5} fill="currentColor" />
            <span>
              Hotkey · <span className="font-mono">⌘⇧Space</span>
            </span>
          </div>
        </button>
      </div>
    </aside>
  )
}
