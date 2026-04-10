// Picks a status color for a "lower is better" metric.
// Under 80% returns the provided base color (the metric's normal accent);
// 80-95% returns yellow; above 95% returns red.
export function healthColor(
  percent: number,
  baseColor: string = "var(--status-running)"
): string {
  if (percent > 95) return "var(--status-error)";
  if (percent > 80) return "var(--status-warn)";
  return baseColor;
}
