interface WaveformProps {
  bars?: number
  active?: boolean
  className?: string
}

const HEIGHTS = [0.45, 0.8, 0.6, 1, 0.5, 0.9, 0.65, 0.4, 0.85, 0.55, 0.7, 0.35]

export function Waveform({ bars = 12, active = true, className = '' }: WaveformProps) {
  return (
    <div className={`flex items-center gap-[3px] h-5 ${className}`}>
      {Array.from({ length: bars }).map((_, i) => (
        <span
          key={i}
          className={`block w-[2px] rounded-full bg-gradient-to-b from-plum to-rose ${
            active ? 'wf-bar' : ''
          }`}
          style={{
            height: `${(HEIGHTS[i % HEIGHTS.length] ?? 0.5) * 100}%`,
            animationDelay: `${i * 90}ms`,
            opacity: active ? 1 : 0.35,
          }}
        />
      ))}
    </div>
  )
}
