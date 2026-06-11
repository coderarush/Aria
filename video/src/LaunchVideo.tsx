import React from "react";
import {
  AbsoluteFill, Sequence, Audio, staticFile, interpolate, spring, Easing,
  useCurrentFrame, useVideoConfig,
} from "remotion";
import { loadFont as loadSerif } from "@remotion/google-fonts/Newsreader";
import { loadFont as loadSans } from "@remotion/google-fonts/HankenGrotesk";
import { Blob } from "./Blob";

const serif = loadSerif();
const sans = loadSans();

export const FPS = 30;
export const DURATION_FRAMES = 40 * FPS; // 40s

const INK = "#15130d";
const SOFT = "#5b5648";
const FAINT = "#958f7e";
const BG = "#f1ede2";
const PAPER = "#f7f4ec";
const LINE = "#ddd6c4";

const fill: React.CSSProperties = {
  backgroundColor: BG,
  fontFamily: sans.fontFamily,
  color: INK,
};

/* ============================================================
   The blob is the main character: ONE blob, choreographed across
   the whole film. Keyframes in seconds; positions relative to
   screen center (1920x1080), scale on a 560px base sprite.
   ============================================================ */
type BlobKey = { t: number; x: number; y: number; s: number; amp: number; speed: number };
const BLOB_PATH: BlobKey[] = [
  { t: 0.0,  x: 0,    y: 0,    s: 0.0,  amp: 0.10, speed: 0.70 },  // born
  { t: 1.2,  x: 0,    y: 0,    s: 1.25, amp: 0.10, speed: 0.70 },  // arrive (wake chime)
  { t: 4.6,  x: 0,    y: 0,    s: 1.25, amp: 0.10, speed: 0.70 },
  { t: 6.0,  x: 470,  y: 0,    s: 0.86, amp: 0.11, speed: 0.80 },  // claim: settles right
  { t: 10.6, x: 470,  y: 0,    s: 0.86, amp: 0.11, speed: 0.80 },
  { t: 12.0, x: 0,    y: 318,  s: 0.42, amp: 0.16, speed: 0.95 },  // conversation: orb, listening
  { t: 14.0, x: 0,    y: 318,  s: 0.42, amp: 0.13, speed: 1.60 },  // thinking
  { t: 17.6, x: 0,    y: 318,  s: 0.42, amp: 0.12, speed: 0.80 },
  { t: 19.0, x: -640, y: -250, s: 0.14, amp: 0.10, speed: 0.70 },  // cards: tucks by the label
  { t: 23.6, x: -640, y: -250, s: 0.14, amp: 0.10, speed: 0.70 },
  { t: 25.0, x: 0,    y: -60,  s: 0.30, amp: 0.05, speed: 0.45 },  // privacy: calm, ringed
  { t: 29.6, x: 0,    y: -60,  s: 0.30, amp: 0.05, speed: 0.45 },
  { t: 31.0, x: 0,    y: -340, s: 0.20, amp: 0.10, speed: 0.80 },  // roll: watches from above
  { t: 34.0, x: 0,    y: -340, s: 0.20, amp: 0.10, speed: 0.80 },
  { t: 35.4, x: 0,    y: -205, s: 0.62, amp: 0.12, speed: 0.80 },  // endcard: confident
];

function blobAt(sec: number) {
  const ease = Easing.bezier(0.22, 1, 0.36, 1);
  const last = BLOB_PATH[BLOB_PATH.length - 1];
  if (sec >= last.t) {
    return { x: last.x, y: last.y, s: last.s, amp: last.amp, speed: last.speed };
  }
  let a = BLOB_PATH[0];
  let b = BLOB_PATH[1];
  for (let i = 0; i < BLOB_PATH.length - 1; i++) {
    if (sec >= BLOB_PATH[i].t && sec <= BLOB_PATH[i + 1].t) {
      a = BLOB_PATH[i]; b = BLOB_PATH[i + 1]; break;
    }
  }
  const p = interpolate(sec, [a.t, Math.max(b.t, a.t + 0.0001)], [0, 1],
    { easing: ease, extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const mix = (ka: number, kb: number) => ka + (kb - ka) * p;
  return { x: mix(a.x, b.x), y: mix(a.y, b.y), s: mix(a.s, b.s),
           amp: mix(a.amp, b.amp), speed: mix(a.speed, b.speed) };
}

const BlobLayer: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const k = blobAt(frame / fps);
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", pointerEvents: "none" }}>
      <div style={{ transform: `translate(${k.x}px, ${k.y}px) scale(${Math.max(0.001, k.s)})` }}>
        <Blob size={560} amp={k.amp} speed={k.speed} />
      </div>
    </AbsoluteFill>
  );
};

/* ---------- shared pieces ---------- */

const Rise: React.FC<{ delay?: number; children: React.ReactNode; style?: React.CSSProperties }> =
  ({ delay = 0, children, style }) => {
    const frame = useCurrentFrame();
    const { fps } = useVideoConfig();
    const s = spring({ frame: frame - delay, fps, config: { damping: 16, mass: 0.7 } });
    return (
      <div style={{ opacity: s, transform: `translateY(${interpolate(s, [0, 1], [44, 0])}px)`, ...style }}>
        {children}
      </div>
    );
  };

/** Kinetic headline: words land one by one with a soft settle. */
const Kinetic: React.FC<{ text: string; size?: number; startDelay?: number; perWord?: number; align?: "left" | "center" }> =
  ({ text, size = 104, startDelay = 0, perWord = 4, align = "left" }) => {
    const frame = useCurrentFrame();
    const { fps } = useVideoConfig();
    const words = text.split(" ");
    return (
      <div style={{
        fontFamily: serif.fontFamily, fontWeight: 500, fontSize: size,
        lineHeight: 1.06, letterSpacing: "-0.015em",
        textAlign: align, maxWidth: 1500,
      }}>
        {words.map((w, i) => {
          const s = spring({ frame: frame - startDelay - i * perWord, fps, config: { damping: 14, mass: 0.6 } });
          return (
            <span key={i} style={{
              display: "inline-block",
              opacity: s,
              transform: `translateY(${interpolate(s, [0, 1], [40, 0])}px) scale(${interpolate(s, [0, 1], [1.06, 1])})`,
              marginRight: "0.26em",
            }}>{w}</span>
          );
        })}
      </div>
    );
  };

const Mono: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{
    fontFamily: "JetBrains Mono, SF Mono, monospace", fontSize: 19,
    letterSpacing: "0.2em", textTransform: "uppercase", color: FAINT,
  }}>{children}</div>
);

/** Type-on text (the user's spoken line in the demo scene). */
const TypeOn: React.FC<{ text: string; startDelay: number; cps?: number; style?: React.CSSProperties }> =
  ({ text, startDelay, cps = 22, style }) => {
    const frame = useCurrentFrame();
    const { fps } = useVideoConfig();
    const chars = Math.max(0, Math.floor(((frame - startDelay) / fps) * cps));
    const shown = text.slice(0, chars);
    const caret = chars < text.length && chars > 0;
    return <span style={style}>{shown}{caret ? "▏" : ""}</span>;
  };

/** Filmic finish: fine grain + soft vignette over everything. */
const Finish: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <svg width="100%" height="100%">
        <filter id="grain">
          <feTurbulence type="fractalNoise" baseFrequency="0.9"
            numOctaves="2" seed={frame % 7} stitchTiles="stitch" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.08 0 0 0 0 0.07 0 0 0 0 0.05 0 0 0 0.05 0" />
        </filter>
        <rect width="100%" height="100%" filter="url(#grain)" />
      </svg>
      <AbsoluteFill style={{
        background: "radial-gradient(ellipse at center, transparent 62%, rgba(21,19,13,0.10) 100%)",
      }} />
    </AbsoluteFill>
  );
};

/* ---------- scenes (text/cards only — the blob lives on its own layer) ---------- */

// 0–5s · arrival: echo rings + Introducing
const SceneArrive: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const ring = (delay: number) => {
    const p = interpolate(frame - delay, [0, 1.6 * fps], [0, 1],
      { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
    return { scale: 0.6 + p * 1.5, opacity: (1 - p) * 0.35 };
  };
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      {[1.2, 1.55].map((d) => {
        const r = ring(Math.round(d * fps));
        return (
          <div key={d} style={{
            position: "absolute", width: 560, height: 560, borderRadius: "50%",
            border: `2px solid ${INK}`, opacity: r.opacity, transform: `scale(${r.scale})`,
          }} />
        );
      })}
      <Rise delay={Math.round(2.2 * fps)} style={{ position: "absolute", bottom: 220 }}>
        <Mono>Introducing Aria</Mono>
      </Rise>
    </AbsoluteFill>
  );
};

// 5–11s · the claim, kinetic
const SceneClaim: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [5.2 * fps, 6 * fps], [1, 0], { extrapolateLeft: "clamp" });
  return (
    <AbsoluteFill style={{ opacity: fadeOut, justifyContent: "center", paddingLeft: 150 }}>
      <div style={{ maxWidth: 900 }}>
        <Kinetic text="The assistant that lives on your Mac." size={108} startDelay={Math.round(0.9 * fps)} />
        <Rise delay={Math.round(2.4 * fps)}>
          <div style={{ fontSize: 32, color: SOFT, marginTop: 34, maxWidth: 620, lineHeight: 1.5 }}>
            Say it, and it's done. She hears you, sees your screen,
            and operates your apps — so you stay in flow.
          </div>
        </Rise>
      </div>
    </AbsoluteFill>
  );
};

// 11–18s · live conversation demo (the orb is the persistent blob, bottom-center)
const SceneDemo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [6.2 * fps, 7 * fps], [1, 0], { extrapolateLeft: "clamp" });
  const replyIn = spring({ frame: frame - Math.round(3.6 * fps), fps, config: { damping: 15 } });
  return (
    <AbsoluteFill style={{ opacity: fadeOut, alignItems: "center" }}>
      <Rise delay={4} style={{ marginTop: 130 }}>
        <Mono>A real conversation</Mono>
      </Rise>
      {/* the user's line, typed as if spoken */}
      <div style={{
        marginTop: 56, background: PAPER, border: `1.5px solid ${LINE}`,
        borderRadius: 999, padding: "22px 42px", minWidth: 760, textAlign: "center",
        boxShadow: "0 24px 70px rgba(21,19,13,0.10)",
        fontFamily: serif.fontFamily, fontSize: 42, fontWeight: 500,
      }}>
        <TypeOn text='"Prepare me for tomorrow."' startDelay={Math.round(0.8 * fps)} />
      </div>
      {/* Aria's reply rises once she's "thought" */}
      <div style={{
        opacity: replyIn,
        transform: `translateY(${interpolate(replyIn, [0, 1], [26, 0])}px)`,
        marginTop: 26, background: INK, color: PAPER,
        borderRadius: 999, padding: "18px 38px", fontSize: 28,
      }}>
        Checked your calendar, pulled last week's notes — your briefing is ready.
      </div>
    </AbsoluteFill>
  );
};

// 18–24s · she gets things done (card stack)
const SceneTasks: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [5.2 * fps, 6 * fps], [1, 0], { extrapolateLeft: "clamp" });
  const rows: [string, string][] = [
    ["Email drafted", "To: Sam — ready to review"],
    ["Document summarized", "Key points saved to notes"],
    ["Meeting found", "Tomorrow at 10:00 AM"],
    ["Briefing ready", "Today, carry-over, suggested focus"],
  ];
  return (
    <AbsoluteFill style={{ opacity: fadeOut, justifyContent: "center" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 130, paddingLeft: 170 }}>
        <div>
          <Rise><div style={{ marginLeft: 56 }}><Mono>Actions</Mono></div></Rise>
          <Rise delay={4}>
            <Kinetic text="Aria gets things done." size={96} startDelay={6} />
          </Rise>
        </div>
        <div style={{
          width: 520, background: PAPER, border: `1.5px solid ${LINE}`,
          borderRadius: 26, padding: "30px 30px 20px",
          boxShadow: "0 40px 100px rgba(21,19,13,0.14)",
        }}>
          <div style={{
            fontFamily: serif.fontFamily, fontWeight: 600, fontSize: 30,
            display: "flex", alignItems: "center", gap: 14, marginBottom: 22,
          }}>
            <Blob size={34} amp={0.08} speed={0.6} /> Aria
          </div>
          {rows.map(([t, s], i) => {
            const d = Math.round((0.7 + i * 0.55) * fps);
            const sp = spring({ frame: frame - d, fps, config: { damping: 15 } });
            return (
              <div key={t} style={{
                opacity: sp,
                transform: `translateY(${interpolate(sp, [0, 1], [22, 0])}px) scale(${interpolate(sp, [0, 1], [0.98, 1])})`,
                background: BG, border: `1px solid ${LINE}`, borderRadius: 16,
                padding: "15px 20px", marginBottom: 12,
              }}>
                <div style={{ fontWeight: 700, fontSize: 23 }}>✓ {t}</div>
                <div style={{ color: FAINT, fontSize: 18, marginTop: 1 }}>{s}</div>
              </div>
            );
          })}
        </div>
      </div>
    </AbsoluteFill>
  );
};

// 24–30s · privacy (ring forms around the persistent blob)
const ScenePrivate: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [5.2 * fps, 6 * fps], [1, 0], { extrapolateLeft: "clamp" });
  const ring = spring({ frame: frame - Math.round(0.6 * fps), fps, config: { damping: 13 } });
  return (
    <AbsoluteFill style={{ opacity: fadeOut, alignItems: "center" }}>
      <div style={{
        position: "absolute", top: 540 - 60 - 195, width: 390, height: 390, borderRadius: "50%",
        background: PAPER, transform: `scale(${ring})`,
        boxShadow: "inset 0 4px 16px rgba(255,255,255,0.9), inset 0 -10px 26px rgba(21,19,13,0.07), 0 36px 90px rgba(21,19,13,0.12)",
      }} />
      <div style={{ position: "absolute", top: 660, textAlign: "center" }}>
        <Kinetic text="Your data stays your data." size={88} startDelay={Math.round(1.0 * fps)} align="center" />
        <Rise delay={Math.round(2.0 * fps)}>
          <div style={{ fontSize: 30, color: SOFT, marginTop: 26, lineHeight: 1.5 }}>
            Local-first intelligence. On-device wake word.<br />
            The cloud is an option, not a requirement.
          </div>
        </Rise>
      </div>
    </AbsoluteFill>
  );
};

// 30–35s · feature roll
const SceneRoll: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [4.2 * fps, 5 * fps], [1, 0], { extrapolateLeft: "clamp" });
  const words = ["Voice", "Knowledge", "Agents", "Memory", "Free & open source"];
  return (
    <AbsoluteFill style={{ opacity: fadeOut, justifyContent: "center", alignItems: "center" }}>
      <div style={{ display: "flex", flexDirection: "column", gap: 12, alignItems: "center", marginTop: 120 }}>
        {words.map((w, i) => {
          const d = Math.round(i * 0.48 * fps);
          const sp = spring({ frame: frame - d, fps, config: { damping: 16 } });
          return (
            <div key={w} style={{
              opacity: sp,
              transform: `translateY(${interpolate(sp, [0, 1], [36, 0])}px)`,
              fontFamily: serif.fontFamily, fontWeight: 500,
              fontSize: i === words.length - 1 ? 52 : 84,
              color: i === words.length - 1 ? SOFT : INK,
              lineHeight: 1.15,
            }}>{w}</div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// 35–40s · endcard
const SceneEnd: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pulse = 1 + 0.02 * Math.sin((frame / fps) * 3.4);
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <div style={{ position: "absolute", top: 560, textAlign: "center" }}>
        <Kinetic text='Say "Hey Aria."' size={120} startDelay={Math.round(0.5 * fps)} align="center" />
        <Rise delay={Math.round(1.4 * fps)} style={{ marginTop: 38, display: "flex", justifyContent: "center" }}>
          <div style={{
            background: INK, color: PAPER, borderRadius: 999,
            padding: "20px 44px", fontSize: 30, fontWeight: 600,
            transform: `scale(${pulse})`,
          }}>
            Download the pre-release
          </div>
        </Rise>
        <Rise delay={Math.round(1.8 * fps)} style={{ marginTop: 26 }}>
          <Mono>github.com/coderarush/Aria</Mono>
        </Rise>
      </div>
    </AbsoluteFill>
  );
};

export const LaunchVideo: React.FC = () => (
  <AbsoluteFill style={fill}>
    {/* soundtrack: warm bed + Aria's actual chimes at story beats */}
    <Audio src={staticFile("bed.wav")} volume={0.85} />
    <Sequence from={Math.round(1.2 * FPS)} durationInFrames={FPS}>
      <Audio src={staticFile("wake.wav")} volume={0.8} />
    </Sequence>
    <Sequence from={Math.round(14.6 * FPS)} durationInFrames={FPS}>
      <Audio src={staticFile("task.wav")} volume={0.7} />
    </Sequence>
    <Sequence from={Math.round(35.8 * FPS)} durationInFrames={FPS}>
      <Audio src={staticFile("done.wav")} volume={0.8} />
    </Sequence>

    <Sequence durationInFrames={5 * FPS}><SceneArrive /></Sequence>
    <Sequence from={5 * FPS} durationInFrames={6 * FPS}><SceneClaim /></Sequence>
    <Sequence from={11 * FPS} durationInFrames={7 * FPS}><SceneDemo /></Sequence>
    <Sequence from={18 * FPS} durationInFrames={6 * FPS}><SceneTasks /></Sequence>
    <Sequence from={24 * FPS} durationInFrames={6 * FPS}><ScenePrivate /></Sequence>
    <Sequence from={30 * FPS} durationInFrames={5 * FPS}><SceneRoll /></Sequence>
    <Sequence from={35 * FPS} durationInFrames={5 * FPS}><SceneEnd /></Sequence>

    {/* the main character, continuous across every scene */}
    <BlobLayer />
    <Finish />
  </AbsoluteFill>
);
