import React from "react";
import {
  AbsoluteFill,
  Audio,
  Easing,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { loadFont as loadSerif } from "@remotion/google-fonts/Newsreader";
import { loadFont as loadSans } from "@remotion/google-fonts/HankenGrotesk";
import { Blob } from "./Blob";

const serif = loadSerif();
const sans = loadSans();

export const FPS = 30;
export const DURATION_FRAMES = 46 * FPS;

const INK = "#15120e";
const SOFT = "#5f574b";
const FAINT = "#9a8e7d";
const CREAM = "#f2e7d7";
const PAPER = "#fff8ec";
const GOLD = "#c38332";
const MOSS = "#526b45";
const CLAY = "#a45e3e";
const LINE = "rgba(60,43,25,0.16)";

const fill: React.CSSProperties = {
  background:
    "radial-gradient(circle at 16% 12%, rgba(255,248,226,0.9), transparent 520px), radial-gradient(circle at 84% 12%, rgba(195,131,50,0.18), transparent 560px), linear-gradient(180deg,#f5ecde,#eee0cc)",
  fontFamily: sans.fontFamily,
  color: INK,
  overflow: "hidden",
};

type BlobKey = { t: number; x: number; y: number; s: number; amp: number; speed: number };
const BLOB_PATH: BlobKey[] = [
  { t: 0, x: 0, y: 0, s: 0.05, amp: 0.08, speed: 0.55 },
  { t: 1.4, x: 0, y: -8, s: 1.25, amp: 0.11, speed: 0.72 },
  { t: 5.2, x: 455, y: -10, s: 0.82, amp: 0.12, speed: 0.82 },
  { t: 11.2, x: 0, y: 290, s: 0.38, amp: 0.16, speed: 1.1 },
  { t: 15.8, x: -625, y: -260, s: 0.15, amp: 0.12, speed: 1.45 },
  { t: 22.0, x: 520, y: 28, s: 0.52, amp: 0.18, speed: 1.16 },
  { t: 28.5, x: -520, y: -58, s: 0.44, amp: 0.13, speed: 0.82 },
  { t: 34.8, x: 0, y: -88, s: 0.34, amp: 0.055, speed: 0.45 },
  { t: 39.2, x: 0, y: -198, s: 0.62, amp: 0.12, speed: 0.78 },
  { t: 46, x: 0, y: -198, s: 0.62, amp: 0.12, speed: 0.78 },
];

function mix(a: number, b: number, p: number) {
  return a + (b - a) * p;
}

function blobAt(sec: number) {
  const ease = Easing.bezier(0.23, 1, 0.32, 1);
  let a = BLOB_PATH[0];
  let b = BLOB_PATH[BLOB_PATH.length - 1];
  for (let i = 0; i < BLOB_PATH.length - 1; i++) {
    if (sec >= BLOB_PATH[i].t && sec <= BLOB_PATH[i + 1].t) {
      a = BLOB_PATH[i];
      b = BLOB_PATH[i + 1];
      break;
    }
  }
  const p = interpolate(sec, [a.t, Math.max(a.t + 0.001, b.t)], [0, 1], {
    easing: ease,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return {
    x: mix(a.x, b.x, p),
    y: mix(a.y, b.y, p),
    s: mix(a.s, b.s, p),
    amp: mix(a.amp, b.amp, p),
    speed: mix(a.speed, b.speed, p),
  };
}

function sceneOpacity(frame: number, start: number, end: number, fade = 18) {
  const enter = interpolate(frame, [start, start + fade], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const exit = interpolate(frame, [end - fade, end], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return Math.min(enter, exit);
}

const Mono: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <div
    style={{
      fontFamily: "SF Mono, JetBrains Mono, ui-monospace, monospace",
      color: MOSS,
      fontSize: 21,
      fontWeight: 800,
      letterSpacing: "0.18em",
      textTransform: "uppercase",
      ...style,
    }}
  >
    {children}
  </div>
);

const Kinetic: React.FC<{
  text: string;
  size?: number;
  delay?: number;
  align?: "left" | "center";
  maxWidth?: number;
}> = ({ text, size = 112, delay = 0, align = "left", maxWidth = 1180 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        fontFamily: sans.fontFamily,
        fontSize: size,
        lineHeight: 0.88,
        letterSpacing: "-0.085em",
        fontWeight: 900,
        textAlign: align,
        maxWidth,
      }}
    >
      {text.split(" ").map((word, index) => {
        const s = spring({
          frame: frame - delay - index * 4,
          fps,
          config: { damping: 15, mass: 0.62 },
        });
        return (
          <span
            key={`${word}-${index}`}
            style={{
              display: "inline-block",
              marginRight: "0.22em",
              opacity: s,
              transform: `translateY(${interpolate(s, [0, 1], [52, 0])}px) scale(${interpolate(s, [0, 1], [1.04, 1])})`,
            }}
          >
            {word}
          </span>
        );
      })}
    </div>
  );
};

const Rise: React.FC<{ children: React.ReactNode; delay?: number; style?: React.CSSProperties }> = ({
  children,
  delay = 0,
  style,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame: frame - delay, fps, config: { damping: 18, mass: 0.75 } });
  return (
    <div
      style={{
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [34, 0])}px)`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

const Grain: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <svg width="100%" height="100%">
        <filter id="grain">
          <feTurbulence type="fractalNoise" baseFrequency="0.72" numOctaves="2" seed={frame % 5} stitchTiles="stitch" />
          <feColorMatrix type="matrix" values="0 0 0 0 0.08 0 0 0 0 0.07 0 0 0 0 0.05 0 0 0 0.04 0" />
        </filter>
        <rect width="100%" height="100%" filter="url(#grain)" />
      </svg>
      <AbsoluteFill
        style={{
          background: "radial-gradient(ellipse at center, transparent 62%, rgba(21,18,14,0.10) 100%)",
        }}
      />
    </AbsoluteFill>
  );
};

const BlobLayer: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const k = blobAt(frame / fps);
  const glow = interpolate(k.s, [0.05, 1.25], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", pointerEvents: "none" }}>
      <div
        style={{
          position: "absolute",
          width: 620,
          height: 620,
          borderRadius: "50%",
          background: `radial-gradient(circle, rgba(21,18,14,${0.12 * glow}), transparent 62%)`,
          filter: "blur(20px)",
          transform: `translate(${k.x}px, ${k.y + 18}px) scale(${Math.max(0.001, k.s)})`,
        }}
      />
      <div style={{ transform: `translate(${k.x}px, ${k.y}px) scale(${Math.max(0.001, k.s)})` }}>
        <Blob size={560} amp={k.amp} speed={k.speed} />
      </div>
    </AbsoluteFill>
  );
};

const Card: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <div
    style={{
      border: `1.5px solid ${LINE}`,
      borderRadius: 34,
      background: "rgba(255,248,236,0.72)",
      boxShadow: "0 28px 90px rgba(57,42,24,0.13)",
      ...style,
    }}
  >
    {children}
  </div>
);

const SceneIntro: React.FC<{ start: number; end: number }> = ({ start, end }) => {
  const frame = useCurrentFrame();
  const op = sceneOpacity(frame, start, end, 24);
  const ring = (delay: number) => {
    const p = interpolate(frame - start - delay, [0, 56], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
      easing: Easing.out(Easing.cubic),
    });
    return { opacity: (1 - p) * 0.28 * op, scale: 0.72 + p * 1.55 };
  };
  return (
    <AbsoluteFill style={{ opacity: op, justifyContent: "center", alignItems: "center" }}>
      {[38, 54, 70].map((d) => {
        const r = ring(d);
        return (
          <div
            key={d}
            style={{
              position: "absolute",
              width: 560,
              height: 560,
              borderRadius: "50%",
              border: `2px solid ${INK}`,
              opacity: r.opacity,
              transform: `scale(${r.scale})`,
            }}
          />
        );
      })}
      <Rise delay={70} style={{ position: "absolute", bottom: 170, textAlign: "center" }}>
        <Mono>Introducing Aria</Mono>
      </Rise>
    </AbsoluteFill>
  );
};

const SceneClaim: React.FC<{ start: number; end: number }> = ({ start, end }) => {
  const frame = useCurrentFrame();
  const op = sceneOpacity(frame, start, end, 20);
  return (
    <AbsoluteFill style={{ opacity: op, justifyContent: "center", paddingLeft: 130 }}>
      <div style={{ maxWidth: 860 }}>
        <Kinetic text="Your Mac, with a living assistant." size={104} delay={start + 18} />
        <Rise delay={start + 76}>
          <div style={{ marginTop: 34, maxWidth: 650, color: SOFT, fontSize: 33, lineHeight: 1.42 }}>
            She hears you, sees the relevant part of your screen, plans the work,
            acts across apps, and leaves receipts.
          </div>
        </Rise>
      </div>
    </AbsoluteFill>
  );
};

const SceneContext: React.FC<{ start: number; end: number }> = ({ start, end }) => {
  const frame = useCurrentFrame();
  const op = sceneOpacity(frame, start, end, 18);
  const local = frame - start;
  const typed = `"Circle the broken chart and explain it."`.slice(0, Math.max(0, Math.floor(local / 1.55)));
  const lens = spring({ frame: local - 70, fps: FPS, config: { damping: 18 } });
  return (
    <AbsoluteFill style={{ opacity: op, alignItems: "center" }}>
      <Rise delay={start + 10} style={{ marginTop: 112 }}>
        <Mono>Voice + visual context</Mono>
      </Rise>
      <Card
        style={{
          width: 980,
          height: 390,
          marginTop: 54,
          padding: 28,
          background: "linear-gradient(180deg,rgba(255,250,241,0.9),rgba(255,250,241,0.58))",
        }}
      >
        <div style={{ height: 46, display: "flex", gap: 10, alignItems: "center" }}>
          {[0, 1, 2].map((i) => (
            <span key={i} style={{ width: 14, height: 14, borderRadius: "50%", background: ["#ef6f5f", "#e9bd5a", "#68b36b"][i] }} />
          ))}
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "1.1fr 0.9fr", gap: 24 }}>
          <div style={{ borderRadius: 26, background: "#17120e", minHeight: 260, position: "relative", overflow: "hidden" }}>
            <div style={{ position: "absolute", left: 55, right: 55, bottom: 58, height: 120, display: "flex", alignItems: "end", gap: 18 }}>
              {[54, 92, 68, 132, 88, 160, 104].map((h, i) => (
                <div key={i} style={{ flex: 1, height: h, borderRadius: 999, background: i === 5 ? GOLD : "rgba(255,248,236,0.34)" }} />
              ))}
            </div>
            <div
              style={{
                position: "absolute",
                left: 596,
                top: 75,
                width: 126,
                height: 126,
                border: "4px solid #f7ead5",
                borderRadius: "45% 55% 58% 42%",
                opacity: lens,
                transform: `scale(${interpolate(lens, [0, 1], [0.9, 1])}) rotate(-8deg)`,
              }}
            />
          </div>
          <div style={{ padding: "22px 8px" }}>
            <div style={{ color: FAINT, fontSize: 18, fontWeight: 800, letterSpacing: "0.12em", textTransform: "uppercase" }}>Hey Aria</div>
            <div style={{ marginTop: 18, fontFamily: serif.fontFamily, fontSize: 42, lineHeight: 1.08 }}>{typed}</div>
          </div>
        </div>
      </Card>
    </AbsoluteFill>
  );
};

const ScenePlan: React.FC<{ start: number; end: number }> = ({ start, end }) => {
  const frame = useCurrentFrame();
  const op = sceneOpacity(frame, start, end, 18);
  const rows = ["Read the selection", "Draft a fix", "Ask before sending", "Verify the result"];
  return (
    <AbsoluteFill style={{ opacity: op, justifyContent: "center", paddingLeft: 150 }}>
      <Mono>Agent plan</Mono>
      <Kinetic text="Not a chatbot. An execution loop." size={82} delay={start + 24} maxWidth={760} />
      <Card style={{ width: 760, marginTop: 40, padding: 26 }}>
        {rows.map((row, i) => {
          const s = spring({ frame: frame - start - 84 - i * 13, fps: FPS, config: { damping: 16 } });
          return (
            <div
              key={row}
              style={{
                display: "grid",
                gridTemplateColumns: "34px 1fr auto",
                alignItems: "center",
                gap: 16,
                padding: "16px 12px",
                opacity: s,
                transform: `translateY(${interpolate(s, [0, 1], [24, 0])}px)`,
                borderBottom: i === rows.length - 1 ? "none" : `1px solid ${LINE}`,
              }}
            >
              <span style={{ width: 20, height: 20, borderRadius: "50%", border: `2px solid ${i < 2 ? MOSS : GOLD}`, background: i < 2 ? MOSS : "transparent" }} />
              <strong style={{ fontSize: 28, letterSpacing: "-0.04em" }}>{row}</strong>
              <span style={{ color: i < 2 ? MOSS : GOLD, fontWeight: 800 }}>{i < 2 ? "done" : "gated"}</span>
            </div>
          );
        })}
      </Card>
    </AbsoluteFill>
  );
};

const SceneAct: React.FC<{ start: number; end: number }> = ({ start, end }) => {
  const frame = useCurrentFrame();
  const op = sceneOpacity(frame, start, end, 18);
  const apps = ["Mail", "Calendar", "Notes", "Browser", "Terminal", "GitHub"];
  return (
    <AbsoluteFill style={{ opacity: op, justifyContent: "center", paddingLeft: 720, paddingRight: 110 }}>
      <Mono>Acts across apps</Mono>
      <Kinetic text="Ask for the outcome. Aria handles the steps." size={78} delay={start + 20} maxWidth={920} />
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 14, marginTop: 40 }}>
        {apps.map((app, i) => {
          const s = spring({ frame: frame - start - 86 - i * 7, fps: FPS, config: { damping: 15 } });
          return (
            <Card
              key={app}
              style={{
                height: 138,
                padding: 20,
                opacity: s,
                transform: `translateY(${interpolate(s, [0, 1], [30, 0])}px)`,
              }}
            >
              <div style={{ width: 38, height: 38, borderRadius: "42% 58% 56% 44%", background: INK, marginBottom: 18 }} />
              <strong style={{ fontSize: 27, letterSpacing: "-0.04em" }}>{app}</strong>
            </Card>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const SceneMemory: React.FC<{ start: number; end: number }> = ({ start, end }) => {
  const frame = useCurrentFrame();
  const op = sceneOpacity(frame, start, end, 18);
  const items = ["Project notes", "Work journal", "ChatGPT export", "Decisions", "People", "Receipts"];
  return (
    <AbsoluteFill style={{ opacity: op, justifyContent: "center", paddingLeft: 140 }}>
      <Mono>Memory that works</Mono>
      <Kinetic text="Past chats become usable context." size={82} delay={start + 18} maxWidth={850} />
      <div style={{ position: "relative", width: 900, height: 330, marginTop: 38 }}>
        {items.map((item, i) => {
          const angle = (Math.PI * 2 * i) / items.length - Math.PI / 2;
          const s = spring({ frame: frame - start - 78 - i * 8, fps: FPS, config: { damping: 16 } });
          const x = 430 + Math.cos(angle) * 300;
          const y = 150 + Math.sin(angle) * 118;
          return (
            <div
              key={item}
              style={{
                position: "absolute",
                left: x,
                top: y,
                opacity: s,
                transform: `translate(-50%, -50%) scale(${interpolate(s, [0, 1], [0.92, 1])})`,
                padding: "13px 18px",
                borderRadius: 999,
                border: `1.5px solid ${LINE}`,
                background: "rgba(255,248,236,0.78)",
                boxShadow: "0 18px 60px rgba(57,42,24,0.10)",
                fontWeight: 820,
              }}
            >
              {item}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const SceneTrust: React.FC<{ start: number; end: number }> = ({ start, end }) => {
  const frame = useCurrentFrame();
  const op = sceneOpacity(frame, start, end, 18);
  return (
    <AbsoluteFill style={{ opacity: op, alignItems: "center", justifyContent: "center" }}>
      <Mono>Trust layer</Mono>
      <Kinetic text="Powerful by default. Safe by design." size={86} delay={start + 18} align="center" maxWidth={1180} />
      <Card style={{ width: 900, marginTop: 48, padding: 26 }}>
        {[
          ["Irreversible action", "Approval required", CLAY],
          ["Background agent", "Fail closed", GOLD],
          ["Completed workflow", "Receipt + undo", MOSS],
        ].map(([left, right, color], i) => {
          const s = spring({ frame: frame - start - 94 - i * 12, fps: FPS, config: { damping: 16 } });
          return (
            <div
              key={left}
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "18px 10px",
                opacity: s,
                transform: `translateY(${interpolate(s, [0, 1], [24, 0])}px)`,
                borderBottom: i === 2 ? "none" : `1px solid ${LINE}`,
                fontSize: 28,
                letterSpacing: "-0.04em",
              }}
            >
              <strong>{left}</strong>
              <span style={{ color: color as string, fontWeight: 850 }}>{right}</span>
            </div>
          );
        })}
      </Card>
    </AbsoluteFill>
  );
};

const SceneEnd: React.FC<{ start: number; end: number }> = ({ start, end }) => {
  const frame = useCurrentFrame();
  const op = sceneOpacity(frame, start, end, 20);
  return (
    <AbsoluteFill style={{ opacity: op, alignItems: "center", justifyContent: "flex-end", paddingBottom: 118 }}>
      <Kinetic text="Meet Aria." size={128} delay={start + 14} align="center" maxWidth={1200} />
      <Rise delay={start + 74} style={{ marginTop: 24, textAlign: "center", color: SOFT, fontSize: 34 }}>
        The assistant that actually does the work.
      </Rise>
      <Rise delay={start + 100} style={{ marginTop: 34 }}>
        <div
          style={{
            padding: "18px 28px",
            borderRadius: 999,
            color: PAPER,
            background: INK,
            fontSize: 24,
            fontWeight: 850,
            boxShadow: "0 22px 70px rgba(21,18,14,0.22)",
          }}
        >
          Download for macOS
        </div>
      </Rise>
    </AbsoluteFill>
  );
};

export const LaunchVideo: React.FC = () => {
  return (
    <AbsoluteFill style={fill}>
      <Audio src={staticFile("wake.wav")} volume={0.18} />
      <Sequence from={Math.round(1.2 * FPS)}>
        <Audio src={staticFile("task.wav")} volume={0.1} />
      </Sequence>
      <SceneIntro start={0} end={5 * FPS} />
      <SceneClaim start={4 * FPS} end={11 * FPS} />
      <SceneContext start={10 * FPS} end={17 * FPS} />
      <ScenePlan start={16 * FPS} end={23 * FPS} />
      <SceneAct start={22 * FPS} end={29 * FPS} />
      <SceneMemory start={28 * FPS} end={35 * FPS} />
      <SceneTrust start={34 * FPS} end={40 * FPS} />
      <SceneEnd start={39 * FPS} end={46 * FPS} />
      <BlobLayer />
      <Grain />
    </AbsoluteFill>
  );
};
