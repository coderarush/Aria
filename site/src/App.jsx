import { motion } from "framer-motion";
import Blob from "./Blob.jsx";

const DOWNLOAD = "https://github.com/coderarush/Aria/releases/latest";
const GITHUB = "https://github.com/coderarush/Aria";

const rise = {
  hidden: { opacity: 0, y: 22 },
  show: (i = 0) => ({
    opacity: 1, y: 0,
    transition: { duration: 0.7, delay: i * 0.08, ease: [0.22, 1, 0.36, 1] },
  }),
};

function Reveal({ children, i = 0, className }) {
  return (
    <motion.div
      className={className}
      variants={rise}
      custom={i}
      initial="hidden"
      whileInView="show"
      viewport={{ once: true, margin: "-80px" }}
    >
      {children}
    </motion.div>
  );
}

const features = [
  ["01", "She acts — she doesn't lecture.",
   "Ask, and Aria opens the app, finds the button, types the message, sends it. Other screen assistants narrate the steps and leave the doing to you. Aria does the doing."],
  ["02", "Lives in your menu bar.",
   "No window to manage, no tab to keep open. Say “Hey Aria” and she rises from the corner, listens, and gets out of the way. On-device wake word — the mic never leaves your Mac to hear her name."],
  ["03", "Sees what you're looking at.",
   "She reads the focused window, the selected text, the field you're in. “Summarize this”, “reply to her”, “translate the selection” just work — no screenshots to attach, nothing to explain."],
  ["04", "Free, on your own key.",
   "Aria runs on Google's free Gemini tier with your own key. No subscription, no metered usage, no card. It stays free because you bring the key — not because we resell you back your own data."],
];

const phrases = [
  ["“Summarize this.”", "the article you're reading"],
  ["“Reply to her — I'm running late.”", "the email that's open"],
  ["“Open my notes and start a list.”", "across apps, by herself"],
  ["“What's on my calendar Thursday?”", "EventKit, on-device"],
  ["“Translate the selection to French.”", "whatever's highlighted"],
  ["“Find the export button and click it.”", "she sees the screen"],
];

export default function App() {
  return (
    <>
      <div className="wrap">
        <nav className="nav">
          <div className="brand"><span className="dot" /> Aria</div>
          <div className="links">
            <a href="#what">What she does</a>
            <a href="#say">Try saying</a>
            <a href={GITHUB} target="_blank" rel="noreferrer">Source</a>
            <a className="btn" href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
          </div>
        </nav>

        <header className="hero">
          <div>
            <motion.span className="mono eyebrow" variants={rise} custom={0} initial="hidden" animate="show">
              A voice agent for macOS
            </motion.span>
            <motion.h1 className="display" variants={rise} custom={1} initial="hidden" animate="show">
              The assistant<br />that actually<br />does it.
            </motion.h1>
            <motion.p className="lede" variants={rise} custom={2} initial="hidden" animate="show">
              Aria lives on your Mac, hears you, sees your screen, and operates your
              apps by voice — out loud, hands-free, and free.
            </motion.p>
            <motion.div className="cta" variants={rise} custom={3} initial="hidden" animate="show">
              <a className="btn" href={DOWNLOAD} target="_blank" rel="noreferrer">Download for Mac</a>
              <a className="btn ghost" href={GITHUB} target="_blank" rel="noreferrer">View source</a>
              <span className="free">Free forever · Apple Silicon & Intel</span>
            </motion.div>
          </div>
          <motion.div
            className="heroBlob"
            initial={{ opacity: 0, scale: 0.7 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 1.1, ease: [0.22, 1, 0.36, 1], delay: 0.15 }}
          >
            <Blob size={440} />
          </motion.div>
        </header>
      </div>

      <section className="statement">
        <div className="wrap">
          <Reveal>
            <p>
              Most “AI on your screen” will <em>tell you</em> how.{" "}
              <span className="accent">Aria just does it</span> — and then tells you it's done.
            </p>
          </Reveal>
        </div>
      </section>

      <section id="what" className="wrap">
        <div className="rows">
          {features.map(([num, title, body], i) => (
            <Reveal key={num} i={i}>
              <div className="row">
                <h3><span className="num mono">{num}</span><br />{title}</h3>
                <p>{body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      <section id="say" className="say">
        <div className="wrap">
          <Reveal>
            <h2 className="display">Just say it.</h2>
            <p className="sub">She resolves “this”, “her”, “the selection” from what's in front of you.</p>
          </Reveal>
          <div className="chips">
            {phrases.map(([say, ctx], i) => (
              <Reveal key={say} i={i % 3}>
                <div className="chip"><b>{say}</b> <span>— {ctx}</span></div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="close">
        <div className="wrap">
          <Reveal>
            <h2 className="display">Say “Hey Aria.”</h2>
            <div className="cta">
              <a className="btn" href={DOWNLOAD} target="_blank" rel="noreferrer">Download for Mac</a>
              <a className="btn ghost" href={GITHUB} target="_blank" rel="noreferrer">It's open source</a>
            </div>
          </Reveal>
        </div>
      </section>

      <footer className="wrap">
        <span>Aria — a free, native macOS voice agent.</span>
        <span>
          <a href={GITHUB} target="_blank" rel="noreferrer">GitHub</a> ·{" "}
          <a href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
        </span>
      </footer>
    </>
  );
}
