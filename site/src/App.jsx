import { useRef, useState } from "react";
import { motion, useScroll, useTransform, useReducedMotion } from "framer-motion";
import Blob from "./Blob.jsx";

const DOWNLOAD = "https://github.com/coderarush/Aria/releases/latest";
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
  "Voice control", "Computer use", "Memory & recall", "Daily briefings",
  "Recipes & automation", "Meeting notes", "Focus mode", "Calendar",
  "Email", "Screen awareness", "Always private",
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

export default function App() {
  const reduce = useReducedMotion();

  /* 01 hero: the blob recedes gently as the story begins. */
  const heroRef = useRef(null);
  const { scrollYProgress: heroP } = useScroll({ target: heroRef, offset: ["start start", "end start"] });
  const heroScale = useTransform(heroP, [0, 1], [1, reduce ? 1 : 0.86]);
  const heroY = useTransform(heroP, [0, 1], [0, reduce ? 0 : 70]);

  /* 02 features: the big blob crests into view from below as you scroll. */
  const featRef = useRef(null);
  const { scrollYProgress: featP } = useScroll({ target: featRef, offset: ["start end", "end start"] });
  const crestY = useTransform(featP, [0, 0.7], [reduce ? 0 : 170, 0]);

  const featureCards = [
    {
      glyph: "●",
      title: "Voice first",
      body: "Natural conversation — no commands to memorize.",
      iconClass: "featIconAmber",
    },
    {
      glyph: "◐",
      title: "Context aware",
      body: "She sees the window, the selection, the field you're in.",
      iconClass: "featIconSage",
    },
    {
      glyph: "→",
      title: "Takes action",
      body: "Opens apps, clicks, types, sends — completes the task.",
      iconClass: "featIconInk",
    },
    {
      glyph: "○",
      title: "Private by default",
      body: "On-device wake word; your data stays on your Mac.",
      iconClass: "featIconRose",
    },
  ];

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
      title: "Add your Gemini API key",
      body: "Open Aria → press ⌘, (Settings) → paste your key in the API section. Get a free key at ai.google.dev — no credit card required.",
    },
    {
      n: "04",
      title: "Say \"Hey Aria\"",
      body: "She wakes on the phrase \"Hey Aria\". Or press ⌥Space to talk, ⌥⇧Space to type. She appears as a small orb on your screen.",
    },
    {
      n: "05",
      title: "Try your first command",
      body: "\"Brief me on my day\" · \"What did I do today?\" · \"Summarize this email\" · \"Open my calendar\" · \"Remember this for later\"",
    },
  ];

  return (
    <>
      {/* ---------- nav ---------- */}
      <nav className="nav">
        <div className="wrap navInner">
          <div className="brand"><span className="dot" /> Aria</div>
          <div className="links">
            <a href="#features">Features</a>
            <a href="#privacy">Privacy</a>
            <a href="#setup">Setup</a>
            <a className="btn small" href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
          </div>
        </div>
      </nav>

      <div className="wrap">
        {/* ---------- 01 · HERO ---------- */}
        <header className="hero" ref={heroRef}>
          <div>
            <motion.h1
              className="display heroHeadline"
              initial={{ opacity: 0, y: reduce ? 0 : 40, scale: reduce ? 1 : 0.98 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              transition={{ duration: 0.9, ease: [0.22, 1, 0.36, 1] }}
            >
              The assistant<br />that lives on<br />your Mac.
            </motion.h1>
            <motion.p
              className="body heroBody"
              initial={{ opacity: 0, y: reduce ? 0 : 40 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.9, delay: 0.09, ease: [0.22, 1, 0.36, 1] }}
            >
              Say it, and it's done. Aria hears you, sees your screen, and
              operates your apps — so you stay in flow.
            </motion.p>
            <motion.div
              className="cta"
              initial={{ opacity: 0, y: reduce ? 0 : 40 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.9, delay: 0.18, ease: [0.22, 1, 0.36, 1] }}
            >
              <a className="btn" href="#features">Meet Aria ↓</a>
              <a className="btn ghost" href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
            </motion.div>
            {/* Animated scroll indicator */}
            <motion.div
              className="scrollIndicator"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ delay: 1.2, duration: 0.6 }}
              aria-hidden="true"
            >
              <motion.span
                className="scrollChevron"
                animate={reduce ? {} : { y: [0, 6, 0] }}
                transition={{ duration: 1.6, repeat: Infinity, ease: "easeInOut" }}
              >
                ↓
              </motion.span>
            </motion.div>
          </div>
          <motion.div
            className="heroBlob"
            initial={{ opacity: 0, scale: 0.72 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 1.2, ease: [0.22, 1, 0.36, 1], delay: 0.15 }}
            style={{ scale: heroScale, y: heroY }}
          >
            <div className="heroBlobGlow">
              <Blob size={430} mood="idle" />
            </div>
          </motion.div>
        </header>
      </div>

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

      {/* ---------- 02 · FEATURES ---------- */}
      <section id="features" ref={featRef}>
        <div className="wrap">
          <Label n="02">Features</Label>
          <Reveal i={1}><h2 className="display">Powerful capabilities.<br />Invisible by design.</h2></Reveal>
          <Reveal i={2}>
            <p className="body sub">Aria blends into your workflow so you can stay in flow
            and get more done.</p>
          </Reveal>
          <div className="featRow">
            {featureCards.map(({ glyph, title, body, iconClass }, i) => (
              <motion.div
                key={title}
                className="feat"
                initial={{ opacity: 0, y: reduce ? 0 : 40, scale: reduce ? 1 : 0.98 }}
                whileInView={{ opacity: 1, y: 0, scale: 1 }}
                viewport={{ once: true, margin: "-70px" }}
                transition={{ duration: 0.8, delay: i * 0.09, ease: [0.22, 1, 0.36, 1] }}
                whileHover={reduce ? {} : { y: -6 }}
              >
                <span className={`featIcon ${iconClass}`} aria-hidden="true">{glyph}</span>
                <h4>{title}</h4>
                <p>{body}</p>
              </motion.div>
            ))}
          </div>
        </div>
        <motion.div className="crest" style={{ y: crestY }} aria-hidden="true">
          <Blob size={360} mood="calm" />
        </motion.div>
      </section>

      {/* ---------- 03 · HOW IT WORKS ---------- */}
      <section>
        <div className="wrap">
          <Label n="03">How it works</Label>
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
            <Reveal i={3}><a className="btn ghost" href={DOWNLOAD} target="_blank" rel="noreferrer">Try speaking →</a></Reveal>
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
              {["Daily briefing — calendar, reminders, projects, one focus",
                "Timeline — “what did I do today?”, answered",
                "Project memory — “continue my Verdai work”",
                "Recipes & focus modes — your workflows, repeatable",
                "Watchers — inbox and web, fingerprinted, never noisy"].map((s, i) => (
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
      <section id="setup" className="setupSec">
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

      {/* ---------- 09 · DOWNLOAD ---------- */}
      <section id="download" className="downloadSec">
        <div className="wrap cols">
          <div>
            <Label n="09">Download</Label>
            <Reveal i={1}><h2 className="display">Ready to try Aria.</h2></Reveal>
            <Reveal i={2}>
              <p className="body sub">Free to download. No account needed. Just your Mac and a free Gemini key.</p>
            </Reveal>
            <Reveal i={3}>
              <a className="btn downloadBtn" href={DOWNLOAD} target="_blank" rel="noreferrer">Download for Mac ↓</a>
            </Reveal>
            <Reveal i={4}>
              <p className="waitlistLabel">Or join the email list for launch updates:</p>
              <Waitlist />
            </Reveal>
          </div>
          <Reveal i={2} className="laptopWrap" aria-hidden="true">
            <div className="laptop">
              <div className="laptopScreen"><div className="laptopOrb"><Blob size={110} mood="confident" /></div></div>
              <div className="laptopBase" />
            </div>
          </Reveal>
        </div>
      </section>

      {/* ---------- footer ---------- */}
      <footer>
        <div className="wrap footGrid">
          <div className="footBrand">
            <div className="brand"><span className="dot" /> Aria</div>
            <p className="footTagline">The assistant that lives on your Mac.</p>
          </div>
          <div>
            <h5 className="mono footHeading">Product</h5>
            <a href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
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
