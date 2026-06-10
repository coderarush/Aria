import { useRef, useState } from "react";
import { motion, useScroll, useTransform, useReducedMotion } from "framer-motion";
import Blob from "./Blob.jsx";

const DOWNLOAD = "https://github.com/coderarush/Aria/releases/latest";
const GITHUB = "https://github.com/coderarush/Aria";
// Waitlist backend (POST JSON {email}). Empty → mailto fallback. See README.
const WAITLIST_ENDPOINT = "";
const CONTACT = "arushp@icloud.com";

/* Apple-style: content drifts up and settles as it enters the viewport. */
const rise = {
  hidden: { opacity: 0, y: 28 },
  show: (i = 0) => ({
    opacity: 1, y: 0,
    transition: { duration: 0.8, delay: i * 0.09, ease: [0.22, 1, 0.36, 1] },
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
      viewport={{ once: true, margin: "-70px" }}
    >
      {children}
    </motion.div>
  );
}

/* Numbered editorial section label, like the reference: "02 · FEATURES". */
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

  return (
    <>
      <div className="wrap">
        <nav className="nav">
          <div className="brand"><span className="dot" /> Aria</div>
          <div className="links">
            <a href="#features">Features</a>
            <a href="#privacy">Privacy</a>
            <a href="#blog">Blog</a>
            <a className="btn small" href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
          </div>
        </nav>

        {/* ---------- 01 · HERO ---------- */}
        <header className="hero" ref={heroRef}>
          <div>
            <motion.h1 className="display" variants={rise} custom={0} initial="hidden" animate="show">
              The assistant<br />that lives on<br />your Mac.
            </motion.h1>
            <motion.p className="body" variants={rise} custom={1} initial="hidden" animate="show">
              Say it, and it's done. Aria hears you, sees your screen, and
              operates your apps — so you stay in flow.
            </motion.p>
            <motion.div className="cta" variants={rise} custom={2} initial="hidden" animate="show">
              <a className="btn" href="#features">Meet Aria ↓</a>
              <a className="btn ghost" href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
            </motion.div>
          </div>
          <motion.div className="heroBlob"
            initial={{ opacity: 0, scale: 0.72 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 1.2, ease: [0.22, 1, 0.36, 1], delay: 0.15 }}
            style={{ scale: heroScale, y: heroY }}>
            <Blob size={430} mood="idle" />
          </motion.div>
        </header>
      </div>

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
            {[
              ["◉", "Voice first", "Natural conversation — no commands to memorize."],
              ["✦", "Context aware", "She sees the window, the selection, the field you're in."],
              ["↯", "Takes action", "Opens apps, clicks, types, sends — completes the task."],
              ["◌", "Private by default", "On-device wake word; your data stays on your Mac."],
            ].map(([glyph, title, body], i) => (
              <Reveal key={title} i={i} className="feat">
                <span className="featIcon" aria-hidden="true">{glyph}</span>
                <h4>{title}</h4>
                <p>{body}</p>
              </Reveal>
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
                <span>📶</span><span>🎧</span><span>🔋</span>
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
            <motion.div className="voiceRing"
              animate={reduce ? {} : { scale: [1, 1.035, 1] }}
              transition={{ duration: 3.4, repeat: Infinity, ease: "easeInOut" }}>
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
              {["Write an email to Sam", "Summarize this document",
                "Find tomorrow's meeting", "Create a project plan"].map((s) => (
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
                  ["Email drafted", "To: Sam — ready to review"],
                  ["Document summarized", "Key points saved to notes"],
                  ["Meeting found", "Tomorrow at 10:00 AM"],
                  ["Project plan created", "8 steps, in your notes"],
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

      {/* ---------- 06 · PRIVACY ---------- */}
      <section id="privacy">
        <div className="wrap cols">
          <div>
            <Label n="06">Privacy</Label>
            <Reveal i={1}><h2 className="display">Your data stays<br />your data.</h2></Reveal>
            <Reveal i={2}>
              <p className="body sub">Aria is built with privacy at the core. Everything can be
              processed on your Mac. Nothing leaves your device without you choosing it.</p>
            </Reveal>
            <ul className="plainList">
              {["On-device processing", "No cloud storage", "Keys in your Keychain",
                "You're in control — every action logged, undoable"].map((s, i) => (
                <Reveal key={s} i={i + 2}><li>{s}</li></Reveal>
              ))}
            </ul>
          </div>
          <Reveal i={2} className="lockWrap" aria-hidden="true">
            <div className="lockCard"><div className="lockCircle">🔒</div></div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 07 · DOWNLOAD ---------- */}
      <section id="download" className="downloadSec">
        <div className="wrap cols">
          <div>
            <Label n="07">Download</Label>
            <Reveal i={1}><h2 className="display">Early access for<br />focused people.</h2></Reveal>
            <Reveal i={2}>
              <p className="body sub">Aria is in pre-release. Grab the build today — free, open
              source — or leave your email for the polished release.</p>
            </Reveal>
            <Reveal i={3}><Waitlist /></Reveal>
          </div>
          <Reveal i={2} className="laptopWrap" aria-hidden="true">
            <div className="laptop">
              <div className="laptopScreen"><div className="laptopOrb"><Blob size={110} mood="confident" /></div></div>
              <div className="laptopBase" />
            </div>
          </Reveal>
        </div>
      </section>

      {/* ---------- 08 · BLOG ---------- */}
      <section id="blog">
        <div className="wrap cols">
          <div>
            <Label n="08">Blog</Label>
            <Reveal i={1}><h2 className="display">Thoughts on design,<br />privacy, and the<br />future of computing.</h2></Reveal>
            <Reveal i={2}><a className="btn ghost" href={GITHUB} target="_blank" rel="noreferrer">Visit the blog →</a></Reveal>
          </div>
          <div className="postCol">
            {[
              ["Why on-device AI is the future", "Jan 12, 2026"],
              ["Designing technology that disappears", "Mar 08, 2026"],
              ["Privacy isn't a feature. It's a foundation.", "Apr 02, 2026"],
            ].map(([t, d], i) => (
              <Reveal key={t} i={i} className="post">
                <span className="postThumb" aria-hidden="true" />
                <div><h4>{t}</h4><span className="mono postDate">{d}</span></div>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* ---------- 09 · ABOUT ---------- */}
      <section id="about">
        <div className="wrap cols">
          <div>
            <Label n="09">About</Label>
            <Reveal i={1}><h2 className="display">About Aria</h2></Reveal>
            <Reveal i={2}>
              <p className="body sub">We're a small team building the next generation of
              personal computing experiences. Aria is our first step.</p>
            </Reveal>
            <Reveal i={3}><a className="btn ghost" href={GITHUB} target="_blank" rel="noreferrer">Learn more about us →</a></Reveal>
          </div>
          <Reveal i={2} className="teamGrid" aria-hidden="true">
            {[0, 1, 2, 3].map((i) => <div key={i} className="teamPhoto" />)}
          </Reveal>
        </div>
      </section>

      {/* ---------- footer ---------- */}
      <footer>
        <div className="wrap footGrid">
          <div>
            <div className="brand"><span className="dot" /> Aria</div>
          </div>
          <div>
            <h5 className="mono">Product</h5>
            <a href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
            <a href="#features">Features</a>
            <a href="#download">Early access</a>
          </div>
          <div>
            <h5 className="mono">Company</h5>
            <a href="#about">About</a>
            <a href="#blog">Blog</a>
            <a href={`mailto:${CONTACT}`}>Contact</a>
          </div>
          <div className="footMeta">
            <div className="social">
              <a href={GITHUB} target="_blank" rel="noreferrer" aria-label="GitHub">◉</a>
              <a href={`mailto:${CONTACT}`} aria-label="Email">✉</a>
            </div>
            <span>© 2026 Aria. All rights reserved.</span>
          </div>
        </div>
      </footer>
    </>
  );
}
