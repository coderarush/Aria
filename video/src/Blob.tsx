import React from "react";
import { useCurrentFrame, useVideoConfig } from "remotion";

// Aria's body — the same layered-sine morphing outline as the app and the
// website, rendered as an SVG path recomputed every frame.
function radii(t: number, n: number, amp: number, speed: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < n; i++) {
    const w =
      0.6 * Math.sin(t * speed + i * 0.9) +
      0.3 * Math.sin(t * speed * 1.7 + i * 1.7) +
      0.1 * Math.sin(t * speed * 0.5 + i * 2.3);
    out.push(1 + amp * w);
  }
  return out;
}

function blobPath(size: number, rad: number[], breathe: number): string {
  const n = rad.length;
  const cx = size / 2;
  const cy = size / 2;
  const base = (size / 2) * 0.62 * breathe;
  const pt = (i: number): [number, number] => {
    const idx = ((i % n) + n) % n;
    const ang = (2 * Math.PI * idx) / n - Math.PI / 2;
    const r = base * rad[idx];
    return [cx + Math.cos(ang) * r, cy + Math.sin(ang) * r];
  };
  let d = `M ${pt(0)[0]} ${pt(0)[1]}`;
  for (let i = 0; i < n; i++) {
    const p0 = pt(i - 1), p1 = pt(i), p2 = pt(i + 1), p3 = pt(i + 2);
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    d += ` C ${c1[0]} ${c1[1]}, ${c2[0]} ${c2[1]}, ${p2[0]} ${p2[1]}`;
  }
  return d + " Z";
}

export const Blob: React.FC<{
  size: number;
  amp?: number;     // wobble amount (mood)
  speed?: number;   // morph speed (mood)
  breatheAmt?: number;
  style?: React.CSSProperties;
}> = ({ size, amp = 0.1, speed = 0.8, breatheAmt = 0.015, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const breathe = 1 + breatheAmt * Math.sin(t * 1.1);
  const d = blobPath(size, radii(t, 11, amp, speed), breathe);
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={style}>
      <defs>
        <linearGradient id="body" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#23201a" />
          <stop offset="1" stopColor="#080706" />
        </linearGradient>
        <radialGradient id="sheen" cx="0.38" cy="0.3" r="0.7">
          <stop offset="0" stopColor="rgba(255,255,255,0.18)" />
          <stop offset="1" stopColor="rgba(255,255,255,0)" />
        </radialGradient>
      </defs>
      <path d={d} fill="url(#body)" />
      <path d={d} fill="url(#sheen)" />
    </svg>
  );
};
