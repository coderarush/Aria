import { useRef, useState, useEffect } from "react";
import { motion, useReducedMotion } from "framer-motion";
import Blob from "./Blob.jsx";
import { Magnetic, TiltCard, ScrollProgress, Aurora, WordReveal, useScroll, useTransform } from "./Motion.jsx";

const DOWNLOAD = "/Aria.dmg";
const GITHUB = "https://github.com/coderarush/Aria";
// Waitlist backend (POST JSON {email}). Empty → mailto fallback. See README.
const WAITLIST_ENDPOINT = "";
const CONTACT = "arushp@icloud.com";

/* Apple-style: content drifts up and settles as it enters the viewport. */
function useRise(reduce) {
  return {
    hidden: { opacity: 0, y: reduce ? 0 : 40, scale: reduce ? 1 : 0.98 },
    show: (i = 0) => ({
      opacity: 1, y: 0, scale: 1,
      transition: { duration: 0.8, delay: i * 0.09, ease: [0.22, 1, 0.36, 1] },
    }),
  };
}

function Reveal({ children, i = 0, className }) {
  const reduce = useReducedMotion();
  const rise = useRise(reduce);
  return (
    <motion.div
      className={className}
      variants={rise}
      custom={i}
      initial="hidden"
      whileInView="show"
      viewport={{ once: true, margin: "-70px" }}
    >
      {children}
    </motion.div>
  );
}

/* Numbered editorial section label */
function Label({ n, children }) {
  return <Reveal><span className="mono label">{n} · {children}</span></Reveal>;
}

function Waitlist() {
  const [email, setEmail] = useState("");
  const [state, setState] = useState("idle");

  const submit = async (e) => {
    e.preventDefault();
    if (!email.includes("@")) return;
    if (!WAITLIST_ENDPOINT) {
      window.location.href =
        `mailto:${CONTACT}?subject=Aria%20early%20access&body=${encodeURIComponent(email)}`;
      return;
    }
    setState("sending");
    try {
      const res = await fetch(WAITLIST_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ email }),
      });
      setState(res.ok ? "done" : "error");
    } catch { setState("error"); }
  };

  if (state === "done") return <p className="waitlistDone">You're on the list — we'll email you at launch.</p>;
  return (
    <form className="waitlist" onSubmit={submit} aria-label="Request early access">
      <input type="email" required value={email} placeholder="you@example.com"
             aria-label="Email address" onChange={(e) => setEmail(e.target.value)} />
      <button className="btn" type="submit" disabled={state === "sending"}>
        {state === "sending" ? "Joining…" : "Request access"}
      </button>
      {state === "error" && <span className="waitlistErr">Something hiccuped — try again.</span>}
    </form>
  );
}

const MARQUEE_ITEMS = [
  "Circle to explain", "Draw on screen", "Voice control", "Computer use",
  "Memory & recall", "Daily briefings", "Recipes & automation", "Meeting notes",
  "Focus mode", "Calendar", "Email", "Screen awareness", "Runs 100% local",
];

function Marquee() {
  const items = [...MARQUEE_ITEMS, ...MARQUEE_ITEMS];
  return (
    <div className="marqueeBand" aria-hidden="true">
      <div className="marqueeTrack">
        {items.map((item, i) => (
          <span key={i} className="marqueeItem">
            {item}<span className="marqueeDot">·</span>
          </span>
        ))}
      </div>
    </div>
  );
}

/* The Lens showcase — Aria's circle-to-explain, drawn in her own gooey idiom.
   A stylized window with a hand-drawn loop around a control, small blobs riding
   the stroke, and the explanation surfacing beside it. Motion is meaning. */
function LensShowcase() {
  const reduce = useReducedMotion();
  const stageRef = useRef(null);
  const [pts, setPts] = useState([]);          // user-drawn points, in 0–100 stage coords
  const [drawing, setDrawing] = useState(false);
  const [answered, setAnswered] = useState(false);
  const drew = pts.length > 4;

  const toCoord = (e) => {
    const r = stageRef.current.getBoundingClientRect();
    const c = e.touches ? e.touches[0] : e;
    return { x: ((c.clientX - r.left) / r.width) * 100, y: ((c.clientY - r.top) / r.height) * 100 };
  };
  const down = (e) => { e.preventDefault(); setAnswered(false); setPts([toCoord(e)]); setDrawing(true); };
  const move = (e) => { if (drawing) setPts((p) => [...p, toCoord(e)]); };
  const up = () => { setDrawing(false); if (pts.length > 4) setTimeout(() => setAnswered(true), 280); };

  const userPath = pts.length > 1 ? "M" + pts.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(" L") : "";
  const demoLoop = "M50,16 C72,14 84,32 82,52 C80,74 58,80 38,76 C18,72 14,46 22,30 C28,18 38,17 50,16 Z";

  return (
    <section id="lens" className="lensSec firstSection">
      <div className="wrap">
        <div className="lensHead">
          <span className="mono label">03 · Lens <span className="newPill">New</span></span>
          <Reveal i={1}><h2 className="display">Circle anything.<br />Aria explains it.</h2></Reveal>
          <Reveal i={2}>
            <p className="body sub">Hold <span className="mono inline">⌥⇧C</span> and draw a loop
            around whatever you don't understand — an error, a chart, a button, a foreign
            phrase. Aria reads just that, and tells you what it is. <strong>Try it below — draw
            a circle on the window.</strong></p>
          </Reveal>
        </div>

        <Reveal i={2} className="lensStageWrap">
          <div
            ref={stageRef}
            className={`lensStage ${drew ? "lensDrew" : ""}`}
            onPointerDown={down}
            onPointerMove={move}
            onPointerUp={up}
            onPointerLeave={() => drawing && up()}
          >
            {/* faux window beneath */}
            <div className="lensWindow">
              <div className="lensTitlebar"><i /><i /><i /></div>
              <div className="lensRows">
                <div className="lensRow"><span className="lensBar w70" /><span className="lensBar w40" /></div>
                <div className="lensRow"><span className="lensBar w50" /><span className="lensBar w60" /></div>
                <div className="lensRow lensRowTarget">
                  <span className="lensChip">Export ▾</span>
                  <span className="lensBar w30" />
                </div>
                <div className="lensRow"><span className="lensBar w80" /><span className="lensBar w20" /></div>
              </div>
            </div>

            {!drew && (
              <div className="lensHint">✎ draw a circle here</div>
            )}

            <svg className="lensInk" viewBox="0 0 100 100" preserveAspectRatio="none">
              <defs>
                <linearGradient id="lensGrad" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stopColor="#6b8cff" />
                  <stop offset="50%" stopColor="#7c66f0" />
                  <stop offset="100%" stopColor="#21d4b4" />
                </linearGradient>
              </defs>
              {drew ? (
                <path d={userPath} fill="none" stroke="url(#lensGrad)" strokeWidth="2.2"
                      strokeLinecap="round" strokeLinejoin="round" />
              ) : (
                <motion.path d={demoLoop} fill="none" stroke="url(#lensGrad)" strokeWidth="2.2"
                  strokeLinecap="round" opacity="0.85"
                  initial={{ pathLength: 0 }}
                  whileInView={reduce ? { pathLength: 1 } : { pathLength: [0, 1, 1, 0] }}
                  viewport={{ once: false }}
                  transition={{ duration: 5, repeat: Infinity, ease: "easeInOut", times: [0, 0.35, 0.8, 1] }}
                />
              )}
            </svg>

            {/* explanation surfacing — after the user draws, or in the auto demo */}
            <motion.div className="lensAnswer"
              initial={{ opacity: 0, y: 16, scale: 0.96 }}
              animate={answered ? { opacity: 1, y: 0, scale: 1 } : undefined}
              whileInView={!drew ? { opacity: 1, y: 0, scale: 1 } : undefined}
              viewport={{ once: false }}
              transition={{ delay: drew ? 0 : 1.6, duration: 0.6, ease: [0.22, 1, 0.36, 1] }}
              style={drew && !answered ? { opacity: 0 } : undefined}>
              <div className="lensAnswerHead"><span className="lensAnswerOrb"><Blob size={20} mood="thinking" /></span> Aria</div>
              <p>That's the <strong>Export</strong> menu — it saves this as PDF, PNG, or CSV.
              The ▾ opens the format list.</p>
            </motion.div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

export default function App() {
  const reduce = useReducedMotion();

  /* Nav scroll state — dark over hero, cream blur when scrolled */
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 60);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  /* Hero scroll parallax — the blob rises and fades, the headline drifts up at a
     different rate, so the hero has Apple-style layered depth as you scroll out. */
  const heroRef = useRef(null);
  const { scrollYProgress: heroP } = useScroll({ target: heroRef, offset: ["start start", "end start"] });
  const blobY = useTransform(heroP, [0, 1], [0, reduce ? 0 : -160]);
  const blobScale = useTransform(heroP, [0, 1], [1, reduce ? 1 : 1.18]);
  const blobOpacity = useTransform(heroP, [0, 0.8], [1, 0.15]);
  const titleY = useTransform(heroP, [0, 1], [0, reduce ? 0 : -60]);
  const heroFade = useTransform(heroP, [0, 0.7], [1, 0]);

  /* Cursor spotlight for hero */
  const handleHeroMouseMove = (e) => {
    const x = ((e.clientX - e.currentTarget.getBoundingClientRect().left) / e.currentTarget.getBoundingClientRect().width * 100).toFixed(1) + "%";
    const y = ((e.clientY - e.currentTarget.getBoundingClientRect().top) / e.currentTarget.getBoundingClientRect().height * 100).toFixed(1) + "%";
    e.currentTarget.style.setProperty("--mx", x);
    e.currentTarget.style.setProperty("--my", y);
  };

  const setupSteps = [
    {
      n: "01",
      title: "Download & Install",
      body: "Download the .dmg file, open it, drag Aria to Applications. Right-click Aria → Open (required once — we're not notarized yet).",
    },
    {
      n: "02",
      title: "Grant permissions",
      body: "Aria needs Accessibility + Screen Recording + Microphone. Each triggers a macOS prompt on first launch — click Allow all three. If missed: System Settings → Privacy & Security.",
    },
    {
      n: "03",
      title: "Pick your model — local by default",
      body: "Open Aria → ⌘, (Settings) → one-click install a local model sized to your Mac. It runs entirely on-device. Prefer the cloud? Paste a free Gemini key (ai.google.dev) instead — optional.",
    },
    {
      n: "04",
      title: "Say \"Hey Aria\"",
      body: "She wakes on the phrase \"Hey Aria\". Or press ⌥Space to talk, ⌥⇧Space to type, ⌥⇧C to circle-and-explain. She appears as a small blob on your screen.",
    },
    {
      n: "05",
      title: "Try your first command",
      body: "\"Brief me on my day\" · \"What did I do today?\" · ⌥⇧C then circle an error · \"Draw on my screen\" · \"Open my calendar\" · \"Remember this for later\"",
    },
  ];

  return (
    <>
      {/* ---------- nav ---------- */}
      <nav className={`nav ${scrolled ? "navScrolled" : "navDark"}`}>
        <div className="wrap navInner">
          <div className={`brand ${scrolled ? "" : "brandLight"}`}>
            <span className={`dot ${scrolled ? "" : "dotLight"}`} /> Aria
          </div>
          <div className="links">
            <a href="#features">Features</a>
            <a href="#lens">Lens</a>
            <a href="#privacy">Privacy</a>
            <a href="#setup">Setup</a>
            <a className={scrolled ? "btn small" : "btnLightSmall"} href={DOWNLOAD} download="Aria.dmg">Download</a>
          </div>
        </div>
      </nav>

      <ScrollProgress />

      {/* ---------- 01 · HERO (dark, full-viewport) ---------- */}
      <section ref={heroRef} className="heroDark" onMouseMove={handleHeroMouseMove}>
        <Aurora className="auroraHero" />
        {/* Large centered blob — rises + fades on scroll */}
        <motion.div className="heroBlobWrap"
          style={{ y: blobY, scale: blobScale, opacity: blobOpacity }}
          initial={{ opacity: 0, scale: 0.6 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 1.4, ease: [0.22, 1, 0.36, 1] }}
        >
          <div className="heroBlobAura" />
          <Blob size={520} mood="idle" />
        </motion.div>

        {/* Headline below blob — word-by-word reveal + scroll drift */}
        <motion.div style={{ y: titleY, opacity: heroFade }}>
          <WordReveal className="display heroTitle" text={"The assistant\nthat lives on your Mac."} />
        </motion.div>

        <motion.p className="heroSub"
          style={{ opacity: heroFade }}
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, delay: 0.55, ease: [0.22, 1, 0.36, 1] }}
        >
          Say it, and it's done. Aria hears you, sees your screen, and operates<br />
          your apps. Circle anything to understand it. Runs on your Mac.
        </motion.p>

        <motion.div className="heroCta"
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, delay: 0.7, ease: [0.22, 1, 0.36, 1] }}
        >
          <Magnetic className="btnLight" href={DOWNLOAD} download="Aria.dmg">
            Download for Mac ↓
          </Magnetic>
          <Magnetic className="btnGhost" href="#features" strength={0.25}>See what she can do</Magnetic>
        </motion.div>

        {/* Specs bar at very bottom of hero */}
        <motion.div className="heroSpecs"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 1.0, duration: 0.7 }}
          aria-hidden="true"
        >
          <span>macOS 14+</span>
          <span className="specDot">·</span>
          <span>Free</span>
          <span className="specDot">·</span>
          <span>Open source</span>
          <span className="specDot">·</span>
          <span>Private by default</span>
        </motion.div>
      </section>

      {/* ---------- MARQUEE ---------- */}
      <Marquee />

      {/* ---------- 01.5 · THE FILM ---------- */}
      <section className="filmSec">
        <div className="wrap">
          <Label n="01">Watch</Label>
          <Reveal i={1}>
            <video
              className="film"
              src="/aria-launch.mp4"
              controls
              playsInline
              preload="metadata"
            />
          </Reveal>
        </div>
      </section>

      {/* ---------- 02 · FEATURES (bento grid) ---------- */}
      <section id="features" className="firstSection">
        <div className="wrap">
          <Label n="02">Features</Label>
          <Reveal i={1}><h2 className="display">Powerful capabilities.<br />Invisible by design.</h2></Reveal>
          <Reveal i={2}>
            <p className="body sub">Aria blends into your workflow so you can stay in flow
            and get more done.</p>
          </Reveal>

          {/* bento grid — 3D tilt + pointer sheen */}
          <div className="bentoGrid">
            <TiltCard className="bentoCard bentoLarge"
              initial={{ opacity: 0, y: 30 }} whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }} transition={{ duration: 0.7 }}>
              <span className="bentoNumber">01 · Voice first</span>
              <h3>Natural conversation.<br />No commands.</h3>
              <p>Just speak. Aria understands context, intent, and follow-ups.</p>
              <div className="bentoBlobDeco"><Blob size={180} mood="listening" /></div>
            </TiltCard>

            <TiltCard className="bentoCard"
              initial={{ opacity: 0, y: 30 }} whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }} transition={{ duration: 0.7, delay: 0.1 }}>
              <span className="bentoNumber">02 · Context aware</span>
              <h3>She sees what you see.</h3>
              <p>Aria reads the window, selection, and field you're in — no explaining needed.</p>
            </TiltCard>

            <TiltCard className="bentoCard bentoWide"
              initial={{ opacity: 0, y: 30 }} whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }} transition={{ duration: 0.7, delay: 0.2 }}>
              <span className="bentoNumber">03 · Takes action</span>
              <h3>Opens apps. Clicks. Types. Sends.</h3>
              <p>From drafting emails to running your morning routine — Aria completes the task.</p>
            </TiltCard>

            <TiltCard className="bentoCard"
              initial={{ opacity: 0, y: 30 }} whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }} transition={{ duration: 0.7, delay: 0.3 }}>
              <span className="bentoNumber">04 · Runs 100% local</span>
              <h3>Your Mac. Your data.</h3>
              <p>A local model does the thinking by default. Only your voice ever touches the cloud — and only if you let it.</p>
            </TiltCard>
          </div>
        </div>
      </section>

      {/* ---------- 03 · LENS (circle to explain) ---------- */}
      <LensShowcase />

      {/* ---------- 03.5 · HOW IT WORKS ---------- */}
      <section>
        <div className="wrap">
          <Label n="04">How it works</Label>
          <div className="cols">
            <Reveal i={1}>
              <h2 className="display">One tiny icon.<br />Always within reach.</h2>
              <p className="body sub">Aria lives in your menu bar. Click, speak, or use a
              shortcut — <span className="mono inline">⌥space</span> to talk,
              <span className="mono inline"> ⌥⇧space</span> to type. It's always there when
              you need it, and invisible when you don't.</p>
            </Reveal>
            <Reveal i={2} className="menubarMock" aria-hidden="true">
              <div className="mbBar">
                <span className="mbGlyph" /><span className="mbGlyph" /><span className="mbGlyph wide" />
                <span className="mbTime">Tue 9:41 AM</span>
                <span className="mbBlob"><Blob size={22} mood="calm" /></span>
              </div>
              <div className="mbDrop">
                <div className="mbOrb"><Blob size={46} mood="listening" /></div>
                <span className="mbName">Aria</span>
              </div>
            </Reveal>
          </div>
        </div>
      </section>

      {/* ---------- 04 · VOICE ---------- */}
      <section>
        <div className="wrap cols">
          <div>
            <Label n="04">Voice</Label>
            <Reveal i={1}><h2 className="display">Speak naturally.<br />Aria understands.</h2></Reveal>
            <Reveal i={2}>
              <p className="body sub">Have real conversations with Aria. Interrupt, clarify,
              ask follow-ups — just like you would with a person.</p>
            </Reveal>
            <Reveal i={3}><a className="btn ghost" href={DOWNLOAD} download="Aria.dmg">Try speaking →</a></Reveal>
          </div>
          <Reveal i={2} className="voiceRingWrap" aria-hidden="true">
            <motion.div
              className="voiceRing"
              animate={reduce ? {} : { scale: [1, 1.06, 1] }}
              transition={{ duration: 3.4, repeat: Infinity, ease: "easeInOut" }}
            >
              <Blob size={64} mood="listening" />
            </motion.div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 05 · ACTIONS ---------- */}
      <section>
        <div className="wrap cols">
          <div>
            <Label n="05">Actions</Label>
            <Reveal i={1}><h2 className="display">Aria gets<br />things done.</h2></Reveal>
            <Reveal i={2}>
              <p className="body sub">From drafting emails to analyzing data, Aria can take
              action across your apps so you can focus on what matters.</p>
            </Reveal>
            <motion.ul className="askList"
              initial="hidden" whileInView="visible" viewport={{ once: true, amount: 0.5 }}
              variants={{ visible: { transition: { staggerChildren: 0.14, delayChildren: 0.2 } } }}>
              {["Brief me on my day", "Run my morning startup",
                "Continue my Verdai work", "What did I do today?"].map((s) => (
                <motion.li key={s} variants={{
                  hidden: { opacity: 0, x: -12 },
                  visible: { opacity: 1, x: 0, transition: { duration: 0.45 } },
                }}>
                  <span className="tick">✓</span> {s}
                </motion.li>
              ))}
            </motion.ul>
          </div>
          <Reveal i={2} className="noteCardWrap" aria-hidden="true">
            <div className="noteCard">
              <div className="noteHead"><span className="noteOrb"><Blob size={18} mood="calm" /></span> Aria</div>
              <motion.div initial="hidden" whileInView="visible" viewport={{ once: true, amount: 0.5 }}
                variants={{ visible: { transition: { staggerChildren: 0.22, delayChildren: 0.4 } } }}>
                {[
                  ["Briefing ready", "3 meetings, one suggested focus"],
                  ["Recipe complete", "Calendar, Mail, briefing — done"],
                  ["Project recalled", "Verdai — deck finished yesterday"],
                  ["Timeline", "14 things done today"],
                ].map(([t, s]) => (
                  <motion.div key={t} className="noteRow" variants={{
                    hidden: { opacity: 0, y: 12 },
                    visible: { opacity: 1, y: 0, transition: { duration: 0.5, ease: "easeOut" } },
                  }}>
                    <strong>{t}</strong><span>{s}</span>
                  </motion.div>
                ))}
              </motion.div>
              <span className="noteAll">View all actions</span>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 06 · INTELLIGENCE ---------- */}
      <section id="intelligence">
        <div className="wrap cols">
          <div>
            <Label n="06">Intelligence</Label>
            <Reveal i={1}><h2 className="display">She remembers.<br />She anticipates.</h2></Reveal>
            <Reveal i={2}>
              <p className="body sub">Aria runs your day, not just your commands. A briefing
              every morning. A timeline of everything you got done. Projects she picks up
              where you left them. Watchers that stay quiet until something actually changed.</p>
            </Reveal>
            <ul className="plainList">
              {['Daily briefing — calendar, reminders, projects, one focus',
                'Timeline — “what did I do today?”, answered',
                'Project memory — “continue my Verdai work”',
                'Recipes & focus modes — your workflows, repeatable',
                'Watchers — inbox and web, fingerprinted, never noisy'].map((s, i) => (
                <Reveal key={s} i={i + 2}><li>{s}</li></Reveal>
              ))}
            </ul>
          </div>
          <Reveal i={2} className="noteCardWrap" aria-hidden="true">
            <div className="noteCard">
              <div className="noteHead"><span className="noteOrb"><Blob size={18} mood="calm" /></span> Your briefing</div>
              <motion.div initial="hidden" whileInView="visible" viewport={{ once: true, amount: 0.5 }}
                variants={{ visible: { transition: { staggerChildren: 0.22, delayChildren: 0.4 } } }}>
                {[
                  ["Today", "Investor sync 10:00 · design review 2:00"],
                  ["Carry-over", "Pricing model finished — deck needs it"],
                  ["Suggested focus", "Close the pricing question before 10"],
                  ["Runs on your Mac", "Local model · private · free"],
                ].map(([t, s]) => (
                  <motion.div key={t} className="noteRow" variants={{
                    hidden: { opacity: 0, y: 12 },
                    visible: { opacity: 1, y: 0, transition: { duration: 0.5, ease: "easeOut" } },
                  }}>
                    <strong>{t}</strong><span>{s}</span>
                  </motion.div>
                ))}
              </motion.div>
              <span className="noteAll">Say "brief me"</span>
            </div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 07 · PRIVACY ---------- */}
      <section id="privacy">
        <div className="wrap cols">
          <div>
            <Label n="07">Privacy</Label>
            <Reveal i={1}><h2 className="display">Your data stays<br />your data.</h2></Reveal>
            <Reveal i={2}>
              <p className="body sub">Aria is built with privacy at the core. Everything can be
              processed on your Mac. Nothing leaves your device without you choosing it.</p>
            </Reveal>
            <ul className="plainList">
              {["Local model by default — one-click setup, sized to your Mac",
                "On-device processing", "No cloud storage", "Keys in your Keychain",
                "You're in control — every action logged, undoable"].map((s, i) => (
                <Reveal key={s} i={i + 2}><li>{s}</li></Reveal>
              ))}
            </ul>
          </div>
          <Reveal i={2} className="lockWrap" aria-hidden="true">
            <div className="lockCard"><div className="lockCircle"><span className="lockShape" /></div></div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 08 · SETUP GUIDE ---------- */}
      <section id="setup" className="setupSec firstSection">
        <div className="wrap">
          <Label n="08">Setup Guide</Label>
          <Reveal i={1}><h2 className="display">Up and running<br />in 5 minutes.</h2></Reveal>
          <Reveal i={2}>
            <p className="body sub">A few one-time steps and Aria is yours.</p>
          </Reveal>
          <div className="setupGrid">
            {setupSteps.map((step, i) => (
              <motion.div
                key={step.n}
                className={`setupCard${step.n === "05" ? " setupCardFull" : ""}`}
                initial={{ opacity: 0, y: reduce ? 0 : 40, scale: reduce ? 1 : 0.98 }}
                whileInView={{ opacity: 1, y: 0, scale: 1 }}
                viewport={{ once: true, margin: "-60px" }}
                transition={{ duration: 0.8, delay: i * 0.1, ease: [0.22, 1, 0.36, 1] }}
              >
                <span className="setupN mono">{step.n}</span>
                <h4 className="setupTitle">{step.title}</h4>
                <p className="setupBody">{step.body}</p>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* ---------- 09 · DOWNLOAD (dark, mirrors hero) ---------- */}
      <section id="download" className="downloadDark firstSection">
        <Aurora className="auroraDownload" />
        <div className="wrap downloadInner">
          <Reveal i={0}><span className="mono labelLight">Download</span></Reveal>
          <Reveal i={1}><h2 className="display downloadTitle">Ready to try Aria.</h2></Reveal>
          <Reveal i={2}><p className="downloadSub">Free to download. No account needed. Runs on your Mac — local by default.</p></Reveal>
          <Reveal i={3}>
            <Magnetic className="btnLight downloadCta" href={DOWNLOAD} download="Aria.dmg">
              Download for Mac ↓
            </Magnetic>
          </Reveal>
          <Reveal i={4}>
            <p className="waitlistLabel">Or join the list for launch updates:</p>
            <Waitlist />
          </Reveal>
        </div>
      </section>

      {/* ---------- footer ---------- */}
      <footer>
        <div className="wrap footGrid">
          <div className="footBrand">
            <div className="brand footBrandColor"><span className="dot dotLight" /> Aria</div>
            <p className="footTagline">The assistant that lives on your Mac.</p>
          </div>
          <div>
            <h5 className="mono footHeading">Product</h5>
            <a href={DOWNLOAD} download="Aria.dmg">Download</a>
            <a href="#features">Features</a>
            <a href="#setup">Setup</a>
          </div>
          <div className="footMeta">
            <div className="social">
              <a href={GITHUB} target="_blank" rel="noreferrer">GitHub</a>
              <a href={`mailto:${CONTACT}`}>Email</a>
            </div>
            <span className="footCopy">© 2026 Aria</span>
          </div>
        </div>
      </footer>
    </>
  );
}
