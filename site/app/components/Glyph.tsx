// Source icons drawn to match the ones Desktop Buddy shows on each notification.

export type GlyphKind = "mail" | "chat" | "calendar" | "tasks" | "reminder";

export function Glyph({ kind, size = 36 }: { kind: GlyphKind; size?: number }) {
  const common = { width: size, height: size, viewBox: "0 0 36 36", "aria-hidden": true } as const;

  switch (kind) {
    case "mail":
      return (
        <svg {...common}>
          <rect width="36" height="36" rx="8" fill="#1F8BF5" />
          <rect x="8" y="11" width="20" height="14" rx="2.5" fill="none" stroke="#fff" strokeWidth="2" />
          <path d="M9 12.5l9 7 9-7" fill="none" stroke="#fff" strokeWidth="2" strokeLinejoin="round" />
        </svg>
      );
    case "chat":
      return (
        <svg {...common}>
          <rect width="36" height="36" rx="8" fill="#30C25A" />
          <path d="M9 11.5h12a2 2 0 012 2v6a2 2 0 01-2 2h-7l-4 3v-3h-1a2 2 0 01-2-2v-6a2 2 0 012-2z" fill="#fff" />
          <path d="M25 15h1a2 2 0 012 2v6a2 2 0 01-2 2h-1v3l-3.5-3H17" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinejoin="round" />
        </svg>
      );
    case "calendar":
      return (
        <svg {...common}>
          <rect width="36" height="36" rx="8" fill="#fff" />
          <rect x="0.5" y="0.5" width="35" height="35" rx="7.5" fill="none" stroke="rgba(0,0,0,.12)" />
          <text x="18" y="12.5" textAnchor="middle" fontSize="6.5" fontWeight="700" fill="#E5483B" fontFamily="system-ui, sans-serif" letterSpacing=".04em">TUE</text>
          <text x="18" y="28" textAnchor="middle" fontSize="15" fontWeight="500" fill="#1d1d1f" fontFamily="system-ui, sans-serif">27</text>
        </svg>
      );
    case "tasks":
      return (
        <svg {...common}>
          <rect width="36" height="36" rx="8" fill="#FF8A2B" />
          <circle cx="12" cy="13" r="2.6" fill="none" stroke="#fff" strokeWidth="1.8" />
          <circle cx="12" cy="23" r="2.6" fill="none" stroke="#fff" strokeWidth="1.8" />
          <path d="M17.5 13H27M17.5 23H27" stroke="#fff" strokeWidth="2" strokeLinecap="round" />
        </svg>
      );
    case "reminder":
      return (
        <svg {...common}>
          <rect width="36" height="36" rx="8" fill="#22C3CF" />
          <path d="M18 9.5a6 6 0 00-6 6v4.2l-2 3h16l-2-3v-4.2a6 6 0 00-6-6z" fill="#fff" />
          <path d="M15.6 24.6a2.5 2.5 0 004.8 0" fill="#fff" />
        </svg>
      );
  }
}

/** A made-up client logo for the demo, drawn rather than borrowed. */
export function SampleClientMark({ size = 36 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 36 36" aria-hidden="true">
      <rect width="36" height="36" rx="8" fill="#fff" />
      <rect x="0.5" y="0.5" width="35" height="35" rx="7.5" fill="none" stroke="rgba(0,0,0,.1)" />
      <path d="M10 27V11h4v6.5h8V11h4v16h-4v-6h-8v6z" fill="#1F4D3A" />
      <circle cx="18" cy="9" r="3" fill="#C9A227" />
    </svg>
  );
}

export function BellIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" aria-hidden="true">
      <path d="M8 1.75a4.25 4.25 0 00-4.25 4.25v2.9L2.4 11h11.2l-1.35-2.1V6A4.25 4.25 0 008 1.75z" fill="currentColor" />
      <path d="M6.2 12.4a1.85 1.85 0 003.6 0z" fill="currentColor" />
    </svg>
  );
}
