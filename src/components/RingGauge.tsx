"use client";

interface RingGaugeProps {
  percent: number;
  color: string;
  value: string;
  unit: string;
  size?: number;
  glowColor?: string;
}

export default function RingGauge({
  percent,
  color,
  value,
  unit,
  size = 100,
  glowColor,
}: RingGaugeProps) {
  const clamped = Math.max(0, Math.min(100, percent || 0));
  const r = (size - 12) / 2;
  const circ = 2 * Math.PI * r;
  const offset = circ * (1 - clamped / 100);
  const glow = glowColor || color;

  return (
    <div
      className="ring-container"
      style={{ width: size, height: size, position: "relative" }}
    >
      <svg
        viewBox={`0 0 ${size} ${size}`}
        style={{ width: "100%", height: "100%", transform: "rotate(-90deg)" }}
      >
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke="var(--ring-track)"
          strokeWidth={6}
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          strokeWidth={6}
          strokeLinecap="round"
          strokeDasharray={circ}
          strokeDashoffset={offset}
          style={{
            transition: "stroke-dashoffset 1.5s cubic-bezier(0.4, 0, 0.2, 1)",
            filter: `drop-shadow(0 0 6px ${glow}66)`,
          }}
        />
      </svg>
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: "translate(-50%, -50%)",
          textAlign: "center",
        }}
      >
        <span
          className="font-mono"
          style={{
            fontSize: 20,
            fontWeight: 600,
            lineHeight: 1,
            color,
            textShadow: `0 0 8px ${glow}44`,
          }}
        >
          {value}
        </span>
        <span
          className="font-mono"
          style={{
            fontSize: 9,
            color: "var(--text-dim)",
            marginTop: 2,
            display: "block",
          }}
        >
          {unit}
        </span>
      </div>
    </div>
  );
}
