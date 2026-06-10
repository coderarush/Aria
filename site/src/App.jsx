import { useRef, useState } from "react";
import { motion, useScroll, useTransform, useReducedMotion } from "framer-motion";
import Blob from "./Blob.jsx";

const DOWNLOAD = "https://github.com/coderarush/Aria/releases/latest";
const GITHUB = "https://github.com/coderarush/Aria";
// Waitlist backend (e.g. a Formspree/Buttondown endpoint). Leave empty to hide
// the form and keep Download as the only CTA. See site/README.md.
const WAITLIST_ENDPOINT = "";

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
   "Ask, and Aria opens the app, finds the button, types the message, sends it. She drives your apps, files, calendar, and email — read your inbox, draft a reply, send it (after she asks). Other screen assistants narrate the steps and leave the doing to you. Aria does the doing."],
  ["02", "Lives in your menu bar.",
   "No window to manage, no tab to keep open. Say “Hey Aria” and she rises from the corner as a single living orb, listens, and gets out of the way. On-device wake word — the mic never leaves your Mac to hear her name."],
  ["03", "Sees what you're looking at.",
   "She reads the focused window, the selected text, the field you're in — and, when the task calls for it, your clipboard, your Finder selection, the tab you're reading, or a real look at the screen. “Summarize this”, “reply to her”, “rename these” just work — only when it's relevant, never by default."],
  ["04", "Plans the task, runs it, finishes it.",
   "Give her a goal, not just a command. She breaks it into steps, runs them across your apps, passes each result forward, checks her own work and retries when something slips — narrating a short play-by-play. Walk away: she notifies you when it's done, and if she's interrupted she picks the task back up where she left off."],
  ["05", "Remembers — and uses it.",
   "Tell her once — “remember my sister's name is Mara”, “I write in British English” — and she keeps it across sessions and brings it into her planning, so she applies what she knows instead of asking twice."],
  ["06", "Safe, and reversible.",
   "Anything irreversible — Send, Pay, Delete — asks first. Every action she takes is written to a visible activity log, and you can undo her last change: “undo that.”"],
  ["07", "Free, on your own key.",
   "Aria runs on Google's free Gemini tier with your own key, and falls back across Groq, Cerebras and OpenRouter — or a fully local model — so she keeps working. No subscription, no metered usage, no card."],
];

const phrases = [
  ["“Summarize this.”", "the article you're reading"],
  ["“Check my email.”", "your inbox — Mail or Gmail"],
  ["“Draft a reply — I'm running late.”", "ready for you to send"],
  ["“Rename the selected files.”", "your Finder selection"],
  ["“What's on my calendar Thursday?”", "EventKit, on-device"],
  ["“Undo that.”", "rolls back her last change"],
  ["“Resume.”", "picks the task back up"],
  ["“Find the export button and click it.”", "she sees the screen"],
];

const steps = [
  ["Wake", "She listens for “Hey Aria” entirely on your Mac. No always-open stream to the cloud, no hot-word sent anywhere — the mic never leaves the machine to hear her name."],
  ["Understand", "She reads what's in front of you — active app, window, the field you're in, the text you've selected — and works out what “this”, “that”, and “her” actually mean."],
  ["Act", "She calls real tools to do the task across your apps, checks her own work, and tells you when it's done. Anything destructive — Send, Pay, Delete — asks first."],
];

const demoFlows = [
  ["“Prepare me for tomorrow's meeting.”",
   ["Checks your calendar", "Finds last week's notes", "Writes a one-page briefing", "Saves it to your notes"]],
  ["“Organize my Downloads folder.”",
   ["Reads the new files", "Creates sensible folders", "Sorts everything by type", "Deletes nothing"]],
  ["“What did the investor say about pricing?”",
   ["Searches your notes and PDFs", "Finds the call summary", "Answers with the source"]],
];

const founderFlows = ["Meeting prep", "Investor updates", "Research briefings", "Daily founder briefing"];
const devFlows = ["Repository-aware answers", "Terminal & git workflows", "Code search across projects", "Indexed docs & specs"];

function Waitlist() {
  const [email, setEmail] = useState("");
  const [state, setState] = useState("idle"); // idle | sending | done | error
  if (!WAITLIST_ENDPOINT) return null;

  const submit = async (e) => {
    e.preventDefault();
    if (!email.includes("@")) return;
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
    <form className="waitlist" onSubmit={submit} aria-label="Join the waitlist">
      <input
        type="email" required value={email} placeholder="you@example.com"
        aria-label="Email address" onChange={(e) => setEmail(e.target.value)}
      />
      <button className="btn" type="submit" disabled={state === "sending"}>
        {state === "sending" ? "Joining…" : "Join the waitlist"}
      </button>
      {state === "error" && <span className="waitlistErr">Something hiccuped — try again.</span>}
    </form>
  );
}

const faqs = [
  ["Is it really free?",
   "Yes. Aria runs on Google's Gemini free tier with your own key, and rotates across several keys plus free fallback providers (Groq, Cerebras, OpenRouter). No subscription, no metered usage, no card."],
  ["Does it send my screen to the cloud?",
   "Only when a task needs it, and only the relevant context. Wake-word detection is on-device, screenshots are never written to disk, and secure fields like passwords are hidden from her."],
  ["Will she click things without asking?",
   "Not the ones that matter. Anything irreversible — Send, Pay, Delete — stops and asks first. While she's driving your apps, a “Aria is controlling your Mac” indicator with a Stop button stays on screen. You're always in the loop."],
  ["How is this different from a screen-aware helper?",
   "Most of them are aware of your screen and guide you step by step. Aria does the steps — she operates the apps herself — and she's free and open source."],
  ["What do I need to run it?",
   "A Mac (Apple Silicon or Intel) on macOS 14 or later, and a free Gemini API key. That's it."],
];

export default function App() {
  const heroRef = useRef(null);
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll({ target: heroRef, offset: ["start start", "end start"] });
  // The blob recedes as the story begins — motion originates from her.
  const heroScale = useTransform(scrollYProgress, [0, 1], [1, reduce ? 1 : 0.82]);
  const heroY = useTransform(scrollYProgress, [0, 1], [0, reduce ? 0 : 90]);

  return (
    <>
      <div className="wrap">
        <nav className="nav">
          <div className="brand"><span className="dot" /> Aria</div>
          <div className="links">
            <a href="#what">What she does</a>
            <a href="#knows">Knowledge</a>
            <a href="#agents">Agents</a>
            <a href={GITHUB} target="_blank" rel="noreferrer">Source</a>
            <a className="btn" href={DOWNLOAD} target="_blank" rel="noreferrer">Download</a>
          </div>
        </nav>

        <header className="hero" ref={heroRef}>
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
            style={{ scale: heroScale, y: heroY }}
          >
            <Blob size={440} mood="idle" />
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

      <section className="how">
        <div className="wrap">
          <Reveal><span className="mono eyebrow">How it works</span></Reveal>
          <div className="steps">
            {steps.map(([title, body], i) => (
              <Reveal key={title} i={i} className="step">
                <span className="mono num">0{i + 1}</span>
                <h3 className="display">{title}</h3>
                <p>{body}</p>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section id="knows" className="knows">
        <div className="wrap">
          <div className="sectionBlob"><Blob size={170} mood="executing" /></div>
          <Reveal><span className="mono eyebrow">Knowledge engine</span></Reveal>
          <Reveal i={1}><h2 className="display">Aria knows your work.</h2></Reveal>
          <Reveal i={2}>
            <p className="sub">Point her at folders of notes, PDFs, documents and code. She indexes them
            on-device and answers from <em>your</em> knowledge — with the source.</p>
          </Reveal>
          <div className="demoCards">
            {demoFlows.map(([ask, steps], i) => (
              <Reveal key={ask} i={i} className="demoCard">
                <h4>{ask}</h4>
                <motion.ul
                  initial="hidden"
                  whileInView="visible"
                  viewport={{ once: true, amount: 0.6 }}
                  variants={{ visible: { transition: { staggerChildren: 0.18, delayChildren: 0.2 } } }}
                >
                  {steps.map((s) => (
                    <motion.li
                      key={s}
                      variants={{
                        hidden: { opacity: 0, x: -10 },
                        visible: { opacity: 1, x: 0, transition: { duration: 0.45, ease: "easeOut" } },
                      }}
                    >
                      <span className="tick">✓</span> {s}
                    </motion.li>
                  ))}
                </motion.ul>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="local">
        <div className="wrap splitGrid">
          <Reveal>
            <div className="sectionBlob"><Blob size={170} mood="calm" /></div>
            <h2 className="display">Your data stays<br />on your Mac.</h2>
          </Reveal>
          <Reveal i={1}>
            <p>
              Aria is local-first. Everyday work — planning, files, calendar, notes, and
              everything the knowledge engine reads — can run on a local model
              (Ollama, Qwen&nbsp;3) that never sends a byte off your machine. The wake word is
              on-device, your knowledge index is on-device, and the cloud is an
              <em> option</em>, not a requirement.
            </p>
            <p>
              When you do want cloud-grade reasoning — deep research, heavy synthesis —
              she uses your own free key and tells you which model answered and why.
              Open Settings → Transparency and there are no black boxes.
            </p>
          </Reveal>
        </div>
      </section>

      <section id="agents" className="agents">
        <div className="wrap">
          <div className="sectionBlob"><Blob size={170} mood="thinking" /></div>
          <Reveal><span className="mono eyebrow">Background agents</span></Reveal>
          <Reveal i={1}><h2 className="display">Set it once.<br />Let Aria handle it.</h2></Reveal>
          <div className="agentRow">
            {[
              ["Daily briefing", "Every morning: your calendar, your reminders, a one-page note — ready before you sit down."],
              ["Folder watch", "New files land in Downloads, Aria sorts them into place. Nothing deleted, everything logged."],
              ["Any recurring goal", "Anything you'd say to her, on a schedule — same tools, same safety gates, every run visible."],
            ].map(([title, body], i) => (
              <Reveal key={title} i={i} className="agentCard">
                <h4>{title}</h4>
                <p>{body}</p>
              </Reveal>
            ))}
          </div>
          <Reveal i={3}>
            <p className="sub">Background agents never feel hidden: every run notifies you and lands in a visible history.</p>
          </Reveal>
        </div>
      </section>

      <section className="who">
        <div className="wrap whoGrid">
          <Reveal>
            <h3 className="display">For founders</h3>
            <ul className="plainList">{founderFlows.map((f) => <li key={f}>{f}</li>)}</ul>
          </Reveal>
          <Reveal i={1}>
            <h3 className="display">For developers</h3>
            <ul className="plainList">{devFlows.map((f) => <li key={f}>{f}</li>)}</ul>
          </Reveal>
        </div>
      </section>

      <section className="split">
        <div className="wrap splitGrid">
          <Reveal>
            <h2 className="display">Free, because<br />you bring the key.</h2>
          </Reveal>
          <Reveal i={1}>
            <p>
              Aria runs on Google's Gemini free tier with your own key — and rotates across
              several keys plus free fallbacks (Groq, Cerebras, OpenRouter) so she keeps
              working when one runs out. It stays free because you bring the key, not because
              we resell you back your own data.
            </p>
            <p>
              And it's private by construction: she has no backend. The wake word runs
              on-device, keys live in your macOS Keychain, screenshots are never written to
              disk, and password fields are hidden from her. The only calls that leave your
              Mac go to the provider you chose.
            </p>
          </Reveal>
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

      <section className="faq">
        <div className="wrap">
          <Reveal><h2 className="display">Questions.</h2></Reveal>
          <div className="qaList">
            {faqs.map(([q, a], i) => (
              <Reveal key={q} i={i % 2} className="qa">
                <h4>{q}</h4>
                <p>{a}</p>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <section className="close">
        <div className="wrap">
          <Reveal>
            <div className="closeBlob"><Blob size={220} mood="confident" /></div>
            <h2 className="display">Say “Hey Aria.”</h2>
            <div className="cta">
              <a className="btn" href={DOWNLOAD} target="_blank" rel="noreferrer">Download for Mac</a>
              <a className="btn ghost" href={GITHUB} target="_blank" rel="noreferrer">It's open source</a>
            </div>
            <Waitlist />
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
