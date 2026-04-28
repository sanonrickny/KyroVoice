import { useState } from 'react'
import {
  AlignLeft,
  Mail,
  Code2,
  Mic,
  Accessibility,
  KeySquare,
  HardDrive,
  Zap,
  Check,
  Download,
  ExternalLink,
  Sparkles,
  ShieldCheck,
} from 'lucide-react'
import {
  Toggle,
  Segmented,
  Row,
  StatusPill,
  GhostButton,
  PrimaryButton,
  Panel,
} from './components/ui'
import { KeyCap } from './components/KeyCap'
import { AppSettings, DictationMode, HotkeyMode, InjectionStrategy, ModelVariant } from './types'

/* ========== shared header ========== */

export function SectionTitle({
  number,
  kicker,
  title,
  subtitle,
}: {
  number: string
  kicker: string
  title: string
  subtitle: string
}) {
  return (
    <header className="mb-10">
      <div className="flex items-center gap-3 text-bone-500 font-mono text-[10.5px] uppercase tracking-[0.22em] mb-5">
        <span>{number}</span>
        <span className="h-px w-8 bg-white/[0.12]" />
        <span>{kicker}</span>
      </div>
      <h1 className="font-display italic text-bone-100 leading-[0.95] text-[64px] tracking-tight">
        {title}
      </h1>
      <p className="mt-4 max-w-[520px] text-[14px] text-bone-400 leading-relaxed">
        {subtitle}
      </p>
    </header>
  )
}

/* ========== General ========== */

export function GeneralSection({
  s,
  set,
}: {
  s: AppSettings
  set: (patch: Partial<AppSettings>) => void
}) {
  return (
    <div className="section-in">
      <SectionTitle
        number="01"
        kicker="General"
        title="How it speaks."
        subtitle="Choose the default writing mode and how the dictation hotkey behaves while you talk."
      />

      <Panel>
        <Row
          label="Default mode"
          hint="Tunes punctuation, capitalization, and tone of the post-processed transcription."
          control={
            <Segmented<DictationMode>
              value={s.mode}
              onChange={(v) => set({ mode: v })}
              options={[
                { value: 'normal', label: 'Normal', icon: <AlignLeft size={14} strokeWidth={1.7} /> },
                { value: 'email', label: 'Email', icon: <Mail size={14} strokeWidth={1.7} /> },
                { value: 'code', label: 'Code', icon: <Code2 size={14} strokeWidth={1.7} /> },
              ]}
            />
          }
        />

        <Row
          label="Hotkey behavior"
          hint="Push to talk records only while held. Tap to toggle starts and stops on each press."
          control={
            <Segmented<HotkeyMode>
              value={s.hotkeyMode}
              onChange={(v) => set({ hotkeyMode: v })}
              options={[
                { value: 'pushToTalk', label: 'Push to talk' },
                { value: 'toggle', label: 'Tap to toggle' },
              ]}
            />
          }
        />

        <Row
          label="Cloud AI cleanup"
          hint="Polishes filler words, restores punctuation, and applies the selected mode using a hosted model."
          warn="Sends transcribed text to API"
          control={
            <Toggle
              checked={s.cloudCleanup}
              onChange={(v) => set({ cloudCleanup: v })}
              label="Enable cloud cleanup"
            />
          }
        />
      </Panel>
    </div>
  )
}

/* ========== Hotkey ========== */

export function HotkeySection({ s, set }: { s: AppSettings; set: (p: Partial<AppSettings>) => void }) {
  const [recording, setRecording] = useState(false)
  const keys = s.hotkey.keys

  return (
    <div className="section-in">
      <SectionTitle
        number="02"
        kicker="Hotkey"
        title="One press, one thought."
        subtitle="Bind the chord that wakes the microphone. Try any combination — modifier-only chords are allowed."
      />

      <div className="hairline rounded-2xl bg-ink-700/40 backdrop-blur-sm p-10">
        {/* The keycap row */}
        <div className="flex items-end justify-center gap-3 py-6">
          {keys.map((k, i) => (
            <KeyCap
              key={i}
              symbol={k}
              size="lg"
              width={k === 'Space' ? 'wide' : 'auto'}
              highlighted={recording}
            />
          ))}
        </div>

        <div className="mt-8 flex flex-col items-center gap-4">
          {recording ? (
            <div className="flex items-center gap-3">
              <span className="relative flex h-2.5 w-2.5">
                <span className="absolute inline-flex h-full w-full rounded-full bg-rose pulse-ring" />
                <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-rose" />
              </span>
              <span className="font-mono text-[11.5px] uppercase tracking-[0.22em] text-rose">
                Listening for chord…
              </span>
            </div>
          ) : (
            <div className="font-mono text-[11px] uppercase tracking-[0.22em] text-bone-500">
              Current binding
            </div>
          )}
          <div className="flex gap-3">
            {recording ? (
              <>
                <GhostButton onClick={() => setRecording(false)}>Cancel</GhostButton>
                <PrimaryButton
                  onClick={() => {
                    set({ hotkey: { keys: ['⌃', '⌥', 'F'] } })
                    setRecording(false)
                  }}
                >
                  Capture & save
                </PrimaryButton>
              </>
            ) : (
              <>
                <GhostButton
                  onClick={() => set({ hotkey: { keys: ['⌘', '⇧', 'Space'] } })}
                >
                  Reset to default
                </GhostButton>
                <PrimaryButton onClick={() => setRecording(true)}>
                  Record new shortcut
                </PrimaryButton>
              </>
            )}
          </div>
        </div>
      </div>

      <p className="mt-6 max-w-[520px] text-[12.5px] text-bone-500 leading-relaxed flex items-start gap-2">
        <KeySquare size={13} strokeWidth={1.7} className="mt-[2px] shrink-0 text-bone-400" />
        Conflicts with system shortcuts will be flagged before saving. Function keys
        and the globe key are supported on Apple Silicon.
      </p>
    </div>
  )
}

/* ========== Models ========== */

const MODELS: {
  id: ModelVariant
  name: string
  size: string
  speed: number
  recommended?: boolean
  blurb: string
}[] = [
  {
    id: 'baseEN',
    name: 'Whisper Base · English',
    size: '≈ 75 MB',
    speed: 3,
    blurb: 'Fastest local model. Great for short utterances, casual notes, and chat.',
  },
  {
    id: 'smallEN',
    name: 'Whisper Small · English',
    size: '≈ 250 MB',
    speed: 2,
    recommended: true,
    blurb: 'Best accuracy for everyday writing. Recommended for emails and prose.',
  },
]

export function ModelsSection({ s, set }: { s: AppSettings; set: (p: Partial<AppSettings>) => void }) {
  return (
    <div className="section-in">
      <SectionTitle
        number="03"
        kicker="Models"
        title="On-device weights."
        subtitle="Choose the Whisper variant that runs locally. Audio never leaves your machine."
      />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {MODELS.map((m) => {
          const selected = s.model === m.id
          const downloaded = m.id === 'smallEN'
          return (
            <button
              key={m.id}
              onClick={() => set({ model: m.id })}
              className={`group lift relative text-left overflow-hidden rounded-2xl p-6 transition-all duration-300 ${
                selected
                  ? 'bg-gradient-to-br from-plum/[0.10] via-ink-700/60 to-rose/[0.06] border border-plum/30 shadow-glow'
                  : 'bg-ink-700/40 hairline hover:border-white/15'
              }`}
            >
              {/* Recommended ribbon */}
              {m.recommended && (
                <span className="absolute top-5 right-5 inline-flex items-center gap-1 rounded-full border border-plum/30 bg-plum/10 pl-2 pr-2.5 py-[3px] text-[10px] font-mono uppercase tracking-wider text-plum">
                  <Sparkles size={10} strokeWidth={2} />
                  Recommended
                </span>
              )}

              {/* Radio */}
              <div className="flex items-center gap-3 mb-5">
                <span
                  className={`relative grid place-items-center h-5 w-5 rounded-full border transition-all ${
                    selected ? 'border-rose bg-plum-rose' : 'border-bone-500'
                  }`}
                >
                  {selected && <Check size={11} strokeWidth={3} className="text-white" />}
                </span>
                <HardDrive size={14} strokeWidth={1.7} className="text-bone-400" />
                <span className="font-mono text-[10.5px] uppercase tracking-[0.18em] text-bone-400">
                  {m.size}
                </span>
              </div>

              <div className="font-display italic text-[28px] leading-[1.05] text-bone-100">
                {m.name}
              </div>
              <p className="mt-3 text-[13px] text-bone-400 leading-relaxed">
                {m.blurb}
              </p>

              {/* Footer */}
              <div className="mt-6 flex items-center justify-between">
                <div className="flex items-center gap-1.5 text-bone-400">
                  <Zap size={12} strokeWidth={1.8} />
                  <span className="font-mono text-[10.5px] uppercase tracking-wider">Speed</span>
                  <div className="ml-1 flex gap-[3px]">
                    {[1, 2, 3].map((n) => (
                      <span
                        key={n}
                        className={`block h-[5px] w-[5px] rounded-full ${
                          n <= m.speed ? 'bg-gradient-to-r from-plum to-rose' : 'bg-white/[0.08]'
                        }`}
                      />
                    ))}
                  </div>
                </div>
                {downloaded ? (
                  <span className="inline-flex items-center gap-1.5 text-[11px] font-mono uppercase tracking-wider text-mint">
                    <Check size={11} strokeWidth={2.4} />
                    Downloaded
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1.5 text-[11px] font-mono uppercase tracking-wider text-bone-300">
                    <Download size={11} strokeWidth={2} />
                    Download
                  </span>
                )}
              </div>
            </button>
          )
        })}
      </div>

      <p className="mt-8 text-[12.5px] text-bone-500 leading-relaxed max-w-[520px]">
        Models are stored at{' '}
        <span className="font-mono text-bone-300">~/Library/Application Support/KyroVoice/Models</span>.
      </p>
    </div>
  )
}

/* ========== Permissions ========== */

const PERMS: {
  key: keyof AppSettings['permissions']
  label: string
  hint: string
  icon: React.ComponentType<{
    size?: number | string
    strokeWidth?: number | string
    className?: string
  }>
}[] = [
  {
    key: 'microphone',
    label: 'Microphone',
    hint: 'Required to capture audio when the hotkey is pressed.',
    icon: Mic,
  },
  {
    key: 'accessibility',
    label: 'Accessibility',
    hint: 'Lets WisperFlo paste transcribed text into the focused field.',
    icon: Accessibility,
  },
  {
    key: 'inputMonitoring',
    label: 'Input Monitoring',
    hint: 'Required for global hotkey detection across every app.',
    icon: KeySquare,
  },
]

export function PermissionsSection({
  s,
  set,
}: {
  s: AppSettings
  set: (p: Partial<AppSettings>) => void
}) {
  return (
    <div className="section-in">
      <SectionTitle
        number="04"
        kicker="Permissions"
        title="What macOS lets us do."
        subtitle="WisperFlo only requests what it needs to capture audio and write text into your active app."
      />

      <Panel className="py-2">
        {PERMS.map((p, i) => {
          const Icon = p.icon
          const granted = s.permissions[p.key] === 'granted'
          return (
            <div
              key={p.key}
              className={`group flex items-center gap-5 py-5 transition-colors ${
                i !== PERMS.length - 1 ? 'border-b border-white/[0.04]' : ''
              }`}
            >
              <div className="grid place-items-center h-10 w-10 rounded-xl hairline bg-ink-800/60 group-hover:border-white/15 transition-all">
                <Icon size={16} strokeWidth={1.6} className="text-bone-200" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-3">
                  <span className="text-[14px] font-medium text-bone-100">{p.label}</span>
                  <StatusPill granted={granted} />
                </div>
                <div className="mt-1 text-[12.5px] text-bone-400">{p.hint}</div>
              </div>
              <div className="flex shrink-0 gap-2">
                {granted ? (
                  <GhostButton
                    onClick={() =>
                      set({
                        permissions: { ...s.permissions, [p.key]: 'notGranted' },
                      })
                    }
                  >
                    <span className="inline-flex items-center gap-1.5">
                      <ExternalLink size={12} strokeWidth={1.8} />
                      Open Settings
                    </span>
                  </GhostButton>
                ) : (
                  <PrimaryButton
                    onClick={() =>
                      set({
                        permissions: { ...s.permissions, [p.key]: 'granted' },
                      })
                    }
                  >
                    Request access
                  </PrimaryButton>
                )}
              </div>
            </div>
          )
        })}
      </Panel>

      <div className="mt-5 flex items-center justify-between text-[12px] text-bone-500">
        <span className="inline-flex items-center gap-2">
          <ShieldCheck size={13} strokeWidth={1.7} />
          Audio and text never leave your Mac unless Cloud cleanup is enabled.
        </span>
        <button className="font-mono uppercase tracking-wider text-[10.5px] text-bone-400 hover:text-bone-200 transition">
          Refresh ↻
        </button>
      </div>
    </div>
  )
}

/* ========== Advanced ========== */

const STRATEGIES: { id: InjectionStrategy; name: string; tagline: string; hint: string }[] = [
  {
    id: 'pasteboard',
    name: 'Pasteboard + ⌘V',
    tagline: 'Recommended',
    hint: 'Works in nearly every app — Slack, Chrome, VS Code, Notion. Briefly touches the clipboard.',
  },
  {
    id: 'accessibility',
    name: 'Accessibility',
    tagline: 'Experimental',
    hint: 'Faster in native Cocoa apps but unreliable in Electron and certain editors.',
  },
  {
    id: 'auto',
    name: 'Auto',
    tagline: 'Try AX, fall back',
    hint: 'Attempts Accessibility first; quietly falls back to pasteboard when it fails.',
  },
]

export function AdvancedSection({
  s,
  set,
}: {
  s: AppSettings
  set: (p: Partial<AppSettings>) => void
}) {
  return (
    <div className="section-in">
      <SectionTitle
        number="05"
        kicker="Advanced"
        title="The quiet machinery."
        subtitle="How WisperFlo delivers the transcribed text into the field you're typing into."
      />

      <Panel>
        <div className="py-5">
          <div className="text-[14px] font-medium text-bone-100 tracking-tight">
            Text injection strategy
          </div>
          <div className="mt-1 text-[12.5px] text-bone-400 max-w-[520px] leading-relaxed">
            If text occasionally arrives garbled or out of order, switch strategies.
          </div>

          <div className="mt-5 space-y-2">
            {STRATEGIES.map((opt) => {
              const selected = s.injection === opt.id
              return (
                <button
                  key={opt.id}
                  onClick={() => set({ injection: opt.id })}
                  className={`group flex w-full items-start gap-4 rounded-xl px-4 py-3.5 text-left transition-all duration-200 ${
                    selected
                      ? 'bg-gradient-to-r from-plum/10 to-transparent border border-plum/30'
                      : 'border border-transparent hover:bg-white/[0.025]'
                  }`}
                >
                  <span
                    className={`mt-[3px] grid place-items-center h-4 w-4 rounded-full border transition-all ${
                      selected
                        ? 'border-rose bg-plum-rose shadow-[0_0_0_4px_rgba(255,108,182,0.10)]'
                        : 'border-bone-500'
                    }`}
                  >
                    {selected && <span className="block h-1.5 w-1.5 rounded-full bg-white" />}
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2.5">
                      <span className="text-[13.5px] font-medium text-bone-100">
                        {opt.name}
                      </span>
                      <span
                        className={`font-mono text-[10px] uppercase tracking-wider ${
                          selected ? 'text-rose' : 'text-bone-500'
                        }`}
                      >
                        · {opt.tagline}
                      </span>
                    </div>
                    <div className="mt-1 text-[12.5px] text-bone-400 leading-relaxed">
                      {opt.hint}
                    </div>
                  </div>
                </button>
              )
            })}
          </div>
        </div>
      </Panel>
    </div>
  )
}

/* ========== About ========== */

export function AboutSection({ listening }: { listening: boolean }) {
  return (
    <div className="section-in">
      <SectionTitle
        number="06"
        kicker="About"
        title="WisperFlo."
        subtitle="Local voice dictation for macOS. Built native in Swift + SwiftUI; transcription runs entirely on your device."
      />

      <div className="grid grid-cols-1 lg:grid-cols-[1.1fr_1fr] gap-4">
        <Panel className="py-7">
          <div className="flex items-center gap-5">
            <div className="relative">
              <img
                src="/app-icon.png"
                alt=""
                className="h-20 w-20 rounded-[18px] shadow-[0_12px_36px_rgba(183,111,255,0.4)]"
              />
              <span className="absolute -inset-2 -z-10 rounded-[24px] bg-plum-rose opacity-30 blur-2xl" />
            </div>
            <div>
              <div className="font-display italic text-[36px] leading-none text-bone-100">
                WisperFlo
              </div>
              <div className="mt-2 font-mono text-[11px] uppercase tracking-[0.22em] text-bone-500">
                v0.2.1 · darwin · arm64
              </div>
              <div className="mt-3 text-[13.5px] text-bone-300 max-w-[320px] leading-relaxed">
                Press, talk, watch the words appear in the app you were already using.
              </div>
            </div>
          </div>

          <div className="mt-7 grid grid-cols-2 gap-3">
            <a className="lift hairline rounded-xl px-4 py-3 hover:border-white/15">
              <div className="font-mono text-[10px] uppercase tracking-wider text-bone-500">
                Source
              </div>
              <div className="mt-1 text-[13px] text-bone-100">github.com/wisperflo</div>
            </a>
            <a className="lift hairline rounded-xl px-4 py-3 hover:border-white/15">
              <div className="font-mono text-[10px] uppercase tracking-wider text-bone-500">
                Updates
              </div>
              <div className="mt-1 text-[13px] text-bone-100">Check for updates</div>
            </a>
          </div>
        </Panel>

        <Panel className="py-7">
          <div className="font-mono text-[10px] uppercase tracking-[0.22em] text-bone-500 mb-3">
            Live status
          </div>
          <div className="flex items-baseline gap-3">
            <div className="font-display italic text-[44px] leading-none text-bone-100">
              {listening ? 'Listening' : 'Idle'}
            </div>
            <span className="relative inline-flex h-2.5 w-2.5">
              <span
                className={`absolute inline-flex h-full w-full rounded-full ${
                  listening ? 'bg-rose pulse-ring' : 'bg-bone-500'
                }`}
              />
              <span
                className={`relative inline-flex h-2.5 w-2.5 rounded-full ${
                  listening ? 'bg-rose' : 'bg-bone-500'
                }`}
              />
            </span>
          </div>

          <div className="mt-6 space-y-3 text-[13px]">
            <KV k="Engine" v="whisper.cpp · Metal" />
            <KV k="Model loaded" v="small.en (244 MB)" />
            <KV k="Latency" v={listening ? '218 ms' : '—'} />
            <KV k="Words today" v="3,418" />
          </div>
        </Panel>
      </div>

      <div className="mt-6 text-[11px] text-bone-500 font-mono uppercase tracking-[0.18em]">
        © 2026 WisperFlo · Made for people who think faster than they type.
      </div>
    </div>
  )
}

function KV({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex items-center justify-between border-b border-white/[0.04] pb-3 last:border-b-0">
      <span className="text-bone-400">{k}</span>
      <span className="font-mono text-bone-100">{v}</span>
    </div>
  )
}
