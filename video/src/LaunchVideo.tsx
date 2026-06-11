import React from "react";
import {
  AbsoluteFill, Sequence, interpolate, spring,
  useCurrentFrame, useVideoConfig,
} from "remotion";
import { loadFont as loadSerif } from "@remotion/google-fonts/Newsreader";
import { loadFont as loadSans } from "@remotion/google-fonts/HankenGrotesk";
import { Blob } from "./Blob";

const serif = loadSerif();
const sans = loadSans();

export const FPS = 30;
export const DURATION_FRAMES = 36 * FPS; // 36s

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

const Center: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
    {children}
  </AbsoluteFill>
);

/** Springy rise-in for any child. */
const Rise: React.FC<{ delay?: number; children: React.ReactNode; style?: React.CSSProperties }> =
  ({ delay = 0, children, style }) => {
    const frame = useCurrentFrame();
    const { fps } = useVideoConfig();
    const s = spring({ frame: frame - delay, fps, config: { damping: 16, mass: 0.7 } });
    return (
      <div style={{
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [44, 0])}px)`,
        ...style,
      }}>
        {children}
      </div>
    );
  };

const Headline: React.FC<{ children: React.ReactNode; size?: number }> = ({ children, size = 118 }) => (
  <div style={{
    fontFamily: serif.fontFamily, fontWeight: 500, fontSize: size,
    lineHeight: 1.04, letterSpacing: "-0.015em", textAlign: "center",
  }}>
    {children}
  </div>
);

const Sub: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ fontSize: 34, color: SOFT, marginTop: 30, textAlign: "center", lineHeight: 1.5 }}>
    {children}
  </div>
);

const Mono: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{
    fontFamily: "JetBrains Mono, SF Mono, monospace", fontSize: 19,
    letterSpacing: "0.2em", textTransform: "uppercase", color: FAINT,
  }}>
    {children}
  </div>
);

/* ----- Scene 1 · 0-5s · the blob arrives ----- */
const SceneArrive: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const grow = spring({ frame, fps, config: { damping: 14, mass: 1.1 } });
  const fadeOut = interpolate(frame, [4 * fps, 5 * fps], [1, 0], { extrapolateLeft: "clamp" });
  return (
    <AbsoluteFill style={{ ...fill, opacity: fadeOut }}>
      <Center>
        <div style={{ transform: `scale(${grow})` }}>
          <Blob size={520} amp={0.1} speed={0.7} />
        </div>
        <Rise delay={Math.round(1.2 * fps)} style={{ marginTop: 36 }}>
          <Mono>Introducing</Mono>
        </Rise>
      </Center>
    </AbsoluteFill>
  );
};

/* ----- Scene 2 · 5-11s · the claim ----- */
const SceneClaim: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [5 * fps, 6 * fps], [1, 0], { extrapolateLeft: "clamp" });
  return (
    <AbsoluteFill style={{ ...fill, opacity: fadeOut }}>
      <Center>
        <div style={{
          display: "flex", alignItems: "center", gap: 110,
          paddingLeft: 140, paddingRight: 140,
        }}>
          <div style={{ flex: 1 }}>
            <Rise>
              <div style={{
                fontFamily: serif.fontFamily, fontWeight: 500, fontSize: 104,
                lineHeight: 1.05, letterSpacing: "-0.015em",
              }}>
                The assistant<br />that lives on<br />your Mac.
              </div>
            </Rise>
            <Rise delay={Math.round(0.5 * fps)}>
              <div style={{ fontSize: 32, color: SOFT, marginTop: 34, maxWidth: 600, lineHeight: 1.5 }}>
                Say it, and it's done. Aria hears you, sees your screen,
                and operates your apps — so you stay in flow.
              </div>
            </Rise>
          </div>
          <Rise delay={Math.round(0.3 * fps)}>
            <Blob size={460} amp={0.11} speed={0.8} />
          </Rise>
        </div>
      </Center>
    </AbsoluteFill>
  );
};

/* ----- Scene 3 · 11-19s · she gets things done (task card) ----- */
const SceneTasks: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [7 * fps, 8 * fps], [1, 0], { extrapolateLeft: "clamp" });
  const rows: [string, string][] = [
    ["Email drafted", "To: Sam — ready to review"],
    ["Document summarized", "Key points saved to notes"],
    ["Meeting found", "Tomorrow at 10:00 AM"],
    ["Briefing ready", "Today, carry-over, suggested focus"],
  ];
  return (
    <AbsoluteFill style={{ ...fill, opacity: fadeOut }}>
      <Center>
        <div style={{ display: "flex", alignItems: "center", gap: 130 }}>
          <div>
            <Rise><Mono>05 · Actions</Mono></Rise>
            <Rise delay={4}>
              <div style={{
                fontFamily: serif.fontFamily, fontWeight: 500, fontSize: 96,
                lineHeight: 1.05, marginTop: 24,
              }}>
                Aria gets<br />things done.
              </div>
            </Rise>
            <Rise delay={10}>
              <div style={{ fontSize: 30, color: SOFT, marginTop: 28, maxWidth: 560, lineHeight: 1.5 }}>
                "Prepare me for tomorrow." She plans it, runs it
                across your apps, and tells you when it's done.
              </div>
            </Rise>
          </div>
          <div style={{
            width: 520, background: PAPER, border: `1.5px solid ${LINE}`,
            borderRadius: 26, padding: "30px 30px 22px",
            boxShadow: "0 40px 100px rgba(21,19,13,0.14)",
          }}>
            <div style={{
              fontFamily: serif.fontFamily, fontWeight: 600, fontSize: 30,
              display: "flex", alignItems: "center", gap: 14, marginBottom: 22,
            }}>
              <Blob size={34} amp={0.08} speed={0.6} /> Aria
            </div>
            {rows.map(([t, s], i) => {
              const d = Math.round((0.8 + i * 0.55) * fps);
              const sp = spring({ frame: frame - d, fps, config: { damping: 15 } });
              return (
                <div key={t} style={{
                  opacity: sp,
                  transform: `translateY(${interpolate(sp, [0, 1], [20, 0])}px)`,
                  background: BG, border: `1px solid ${LINE}`, borderRadius: 16,
                  padding: "16px 20px", marginBottom: 13,
                }}>
                  <div style={{ fontWeight: 700, fontSize: 24 }}>✓ {t}</div>
                  <div style={{ color: FAINT, fontSize: 19, marginTop: 2 }}>{s}</div>
                </div>
              );
            })}
          </div>
        </div>
      </Center>
    </AbsoluteFill>
  );
};

/* ----- Scene 4 · 19-26s · private / local-first ----- */
const ScenePrivate: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [6 * fps, 7 * fps], [1, 0], { extrapolateLeft: "clamp" });
  const ring = spring({ frame: frame - Math.round(0.3 * fps), fps, config: { damping: 13 } });
  return (
    <AbsoluteFill style={{ ...fill, opacity: fadeOut }}>
      <Center>
        <div style={{
          width: 380, height: 380, borderRadius: "50%",
          background: PAPER, transform: `scale(${ring})`,
          boxShadow: "inset 0 4px 16px rgba(255,255,255,0.9), inset 0 -10px 26px rgba(21,19,13,0.07), 0 36px 90px rgba(21,19,13,0.12)",
          display: "flex", alignItems: "center", justifyContent: "center",
        }}>
          <Blob size={120} amp={0.05} speed={0.45} />
        </div>
        <Rise delay={Math.round(0.8 * fps)} style={{ marginTop: 56 }}>
          <Headline size={92}>Your data stays your data.</Headline>
        </Rise>
        <Rise delay={Math.round(1.3 * fps)}>
          <Sub>Local-first intelligence. On-device wake word.<br />The cloud is an option, not a requirement.</Sub>
        </Rise>
      </Center>
    </AbsoluteFill>
  );
};

/* ----- Scene 5 · 26-31s · feature roll ----- */
const SceneRoll: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fadeOut = interpolate(frame, [4 * fps, 5 * fps], [1, 0], { extrapolateLeft: "clamp" });
  const words = ["Voice", "Knowledge", "Agents", "Memory", "Free & open source"];
  return (
    <AbsoluteFill style={{ ...fill, opacity: fadeOut }}>
      <Center>
        <div style={{ display: "flex", flexDirection: "column", gap: 14, alignItems: "center" }}>
          {words.map((w, i) => {
            const d = Math.round(i * 0.5 * fps);
            const sp = spring({ frame: frame - d, fps, config: { damping: 16 } });
            return (
              <div key={w} style={{
                opacity: sp,
                transform: `translateY(${interpolate(sp, [0, 1], [36, 0])}px)`,
                fontFamily: serif.fontFamily, fontWeight: 500,
                fontSize: i === words.length - 1 ? 56 : 88,
                color: i === words.length - 1 ? SOFT : INK,
                lineHeight: 1.15,
              }}>
                {w}
              </div>
            );
          })}
        </div>
      </Center>
    </AbsoluteFill>
  );
};

/* ----- Scene 6 · 31-36s · endcard ----- */
const SceneEnd: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={fill}>
      <Center>
        <Rise>
          <Blob size={300} amp={0.12} speed={0.8} breatheAmt={0.03} />
        </Rise>
        <Rise delay={Math.round(0.4 * fps)} style={{ marginTop: 40 }}>
          <Headline size={120}>Say "Hey Aria."</Headline>
        </Rise>
        <Rise delay={Math.round(1.0 * fps)} style={{ marginTop: 36 }}>
          <div style={{
            background: INK, color: PAPER, borderRadius: 999,
            padding: "20px 44px", fontSize: 30, fontWeight: 600,
          }}>
            Download the pre-release
          </div>
        </Rise>
        <Rise delay={Math.round(1.4 * fps)} style={{ marginTop: 26 }}>
          <Mono>github.com/coderarush/Aria</Mono>
        </Rise>
      </Center>
    </AbsoluteFill>
  );
};

export const LaunchVideo: React.FC = () => (
  <AbsoluteFill style={fill}>
    <Sequence durationInFrames={5 * FPS}><SceneArrive /></Sequence>
    <Sequence from={5 * FPS} durationInFrames={6 * FPS}><SceneClaim /></Sequence>
    <Sequence from={11 * FPS} durationInFrames={8 * FPS}><SceneTasks /></Sequence>
    <Sequence from={19 * FPS} durationInFrames={7 * FPS}><ScenePrivate /></Sequence>
    <Sequence from={26 * FPS} durationInFrames={5 * FPS}><SceneRoll /></Sequence>
    <Sequence from={31 * FPS} durationInFrames={5 * FPS}><SceneEnd /></Sequence>
  </AbsoluteFill>
);
