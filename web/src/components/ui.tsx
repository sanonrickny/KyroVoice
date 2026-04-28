import { ReactNode } from 'react'

/* ───────── Toggle ───────── */

export function Toggle({
  checked,
  onChange,
  label,
}: {
  checked: boolean
  onChange: (v: boolean) => void
  label?: string
}) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      className={`relative h-[26px] w-[46px] shrink-0 rounded-full transition-all duration-300 outline-none ${
        checked
          ? 'bg-plum-rose shadow-glow'
          : 'bg-white/[0.06] hover:bg-white/[0.10]'
      }`}
    >
      <span
        className={`absolute top-[3px] h-5 w-5 rounded-full bg-white transition-all duration-300 ${
          checked
            ? 'left-[23px] shadow-[0_2px_6px_rgba(0,0,0,0.3)]'
            : 'left-[3px]'
        }`}
      />
    </button>
  )
}

/* ───────── Segmented control ───────── */

export interface SegOption<T extends string> {
  value: T
  label: string
  icon?: ReactNode
}

export function Segmented<T extends string>({
  value,
  onChange,
  options,
}: {
  value: T
  onChange: (v: T) => void
  options: SegOption<T>[]
}) {
  return (
    <div
      className="relative grid hairline rounded-xl p-[3px] bg-ink-700/60 backdrop-blur-sm"
      style={{ gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))` }}
    >
      {options.map((opt) => {
        const active = opt.value === value
        return (
          <button
            key={opt.value}
            onClick={() => onChange(opt.value)}
            className={`relative z-10 flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-[13px] font-medium tracking-tight transition-all duration-300 ${
              active
                ? 'text-bone-100 bg-gradient-to-b from-white/10 to-white/[0.04] shadow-[inset_0_1px_0_rgba(255,255,255,0.08)]'
                : 'text-bone-400 hover:text-bone-200'
            }`}
          >
            {opt.icon && (
              <span className={active ? 'text-rose' : 'opacity-70'}>
                {opt.icon}
              </span>
            )}
            {opt.label}
          </button>
        )
      })}
    </div>
  )
}

/* ───────── Row ───────── */

export function Row({
  label,
  hint,
  control,
  warn,
}: {
  label: string
  hint?: string
  control: ReactNode
  warn?: string
}) {
  return (
    <div className="grid grid-cols-[1fr_auto] items-start gap-6 py-5 border-b border-white/[0.04] last:border-b-0">
      <div className="min-w-0">
        <div className="text-[14px] font-medium text-bone-100 tracking-tight">
          {label}
        </div>
        {hint && (
          <div className="mt-1 text-[12.5px] text-bone-400 leading-relaxed max-w-[460px]">
            {hint}
          </div>
        )}
        {warn && (
          <div className="mt-2 inline-flex items-center gap-1.5 text-[11.5px] text-amber/90 font-mono uppercase tracking-wider">
            <span className="h-[5px] w-[5px] rounded-full bg-amber" />
            {warn}
          </div>
        )}
      </div>
      <div className="shrink-0 pt-[2px]">{control}</div>
    </div>
  )
}

/* ───────── Status pill ───────── */

export function StatusPill({
  granted,
}: {
  granted: boolean
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full pl-2 pr-2.5 py-[3px] text-[11px] font-mono uppercase tracking-wider ${
        granted
          ? 'bg-mint/10 text-mint border border-mint/20'
          : 'bg-amber/10 text-amber border border-amber/20'
      }`}
    >
      <span
        className={`h-[6px] w-[6px] rounded-full ${
          granted ? 'bg-mint' : 'bg-amber'
        }`}
      />
      {granted ? 'Granted' : 'Not granted'}
    </span>
  )
}

/* ───────── Buttons ───────── */

export function GhostButton({
  children,
  onClick,
}: {
  children: ReactNode
  onClick?: () => void
}) {
  return (
    <button
      onClick={onClick}
      className="lift hairline rounded-lg px-3.5 py-1.5 text-[12.5px] font-medium text-bone-200 hover:bg-white/[0.04] hover:border-white/15 active:scale-[0.98]"
    >
      {children}
    </button>
  )
}

export function PrimaryButton({
  children,
  onClick,
}: {
  children: ReactNode
  onClick?: () => void
}) {
  return (
    <button
      onClick={onClick}
      className="lift relative rounded-lg px-4 py-1.5 text-[12.5px] font-semibold text-white bg-plum-rose shadow-glow active:scale-[0.98]"
    >
      <span className="relative z-10">{children}</span>
      <span className="absolute inset-0 rounded-lg bg-white/0 hover:bg-white/10 transition-colors" />
    </button>
  )
}

/* ───────── Card ───────── */

export function Panel({
  children,
  className = '',
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <div
      className={`hairline rounded-2xl bg-ink-700/40 backdrop-blur-sm px-6 ${className}`}
    >
      {children}
    </div>
  )
}
