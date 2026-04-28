interface KeyCapProps {
  symbol: string
  size?: 'md' | 'lg'
  width?: 'auto' | 'wide'
  highlighted?: boolean
}

export function KeyCap({
  symbol,
  size = 'lg',
  width = 'auto',
  highlighted = false,
}: KeyCapProps) {
  const dim =
    size === 'lg'
      ? 'h-[78px] min-w-[78px] text-[32px]'
      : 'h-[44px] min-w-[44px] text-[18px]'
  const w = width === 'wide' ? (size === 'lg' ? 'min-w-[180px]' : 'min-w-[110px]') : ''

  return (
    <div
      className={`relative flex items-center justify-center rounded-xl ${dim} ${w} font-mono font-medium select-none transition-transform`}
      style={{
        background:
          'linear-gradient(180deg, #20202b 0%, #15151c 60%, #0e0e14 100%)',
        boxShadow:
          '0 1px 0 rgba(255,255,255,0.08) inset, 0 -3px 0 rgba(0,0,0,0.6) inset, 0 8px 22px rgba(0,0,0,0.55)',
      }}
    >
      {/* gradient ring on highlight */}
      {highlighted && (
        <span
          className="absolute -inset-px rounded-xl opacity-80"
          style={{
            background:
              'linear-gradient(135deg, rgba(183,111,255,0.6), rgba(255,108,182,0.6))',
            WebkitMask:
              'linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0)',
            WebkitMaskComposite: 'xor',
            maskComposite: 'exclude',
            padding: '1px',
          }}
        />
      )}
      <span
        className={
          highlighted
            ? 'text-gradient'
            : 'text-bone-100/95'
        }
      >
        {symbol}
      </span>
    </div>
  )
}
