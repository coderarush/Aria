import React, { useState, useRef, useEffect } from "react";
import { motion, AnimatePresence, useScroll, useTransform } from "framer-motion";
import VoiceOrb from "./VoiceOrb.jsx";

const EASE = [0.16, 1, 0.3, 1];

/* kinetic headline line: clip-reveals upward */
function KLine({ children, delay = 0 }) {
  return (
    <span className="kline">
      <motion.span initial={{ y: "115%" }} animate={{ y: 0 }} transition={{ duration: 0.95, ease: EASE, delay }}>
        {children}
      </motion.span>
    </span>
  );
}

/* ---------- reusable reveal ---------- */
function Reveal({ children, delay = 0, y = 26, className, ...rest }) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-12%" }}
      transition={{ duration: 0.7, ease: EASE, delay }}
      {...rest}
    >
      {children}
    </motion.div>
  );
}

const stagger = {
  hidden: {},
  show: { transition: { staggerChildren: 0.08, delayChildren: 0.05 } },
};
const item = {
  hidden: { opacity: 0, y: 22 },
  show: { opacity: 1, y: 0, transition: { duration: 0.7, ease: EASE } },
};

/* ---------- animated aurora ---------- */
function Aurora() {
  const blobs = [
    { c: "var(--violet)", s: 560, x: "-12vw", y: "-10vw", d: 16 },
    { c: "var(--pink)", s: 600, x: "70vw", y: "4vw", d: 21 },
    { c: "var(--cyan)", s: 520, x: "32vw", y: "58vh", d: 26 },
  ];
  return (
    <div className="aurora">
      {blobs.map((b, i) => (
        <motion.div
          key={i}
          className="b"
          style={{ width: b.s, height: b.s, left: b.x, top: b.y, background: `radial-gradient(circle, ${b.c}, transparent 62%)` }}
          animate={{ x: [0, 60, -30, 0], y: [0, -40, 30, 0], scale: [1, 1.15, 0.95, 1] }}
          transition={{ duration: b.d, repeat: Infinity, ease: "easeInOut" }}
        />
      ))}
    </div>
  );
}

/* ---------- hero orb ---------- */
function Orb() {
  return (
    <motion.div className="heroOrb" initial={{ scale: 0.7, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ duration: 1, ease: EASE }}>
      <motion.div className="ring" animate={{ rotate: 360 }} transition={{ duration: 40, repeat: Infinity, ease: "linear" }} />
      <motion.div
        className="core"
        animate={{ scale: [1, 1.06, 1], filter: ["hue-rotate(0deg)", "hue-rotate(24deg)", "hue-rotate(0deg)"] }}
        transition={{ duration: 5, repeat: Infinity, ease: "easeInOut" }}
      />
    </motion.div>
  );
}

/* ---------- live console ---------- */
function Console() {
  const [done, setDone] = useState(false);
  const [reply, setReply] = useState(false);
  useEffect(() => {
    let t1, t2, loop;
    const run = () => {
      setDone(false); setReply(false);
      t1 = setTimeout(() => setDone(true), 1500);
      t2 = setTimeout(() => setReply(true), 2200);
    };
    run();
    loop = setInterval(run, 7000);
    return () => { clearTimeout(t1); clearTimeout(t2); clearInterval(loop); };
  }, []);
  return (
    <div className="win">
      <div className="bar">
        <i /><i /><i /><span className="lab">Aria · listening</span>
        <span className="wv">
          {[0, 1, 2, 3, 4].map((i) => (
            <motion.span key={i} animate={{ height: ["24%", "100%", "24%"] }} transition={{ duration: 1.1, repeat: Infinity, ease: "easeInOut", delay: i * 0.13 }} style={{ height: "30%" }} />
          ))}
        </span>
      </div>
      <div className="chat">
        <div className="msg you">Hey Aria — research the best USB mics and save a summary to a note.</div>
        <div className="msg aria">On it. Searching now, then I'll write it up.</div>
        <div className="panel">
          <div className="h">Task · 3 steps</div>
          <div className="st on"><b>✓</b>Search the web for the best USB mics</div>
          <div className="st on"><b>✓</b>Write a short summary</div>
          <div className={"st" + (done ? " on" : "")}><b>✓</b>Save it to a note</div>
        </div>
        <AnimatePresence>
          {reply && (
            <motion.div className="msg aria" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.4, ease: EASE }}>
              Done — saved “Best USB Mics” to your notes. The Shure MV7 came out on top.
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

/* ---------- feature card ---------- */
function Card({ icon, title, body, cls }) {
  return (
    <motion.div
      className={"card " + (cls || "")}
      variants={item}
      whileHover={{ y: -5 }}
      transition={{ type: "spring", stiffness: 300, damping: 22 }}
      onMouseMove={(e) => {
        const g = e.currentTarget.querySelector(".glow");
        if (g) g.style.opacity = "0.4";
      }}
      onMouseLeave={(e) => { const g = e.currentTarget.querySelector(".glow"); if (g) g.style.opacity = "0"; }}
    >
      <span className="glow" />
      <div className="ic">{icon}</div>
      <h3>{title}</h3>
      <p>{body}</p>
    </motion.div>
  );
}

/* ---------- minimal line icons ---------- */
const I = {
  cursor: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="url(#vc)" strokeWidth="1.8"><defs><linearGradient id="vc" x1="0" y1="0" x2="1" y2="1"><stop stopColor="#8b5cff" /><stop offset="1" stopColor="#34c8ff" /></linearGradient></defs><path d="M4 4l7 16 2-7 7-2L4 4z" strokeLinejoin="round" /></svg>,
  flow: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8b5cff" strokeWidth="1.8"><circle cx="6" cy="6" r="2" /><circle cx="18" cy="12" r="2" /><circle cx="6" cy="18" r="2" /><path d="M8 6h6a2 2 0 012 2v2M8 18h6a2 2 0 002-2" strokeLinecap="round" /></svg>,
  wave: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#34c8ff" strokeWidth="1.8" strokeLinecap="round"><path d="M3 12h2M7 8v8M11 5v14M15 8v8M19 11v2M21 12h0" /></svg>,
  brain: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#ff5fb0" strokeWidth="1.8"><path d="M9 4a3 3 0 00-3 3 3 3 0 00-2 5 3 3 0 002 5 3 3 0 006 0V4a3 3 0 00-3 0z" strokeLinejoin="round" /></svg>,
  cal: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8b5cff" strokeWidth="1.8"><rect x="4" y="5" width="16" height="16" rx="2" /><path d="M4 9h16M8 3v4M16 3v4" strokeLinecap="round" /></svg>,
  lock: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#34c8ff" strokeWidth="1.8"><rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8 11V8a4 4 0 018 0v3" /></svg>,
  inf: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="url(#vc2)" strokeWidth="1.8"><defs><linearGradient id="vc2" x1="0" y1="0" x2="1" y2="0"><stop stopColor="#8b5cff" /><stop offset="1" stopColor="#34c8ff" /></linearGradient></defs><path d="M7 12a3 3 0 100-.01M17 12a3 3 0 110-.01M9.5 12c1.5-2.5 3.5-2.5 5 0s3.5 2.5 5 0" strokeLinecap="round" /></svg>,
};

const check = <svg width="16" height="16" viewBox="0 0 16 16" fill="none"><path d="M3 8.5l3.5 3.5L13 4.5" stroke="#34c8ff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></svg>;

const FAQS = [
  ["Is it really free to run?", "Yes. You pay once for the app. It runs on the free tiers of several AI providers and rotates across them, so you never pay per use. Each provider key is free to create."],
  ["What does “works any app” mean?", "Aria reads the controls on your screen and can click, type, scroll, and run menus in any Mac app — by voice. For apps it can't read directly, it looks at the screen with vision. It confirms before destructive actions and shows a marker you can stop."],
  ["Where does my data go?", "Aria runs on your Mac. Wake-word detection and your optional voiceprint stay on-device. Only the request you make goes to the provider you chose."],
  ["Do I need to be technical?", "No. Install it, grant microphone and accessibility access, paste a free key, and start talking."],
];

function FAQItem({ q, a }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="q">
      <button onClick={() => setOpen((o) => !o)}>
        {q}
        <motion.span className="pm" animate={{ rotate: open ? 45 : 0 }} transition={{ duration: 0.3, ease: EASE }}>+</motion.span>
      </button>
      <AnimatePresence initial={false}>
        {open && (
          <motion.div className="a" initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={{ duration: 0.34, ease: EASE }}>
            <p>{a}</p>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

export default function App() {
  const { scrollYProgress } = useScroll();
  const orbY = useTransform(scrollYProgress, [0, 0.3], [0, -90]);
  const orbOp = useTransform(scrollYProgress, [0, 0.25], [1, 0.2]);
  const year = new Date().getFullYear();

  return (
    <>
      <Aurora />
      <div className="grain" />

      <nav className="nav">
        <div className="inner">
          <a className="brand" href="#top"><span className="orb" />Aria</a>
          <div className="nlinks">
            <a className="l" href="#features">Features</a>
            <a className="l" href="#free">Cost</a>
            <a className="l" href="#price">Price</a>
            <motion.a className="btn sm" href="#price" whileHover={{ y: -2 }} whileTap={{ scale: 0.96 }} transition={{ type: "spring", stiffness: 400, damping: 20 }}>Download</motion.a>
          </div>
        </div>
      </nav>

      {/* HERO — the orb is the protagonist */}
      <header className="hero wrap" id="top">
        <motion.div className="orbWrap" style={{ y: orbY, opacity: orbOp }} initial={{ scale: 0.6, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ duration: 1.1, ease: EASE }}>
          <VoiceOrb size={420} />
        </motion.div>

        <motion.div className="eyebrow heroEy" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.5, duration: 0.8 }}>A spoken assistant for macOS</motion.div>
        <h1 className="heroH1">
          <KLine delay={0.2}>Ask out loud.</KLine>
          <KLine delay={0.34}>Aria <em>does it.</em></KLine>
        </h1>
        <motion.p className="lede heroLede" initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.7, duration: 0.8, ease: EASE }}>
          Not another chat window. Say what you want and it researches, writes, remembers, and <b>works the apps on your screen</b> for you.
        </motion.p>
        <motion.div className="cta" initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.84, duration: 0.8, ease: EASE }}>
          <motion.a className="btn" href="#price" whileHover={{ y: -3, scale: 1.02 }} whileTap={{ scale: 0.97 }} transition={{ type: "spring", stiffness: 350, damping: 18 }}>Download for Mac</motion.a>
          <motion.a className="btn ghost" href="#demo" whileHover={{ y: -3 }} whileTap={{ scale: 0.97 }} transition={{ type: "spring", stiffness: 350, damping: 18 }}>See it work</motion.a>
        </motion.div>
        <motion.div className="note" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 1, duration: 0.8 }}>One purchase · free to run · macOS 14+</motion.div>

        <Reveal className="stage" id="demo" delay={0.1}><Console /></Reveal>
      </header>

      {/* FEATURES */}
      <section id="features" className="wrap">
        <Reveal className="shead"><div className="eyebrow">Capabilities</div><h2 style={{ marginTop: 16 }}>Not a chatbot. An assistant.</h2><p>Everything below works from your voice.</p></Reveal>
        <motion.div className="bento" variants={stagger} initial="hidden" whileInView="show" viewport={{ once: true, margin: "-10%" }}>
          <Card cls="big" icon={I.cursor} title="Works any app" body="Aria sees your screen and clicks, types, scrolls, and runs menus in any Mac app — even ones with no scripting. The thing no other voice assistant can do. It asks before anything irreversible and shows a marker while it's in control." />
          <Card cls="wide" icon={I.flow} title="Multi-step tasks" body="Give a goal; it plans the steps, runs them with a crew of agents, checks the result, recovers from snags, and reports back." />
          <Card icon={I.wave} title="Real conversation" body="“Hey Aria,” then talk. Cut in mid-sentence and it stops to listen." />
          <Card icon={I.brain} title="Remembers you" body="“Remember that…” and it keeps the fact across days." />
          <Card cls="wide" icon={I.cal} title="Runs your day" body="Calendar, reminders, mail, notes, music — spoken, hands free." />
          <Card cls="wide" icon={I.lock} title="Stays on your Mac" body="Wake-word listening and your voiceprint never leave the machine." />
          <Card cls="wide" icon={I.inf} title="Free forever to run" body="Rotates across free AI providers — when one's out, it keeps going on the next." />
        </motion.div>
      </section>

      {/* FREE */}
      <section id="free" className="wrap">
        <Reveal className="free">
          <div className="eyebrow">The economics</div>
          <h2 style={{ marginTop: 14 }}>Buy once. Run free forever.</h2>
          <p>Aria stacks the free tiers of multiple AI providers and moves to the next the moment one runs out — or to a model on your own Mac. No subscription. No usage bill.</p>
          <div className="provs">{["Gemini", "Groq", "Cerebras", "OpenRouter", "Local · Ollama"].map((p) => <span className="prov" key={p}>{p}</span>)}</div>
        </Reveal>
      </section>

      {/* PRICE */}
      <section id="price" className="wrap">
        <Reveal className="shead"><div className="eyebrow">Pricing</div><h2 style={{ marginTop: 16 }}>One price, kept forever.</h2><p>No subscription. Free updates.</p></Reveal>
        <Reveal delay={0.05}>
          <motion.div className="price" whileHover={{ y: -4 }} transition={{ type: "spring", stiffness: 300, damping: 22 }}>
            <div className="amt">$29 <em>once</em></div>
            <ul>
              {["Voice assistant + multi-step tasks", "Works any app on screen", "Memory across sessions", "Free-to-run provider engine", "Updates for life"].map((f) => <li key={f}>{check}{f}</li>)}
            </ul>
            <motion.a className="btn" id="buy" href="#" style={{ width: "100%", justifyContent: "center" }} whileHover={{ y: -2 }} whileTap={{ scale: 0.97 }} transition={{ type: "spring", stiffness: 350, damping: 18 }}>Download for Mac</motion.a>
            <div className="note">macOS 14 Sonoma+ · Apple Silicon &amp; Intel</div>
          </motion.div>
        </Reveal>
      </section>

      {/* FAQ */}
      <section className="wrap">
        <Reveal className="shead"><div className="eyebrow">FAQ</div><h2 style={{ marginTop: 16 }}>Questions.</h2></Reveal>
        <Reveal className="faq">{FAQS.map(([q, a]) => <FAQItem key={q} q={q} a={a} />)}</Reveal>
      </section>

      <footer className="wrap">
        <div className="foot">
          <a className="brand" href="#top"><span className="orb" />Aria</a>
          <span className="meta">© {year} · Made for macOS · <a href="https://github.com/coderarush/Aria">GitHub</a></span>
        </div>
      </footer>
    </>
  );
}
