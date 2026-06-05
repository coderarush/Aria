import { useRef, useEffect } from "react";

/* The signature: a living "voice" — a breathing aurora core inside a reactive
   waveform ring, drawn on canvas. This is the one thing people remember. */
export default function VoiceOrb({ size = 360 }) {
  const ref = useRef(null);
  useEffect(() => {
    const cv = ref.current;
    const ctx = cv.getContext("2d");
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    let raf, t = 0, w = 0, h = 0, mx = 0, my = 0;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const resize = () => { const s = cv.clientWidth; cv.width = s * dpr; cv.height = s * dpr; w = cv.width; h = cv.height; };
    resize();
    window.addEventListener("resize", resize);
    const onMove = (e) => { const r = cv.getBoundingClientRect(); mx = (e.clientX - r.left - r.width / 2) / r.width; my = (e.clientY - r.top - r.height / 2) / r.height; };
    window.addEventListener("mousemove", onMove);

    const cols = ["#8b5cff", "#34c8ff", "#ff5fb0"];
    const draw = () => {
      t += reduce ? 0 : 0.016;
      ctx.clearRect(0, 0, w, h);
      const cx = w / 2 + mx * w * 0.04, cy = h / 2 + my * h * 0.04, R = Math.min(w, h) * 0.26;

      // drifting aurora light, additive
      ctx.globalCompositeOperation = "screen";
      for (let i = 0; i < 3; i++) {
        const a = t * 0.5 + i * 2.094;
        const x = cx + Math.cos(a) * R * 0.55, y = cy + Math.sin(a * 1.3) * R * 0.55;
        const g = ctx.createRadialGradient(x, y, 0, x, y, R * 1.7);
        g.addColorStop(0, cols[i] + "bb"); g.addColorStop(1, "transparent");
        ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, R * 1.7, 0, 7); ctx.fill();
      }

      // reactive waveform ring
      ctx.globalCompositeOperation = "source-over";
      const bars = 84;
      for (let i = 0; i < bars; i++) {
        const ang = (i / bars) * Math.PI * 2;
        const amp = 0.45 + 0.4 * Math.sin(t * 3 + i * 0.5) + 0.25 * Math.sin(t * 1.7 + i * 0.27);
        const r1 = R * 1.18, r2 = r1 + R * 0.2 * Math.max(0, amp);
        ctx.strokeStyle = `rgba(255,255,255,${0.18 + 0.5 * Math.max(0, amp) / 1.1})`;
        ctx.lineWidth = dpr * 2.2;
        ctx.beginPath();
        ctx.moveTo(cx + Math.cos(ang) * r1, cy + Math.sin(ang) * r1);
        ctx.lineTo(cx + Math.cos(ang) * r2, cy + Math.sin(ang) * r2);
        ctx.stroke();
      }

      // breathing core
      const br = R * (1 + 0.035 * Math.sin(t * 2));
      const core = ctx.createRadialGradient(cx - R * 0.25, cy - R * 0.25, 0, cx, cy, br);
      core.addColorStop(0, "#ffffff");
      core.addColorStop(0.35, "#b9a3ff");
      core.addColorStop(0.7, "#7c5cff");
      core.addColorStop(1, "#1f7fd6");
      ctx.fillStyle = core; ctx.beginPath(); ctx.arc(cx, cy, br, 0, 7); ctx.fill();

      raf = requestAnimationFrame(draw);
    };
    draw();
    return () => { cancelAnimationFrame(raf); window.removeEventListener("resize", resize); window.removeEventListener("mousemove", onMove); };
  }, []);
  return <canvas ref={ref} className="voiceOrb" style={{ width: size, height: size }} aria-hidden="true" />;
}
