import { useState } from "react";
import { motion, useReducedMotion } from "framer-motion";
import Blob from "./Blob.jsx";

const DOWNLOAD = "https://github.com/coderarush/Aria/releases/latest";
const GITHUB = "https://github.com/coderarush/Aria";
// Waitlist backend (e.g. a Formspree/Buttondown endpoint accepting POST JSON
// {email}). Empty → the form falls back to a mailto compose. See site/README.md.
const WAITLIST_ENDPOINT = "";
const CONTACT = "arushp@icloud.com";

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
      viewport={{ once: true, margin: "-60px" }}
    >
      {children}
    </motion.div>
  );
}

/* ---------- panel 2: capabilities ---------- */
const capabilities = [
  ["◎", "Acts, doesn't narrate", "Opens the app, finds the button, sends the message — she does the task."],
  ["✦", "Sees what you see", "Reads the focused window, the selection, the field you're in."],
  ["⌘", "Multi-step autonomy", "Plans, executes, verifies, recovers — and resumes if interrupted."],
  ["▤", "Knows your work", "Indexes your notes, PDFs and code on-device. Answers with sources."],
  ["◴", "Works in the background", "Daily briefings, folder watching, recurring goals — set once."],
  ["▣", "Local-first", "Everyday tasks can run on a local model. Cloud is optional."],
];

/* ---------- panel 5: task cards ---------- */
const taskCards = [
  ["“Prepare me for tomorrow's meeting.”",
   ["Checks your calendar", "Finds last week's notes", "Writes a one-page briefing"]],
  ["“Organize my Downloads folder.”",
   ["Sorts new files by type", "Creates sensible folders", "Deletes nothing"]],
];

/* ---------- panel 8: blog teasers ---------- */
const posts = [
  ["Why the model isn't the product", "Execution, context and memory are.", "Design"],
  ["Local-first is a feature", "What stays on your Mac, and why it matters.", "Privacy"],
];

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
    } catch {
      setState("error");
    }
  };

  if (state === "done") return <p className="waitlistDone">You're on the list — we'll email you at launch.</p>;
  return (
    <form className="waitlist" onSubmit={submit} aria-label="Request early access">
      <input
        type="email" required value={email} placeholder="you@example.com"
        aria-label="Email address" onChange={(e) => setEmail(e.target.value)}
      />
      <button className="btn" type="submit" disabled={state === "sending"}>
        {state === "sending" ? "Joining…" : "Request access"}
      </button>
      {state === "error" && <span className="waitlistErr">Something hiccuped — try again.</span>}
    </form>
  );
}

export default function App() {
  const reduce = useReducedMotion();

  return (
    <>
      {/* ---------- nav ---------- */}
      <div className="wrap">
        <nav className="nav">
          <div className="brand"><span className="dot" /> Aria</div>
          <div className="links">
            <a href="#features">Features</a>
            <a href="#voice">Voice</a>
            <a href="#blog">Blog</a>
            <a href="#about">About</a>
            <a className="btn" href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
          </div>
        </nav>

        {/* ---------- 1 · hero ---------- */}
        <header className="hero">
          <div>
            <motion.h1 className="display" variants={rise} custom={0} initial="hidden" animate="show">
              The assistant<br />that lives on<br />your Mac.
            </motion.h1>
            <motion.p className="lede" variants={rise} custom={1} initial="hidden" animate="show">
              Say “Hey Aria.” She hears you, sees your screen, and operates your
              apps by voice — she does the task, not just the talking.
            </motion.p>
            <motion.div className="cta" variants={rise} custom={2} initial="hidden" animate="show">
              <a className="btn" href={DOWNLOAD} target="_blank" rel="noreferrer">Download for Mac</a>
              <a className="btn ghost" href={GITHUB} target="_blank" rel="noreferrer">View source</a>
            </motion.div>
            <motion.span className="mono fine" variants={rise} custom={3} initial="hidden" animate="show">
              Free · Open source · macOS 14+
            </motion.span>
          </div>
          <motion.div
            className="heroBlob"
            initial={{ opacity: 0, scale: 0.7 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 1.1, ease: [0.22, 1, 0.36, 1], delay: 0.15 }}
          >
            <Blob size={420} mood="idle" />
          </motion.div>
        </header>
      </div>

      {/* ---------- 2 · capabilities ---------- */}
      <section id="features" className="capabilities">
        <div className="wrap">
          <Reveal><h2 className="display center">Powerful capabilities.<br />Reliable by design.</h2></Reveal>
          <Reveal i={1}>
            <p className="sub center">A real tool system with safety gates, an activity log, and undo —
            built to complete work, not to chat about it.</p>
          </Reveal>
          <div className="capGrid">
            {capabilities.map(([glyph, title, body], i) => (
              <Reveal key={title} i={i} className="capCard">
                <span className="glyph" aria-hidden="true">{glyph}</span>
                <h4>{title}</h4>
                <p>{body}</p>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* ---------- 3 · tiny icon ---------- */}
      <section className="tiny">
        <div className="wrap tinyGrid">
          <Reveal>
            <h2 className="display">One tiny icon.<br />Always within reach.</h2>
            <p className="sub">No window to manage, no tab to keep open. Aria lives in your
            menu bar and rises as a single living orb when you call —
            <span className="mono"> ⌥Space</span> to talk, <span className="mono">⌥⇧Space</span> to type.</p>
          </Reveal>
          <Reveal i={1} className="menubarMock" aria-hidden="true">
            <div className="mbBar">
              <span className="mbIcon active">⬡</span>
              <span className="mbIcon">◌</span><span className="mbIcon">♪</span>
              <span className="mbIcon">⚙</span><span className="mbTime mono">Tue 9:41</span>
            </div>
            <div className="mbDrop">
              <div className="mbRow strong">Talk to Aria <span className="mono">⌥Space</span></div>
              <div className="mbRow">Type to Aria… <span className="mono">⌥⇧Space</span></div>
              <div className="mbRow">Settings…</div>
              <div className="mbGlow" />
            </div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 4 · voice ---------- */}
      <section id="voice" className="voice">
        <div className="wrap tinyGrid">
          <Reveal>
            <h2 className="display">Speak naturally.<br />Aria understands.</h2>
            <p className="sub">The wake word runs entirely on-device. Talk over her and she stops
            to listen. Say “this”, “her”, “the selection” — she resolves them from
            what's in front of you.</p>
            <a className="btn ghost" href="#tasks">See her work ↓</a>
          </Reveal>
          <Reveal i={1} className="voiceRingWrap" aria-hidden="true">
            <motion.div
              className="voiceRing"
              animate={reduce ? {} : { scale: [1, 1.04, 1] }}
              transition={{ duration: 3.2, repeat: Infinity, ease: "easeInOut" }}
            >
              <div className="voiceCore" />
            </motion.div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 5 · gets things done ---------- */}
      <section id="tasks" className="tasks">
        <div className="wrap">
          <Reveal><h2 className="display center">Aria gets things done.</h2></Reveal>
          <Reveal i={1}>
            <p className="sub center">Give her an outcome, not a command. She plans the steps,
            runs them across your apps, and tells you when it's done.</p>
          </Reveal>
          <div className="taskStack">
            {taskCards.map(([ask, steps], i) => (
              <Reveal key={ask} i={i} className={`taskCard ${i === 1 ? "tilt" : ""}`}>
                <h4>{ask}</h4>
                <motion.ul
                  initial="hidden" whileInView="visible"
                  viewport={{ once: true, amount: 0.7 }}
                  variants={{ visible: { transition: { staggerChildren: 0.25, delayChildren: 0.3 } } }}
                >
                  {steps.map((s) => (
                    <motion.li key={s} variants={{
                      hidden: { opacity: 0, x: -8 },
                      visible: { opacity: 1, x: 0, transition: { duration: 0.4 } },
                    }}>
                      <span className="tick">✓</span> {s}
                    </motion.li>
                  ))}
                </motion.ul>
              </Reveal>
            ))}
          </div>
          <Reveal i={3}>
            <p className="fine center mono">Anything irreversible — Send, Pay, Delete — asks first.</p>
          </Reveal>
        </div>
      </section>

      {/* ---------- 6 · privacy ---------- */}
      <section className="privacy">
        <div className="wrap tinyGrid">
          <Reveal>
            <h2 className="display">Your data stays<br />your data.</h2>
            <ul className="plainList">
              <li>Wake word detected on-device — the mic never streams to a server</li>
              <li>Your knowledge index never leaves this Mac</li>
              <li>Everyday tasks can run on a local model — cloud is optional</li>
              <li>Keys in the macOS Keychain · screenshots never written to disk</li>
              <li>Every action visible in an activity log, with undo</li>
            </ul>
          </Reveal>
          <Reveal i={1} className="lockWrap" aria-hidden="true">
            <div className="lockCard"><span className="lock">🔒</span></div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 7 · early access ---------- */}
      <section id="access" className="access">
        <div className="wrap tinyGrid">
          <Reveal>
            <h2 className="display">Early access for<br />focused people.</h2>
            <p className="sub">Aria is in pre-release. Grab the build today, or leave your
            email and get the polished release the day it ships.</p>
            <Waitlist />
          </Reveal>
          <Reveal i={1} className="laptopWrap" aria-hidden="true">
            <div className="laptop">
              <div className="laptopScreen">
                <div className="laptopOrb"><Blob size={120} mood="confident" /></div>
              </div>
              <div className="laptopBase" />
            </div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 8 · blog ---------- */}
      <section id="blog" className="blog">
        <div className="wrap">
          <Reveal>
            <h2 className="display center">Thoughts on design, privacy,<br />and the future of computing.</h2>
          </Reveal>
          <div className="postList">
            {posts.map(([title, sub, tag], i) => (
              <Reveal key={title} i={i} className="post">
                <span className="postAvatar" aria-hidden="true" />
                <div>
                  <h4>{title}</h4>
                  <p>{sub}</p>
                </div>
                <span className="mono postTag">{tag}</span>
              </Reveal>
            ))}
          </div>
          <Reveal i={3}><p className="center"><a className="btn ghost" href={GITHUB} target="_blank" rel="noreferrer">Read the blog →</a></p></Reveal>
        </div>
      </section>

      {/* ---------- 9 · about ---------- */}
      <section id="about" className="about">
        <div className="wrap tinyGrid">
          <Reveal>
            <h2 className="display">About Aria</h2>
            <p className="sub">Aria is built by a small team that believes the computer should do
            the work — that apps are implementation details, and that the most
            personal assistant is one that runs on your own machine.</p>
            <p className="sub">Open source, free to run on your own key, and engineered
            execution-first: reliability is the feature.</p>
          </Reveal>
          <Reveal i={1} className="teamGrid" aria-hidden="true">
            {["A", "R", "I", "A"].map((ch, i) => (
              <div key={i} className="teamPhoto"><span>{ch}</span></div>
            ))}
          </Reveal>
        </div>
      </section>

      {/* ---------- footer ---------- */}
      <footer>
        <div className="wrap footGrid">
          <div>
            <div className="brand"><span className="dot" /> Aria</div>
            <p className="fine">The assistant that lives on your Mac.</p>
          </div>
          <div>
            <h5 className="mono">Product</h5>
            <a href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
            <a href="#features">Features</a>
            <a href="#access">Early access</a>
          </div>
          <div>
            <h5 className="mono">Company</h5>
            <a href="#about">About</a>
            <a href="#blog">Blog</a>
            <a href={`mailto:${CONTACT}`}>Contact</a>
          </div>
          <div>
            <h5 className="mono">Open source</h5>
            <a href={GITHUB} target="_blank" rel="noreferrer">GitHub</a>
            <a href={`${GITHUB}/releases`} target="_blank" rel="noreferrer">Releases</a>
            <a href={`${GITHUB}/blob/main/LICENSE`} target="_blank" rel="noreferrer">License</a>
          </div>
        </div>
      </footer>
    </>
  );
}
