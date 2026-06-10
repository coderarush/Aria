import { useRef, useEffect } from "react";

// Same morphing math as the macOS app (BlobMath): per-vertex radii wobbling with
// layered sine noise, drawn as a smooth Catmull-Rom closed curve. This is Aria's body.
function radii(t, n, amp, speed) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = i;
    const w =
      0.6 * Math.sin(t * speed + a * 0.9) +
      0.3 * Math.sin(t * speed * 1.7 + a * 1.7) +
      0.1 * Math.sin(t * speed * 0.5 + a * 2.3);
    out.push(1 + amp * w);
  }
  return out;
}

function trace(ctx, cx, cy, base, rad) {
  const n = rad.length;
  const pt = (i) => {
    const idx = ((i % n) + n) % n;
    const ang = (2 * Math.PI * idx) / n - Math.PI / 2;
    const r = base * rad[idx];
    return [cx + Math.cos(ang) * r, cy + Math.sin(ang) * r];
  };
  ctx.beginPath();
  const s = pt(0);
  ctx.moveTo(s[0], s[1]);
  for (let i = 0; i < n; i++) {
    const p0 = pt(i - 1), p1 = pt(i), p2 = pt(i + 1), p3 = pt(i + 2);
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    ctx.bezierCurveTo(c1[0], c1[1], c2[0], c2[1], p2[0], p2[1]);
  }
  ctx.closePath();
}

// Blob states from the website constitution: motion is meaning, never decoration.
// idle = subtle breathing · listening = slight expansion + ripple · thinking =
// organic morphing, faster · executing = energy radiating outward · calm =
// settled, near-still · confident = fully alive, easy breathing.
const MOODS = {
  idle:      { amp: 0.10, speed: 0.70, breathe: 0.012 },
  listening: { amp: 0.16, speed: 0.95, breathe: 0.020 },
  thinking:  { amp: 0.13, speed: 1.60, breathe: 0.010 },
  executing: { amp: 0.20, speed: 1.25, breathe: 0.016 },
  calm:      { amp: 0.055, speed: 0.45, breathe: 0.008 },
  confident: { amp: 0.12, speed: 0.80, breathe: 0.030 },
};

export default function Blob({ size = 440, mood = "idle" }) {
  const ref = useRef(null);
  const mouse = useRef({ x: 0.42, y: 0.34 });
  const moodRef = useRef(mood);
  moodRef.current = mood;

  useEffect(() => {
    const canvas = ref.current;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = size * dpr;
    canvas.height = size * dpr;
    const ctx = canvas.getContext("2d");
    ctx.scale(dpr, dpr);

    const onMove = (e) => {
      const r = canvas.getBoundingClientRect();
      mouse.current.x = (e.clientX - r.left) / r.width;
      mouse.current.y = (e.clientY - r.top) / r.height;
    };
    window.addEventListener("pointermove", onMove);

    let raf;
    const start = performance.now();
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Live parameters ease toward the active mood — transitions read as the
    // blob changing its mind, not as a cut.
    const live = { ...MOODS[moodRef.current] || MOODS.idle };

    const draw = () => {
      const t = reduce ? 0.6 : (performance.now() - start) / 1000;
      const target = MOODS[moodRef.current] || MOODS.idle;
      const k = 0.04; // lerp factor — slow, organic settle
      live.amp += (target.amp - live.amp) * k;
      live.speed += (target.speed - live.speed) * k;
      live.breathe += (target.breathe - live.breathe) * k;

      ctx.clearRect(0, 0, size, size);
      const cx = size / 2;
      const cy = size / 2;
      const breathe = 1 + live.breathe * Math.sin(t * 1.1);
      const base = (size / 2) * 0.6 * breathe;
      const rad = radii(t, 11, live.amp, live.speed);

      // Body — warm near-black, like the reference blobs.
      trace(ctx, cx, cy, base, rad);
      const g = ctx.createLinearGradient(cx - base, cy - base, cx + base, cy + base);
      g.addColorStop(0, "#23201a");
      g.addColorStop(1, "#080706");
      ctx.fillStyle = g;
      ctx.fill();

      // Gel highlight that drifts toward the cursor.
      const hx = cx + (mouse.current.x - 0.5) * base * 0.6;
      const hy = cy + (mouse.current.y - 0.5) * base * 0.5;
      trace(ctx, cx, cy, base, rad);
      const hg = ctx.createRadialGradient(hx, hy, 2, hx, hy, base * 0.95);
      hg.addColorStop(0, "rgba(255,255,255,0.16)");
      hg.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = hg;
      ctx.fill();

      if (!reduce) raf = requestAnimationFrame(draw);
    };
    draw();

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", onMove);
    };
  }, [size]);

  return <canvas ref={ref} style={{ width: size, height: size }} aria-hidden="true" />;
}
