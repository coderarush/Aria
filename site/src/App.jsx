import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import Blob from "./Blob.jsx";
import { Aurora, ScrollProgress, TiltCard, WordReveal } from "./Motion.jsx";

const GITHUB = "https://github.com/coderarush/Aria";
const DOWNLOAD = `${GITHUB}/releases/latest/download/Aria.dmg`;
const CONTACT = "arushp@icloud.com";

const heroBeats = [
  ["Listening", "Hey Aria, prep me for tomorrow.", "Voice wakes the blob."],
  ["Seeing", "Circle the broken chart.", "Screen context snaps into focus."],
  ["Planning", "Draft, verify, then ask before sending.", "Agent plan builds safely."],
  ["Acting", "Gmail draft ready. Calendar checked.", "Receipts and undo stay attached."],
];

const planRows = [
  ["Capture", "Read the focused app, selected region, clipboard, and active project memory.", "done"],
  ["Plan", "Break the goal into reversible steps with explicit gates for sends/deletes/scripts.", "active"],
  ["Operate", "Use apps, files, browser, mail, calendar, notes, and connectors without losing context.", "pending"],
  ["Verify", "Check postconditions, log the receipt, and leave undo where the action allows it.", "pending"],
];

const bento = [
  {
    title: "Circle-to-ask",
    label: "Vision",
    body: "Draw around an error, chart, image, or paragraph. Aria reads that exact region and acts from it.",
    mood: "listening",
  },
  {
    title: "Memory from everywhere",
    label: "Recall",
    body: "Project notes, past work, imported ChatGPT exports, and decisions become durable context.",
    mood: "thinking",
  },
  {
    title: "Background agents",
    label: "Autonomy",
    body: "Watch an inbox, page, folder, or calendar. Quiet until something changes; fail closed on risky work.",
    mood: "executing",
  },
  {
    title: "Operator receipts",
    label: "Trust",
    body: "Important actions leave a readable trail. Reversible actions keep undo attached to the result.",
    mood: "calm",
  },
  {
    title: "Local-first routing",
    label: "Privacy",
    body: "Prefer local models and your own keys. No Aria backend is required for normal use.",
    mood: "confident",
  },
  {
    title: "Workflow packs",
    label: "Speed",
    body: "Founder, student, and developer routines install reusable recipes and proactive daily agents.",
    mood: "idle",
  },
];

const comparison = [
  ["Siri AI", "Personal context, broad questions, app actions", "Aria adds Mac operation, receipts, undo, local-first routing, background agents."],
  ["Hey Clicky", "Computer control", "Aria adds memory, workflows, connector tools, action policy, and deep macOS-native surfaces."],
  ["Raycast AI", "Fast command surface", "Aria adds a voice-first living interface, screen vision, and autonomous multi-step execution."],
];

const install = [
  "Download the DMG",
  "Grant Microphone, Speech, Screen Recording, and Accessibility",
  "Choose local Ollama or bring your own model key",
  "Say “Hey Aria” or press ⌥Space",
];

function useBeat() {
  const [beat, setBeat] = useState(0);
  useEffect(() => {
    const id = window.setInterval(() => setBeat((v) => (v + 1) % heroBeats.length), 2400);
    return () => window.clearInterval(id);
  }, []);
  return beat;
}

function LiquidButton({ href, children, variant = "dark", ...props }) {
  return (
    <a className={`liquidButton ${variant}`} href={href} {...props}>
      <span>{children}</span>
      <i aria-hidden="true" />
    </a>
  );
}

function BlobField({ activeBeat }) {
  return (
    <div className="blobField" aria-hidden="true">
      <motion.div
        className="heroBlob heroBlobMain"
        animate={{
          transform: [
            "translate3d(-50%, -50%, 0) scale(0.98)",
            "translate3d(-50%, -51.5%, 0) scale(1.03)",
            "translate3d(-50%, -50%, 0) scale(0.98)",
          ],
        }}
        transition={{ duration: 7, repeat: Infinity, ease: "easeInOut" }}
      >
        <Blob size={520} mood={heroBeats[activeBeat][0].toLowerCase()} />
      </motion.div>
      <motion.div
        className="heroBlob satellite s1"
        animate={{ transform: ["translate3d(0,0,0)", "translate3d(12px,-18px,0)", "translate3d(0,0,0)"] }}
        transition={{ duration: 9, repeat: Infinity, ease: "easeInOut" }}
      >
        <Blob size={164} mood="calm" />
      </motion.div>
      <motion.div
        className="heroBlob satellite s2"
        animate={{ transform: ["translate3d(0,0,0)", "translate3d(-18px,16px,0)", "translate3d(0,0,0)"] }}
        transition={{ duration: 10.5, repeat: Infinity, ease: "easeInOut" }}
      >
        <Blob size={118} mood="thinking" />
      </motion.div>
      <div className="blobHalo" />
      <div className="orbitalRail r1" />
      <div className="orbitalRail r2" />
    </div>
  );
}

function AgentPlan() {
  return (
    <TiltCard className="agentPlan glassPanel">
      <div className="planTop">
        <span>Agent plan</span>
        <strong>in-progress</strong>
      </div>
      <div className="planRows">
        {planRows.map(([title, body, state]) => (
          <div className={`planRow ${state}`} key={title}>
            <i />
            <div>
              <strong>{title}</strong>
              <p>{body}</p>
            </div>
          </div>
        ))}
      </div>
    </TiltCard>
  );
}

function Hero() {
  const beat = useBeat();
  return (
    <header className="hero" id="top">
      <Aurora />
      <nav className="nav">
        <a className="brand" href="#top">
          <span className="brandBlob"><Blob size={34} mood="idle" /></span>
          <span>Aria</span>
        </a>
        <div className="navLinks">
          <a href="#why">Why</a>
          <a href="#features">Features</a>
          <a href="#film">Launch film</a>
          <a href="#download">Download</a>
        </div>
      </nav>

      <section className="heroGrid">
        <div className="heroCopy">
          <motion.p
            className="eyebrow"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
          >
            Native macOS voice operator
          </motion.p>
          <WordReveal className="heroTitle" text={"Your Mac,\nwith a living assistant."} />
          <motion.p
            className="heroSub"
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.55, ease: [0.23, 1, 0.32, 1] }}
          >
            Aria is not a search box. She is a morphing, voice-first operator that
            hears you, sees the relevant part of your screen, plans the work,
            operates your apps, verifies the result, and remembers the context.
          </motion.p>
          <motion.div
            className="heroActions"
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.75, ease: [0.23, 1, 0.32, 1] }}
          >
            <LiquidButton href={DOWNLOAD}>Download for Mac</LiquidButton>
            <LiquidButton href="#film" variant="clear">Watch launch film</LiquidButton>
          </motion.div>
          <motion.div
            className="proofPills"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.7, delay: 1 }}
          >
            <span>1,536 tests green</span>
            <span>Local-first</span>
            <span>No Aria backend required</span>
          </motion.div>
        </div>

        <div className="heroStage">
          <BlobField activeBeat={beat} />
          <motion.div
            className="voiceCard glassPanel"
            key={beat}
            initial={{ opacity: 0, y: 22, scale: 0.97, filter: "blur(4px)" }}
            animate={{ opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }}
            transition={{ duration: 0.5, ease: [0.23, 1, 0.32, 1] }}
          >
            <span>{heroBeats[beat][0]}</span>
            <strong>{heroBeats[beat][1]}</strong>
            <p>{heroBeats[beat][2]}</p>
          </motion.div>
        </div>
      </section>
    </header>
  );
}

function Why() {
  return (
    <section className="section why" id="why">
      <div className="sectionKicker">
        <span className="miniBlob" />
        Why Aria feels different
      </div>
      <div className="splitHeader">
        <h2>The blob is the interface.</h2>
        <p>
          The body language matters: listening expands, thinking ripples, executing
          radiates, calm settles. You should feel what Aria is doing before reading a status line.
        </p>
      </div>
      <div className="whyGrid">
        <div className="stickyBlob">
          <Blob size={420} mood="confident" />
          <div className="orbitTag t1">sees</div>
          <div className="orbitTag t2">plans</div>
          <div className="orbitTag t3">acts</div>
          <div className="orbitTag t4">remembers</div>
        </div>
        <AgentPlan />
      </div>
    </section>
  );
}

function Features() {
  return (
    <section className="section features" id="features">
      <div className="sectionKicker">
        <span className="miniBlob" />
        Built to complete outcomes
      </div>
      <div className="splitHeader">
        <h2>A host of capabilities, one coherent loop.</h2>
        <p>
          Every feature routes through the same execution system: context, plan,
          safety gate, action, verification, memory, receipt.
        </p>
      </div>
      <div className="bentoGrid">
        {bento.map((card, index) => (
          <TiltCard className={`bentoCard c${index}`} key={card.title}>
            <div className="cardBlob"><Blob size={96} mood={card.mood} /></div>
            <span>{card.label}</span>
            <h3>{card.title}</h3>
            <p>{card.body}</p>
          </TiltCard>
        ))}
      </div>
    </section>
  );
}

function Competition() {
  return (
    <section className="section compare">
      <div className="comparePanel">
        <div>
          <div className="sectionKicker">
            <span className="miniBlob" />
            Raise the bar
          </div>
          <h2>Designed past chatbot assistants.</h2>
        </div>
        <div className="compareRows">
          {comparison.map(([name, they, aria]) => (
            <div className="compareRow" key={name}>
              <span>{name}</span>
              <p>{they}</p>
              <strong>{aria}</strong>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function Film() {
  return (
    <section className="section film" id="film">
      <div className="filmCopy">
        <div className="sectionKicker">
          <span className="miniBlob" />
          Launch film
        </div>
        <h2>One blob. One assistant. One operating loop.</h2>
        <p>
          The launch film uses Aria as the main character: a living body moving
          through listening, seeing, planning, acting, memory, and trust.
        </p>
      </div>
      <div className="videoShell">
        <video src="/aria-launch.mp4" controls playsInline poster="" />
        <div className="videoGlow"><Blob size={220} mood="calm" /></div>
      </div>
    </section>
  );
}

function Download() {
  return (
    <section className="section download" id="download">
      <div className="downloadPanel">
        <div className="downloadBlob"><Blob size={300} mood="confident" /></div>
        <div>
          <div className="sectionKicker">
            <span className="miniBlob" />
            Try Aria
          </div>
          <h2>Set up the living Mac assistant.</h2>
          <ol>
            {install.map((item) => <li key={item}>{item}</li>)}
          </ol>
          <div className="heroActions">
            <LiquidButton href={DOWNLOAD}>Download DMG</LiquidButton>
            <LiquidButton href={`mailto:${CONTACT}`} variant="clear">Contact</LiquidButton>
            <LiquidButton href={GITHUB} variant="clear" target="_blank" rel="noreferrer">GitHub</LiquidButton>
          </div>
        </div>
      </div>
    </section>
  );
}

export default function App() {
  return (
    <>
      <ScrollProgress />
      <Hero />
      <Why />
      <Features />
      <Competition />
      <Film />
      <Download />
      <footer className="footer">
        <a className="brand" href="#top">
          <span className="brandBlob"><Blob size={30} mood="calm" /></span>
          <span>Aria</span>
        </a>
        <div>
          <a href={GITHUB} target="_blank" rel="noreferrer">GitHub</a>
          <a href={`mailto:${CONTACT}`}>Email</a>
        </div>
      </footer>
    </>
  );
}
