import { useRef, useState } from "react";
import {
  motion, useReducedMotion, useScroll, useSpring,
  useMotionValue, useTransform, useMotionValueEvent,
} from "framer-motion";

/* A button that subtly leans toward the cursor and lifts on hover — the small,
   physical "this is alive" detail Apple uses on primary actions. */
export function Magnetic({ children, className, href, download, onClick, strength = 0.4 }) {
  const reduce = useReducedMotion();
  const ref = useRef(null);
  const x = useSpring(0, { stiffness: 250, damping: 18 });
  const y = useSpring(0, { stiffness: 250, damping: 18 });

  const onMove = (e) => {
    if (reduce || !ref.current) return;
    const r = ref.current.getBoundingClientRect();
    x.set((e.clientX - (r.left + r.width / 2)) * strength);
    y.set((e.clientY - (r.top + r.height / 2)) * strength);
  };
  const reset = () => { x.set(0); y.set(0); };

  const Comp = href ? motion.a : motion.button;
  return (
    <Comp
      ref={ref}
      href={href}
      download={download}
      onClick={onClick}
      onMouseMove={onMove}
      onMouseLeave={reset}
      style={{ x, y }}
      whileTap={{ scale: 0.96 }}
      className={className}
    >
      {children}
    </Comp>
  );
}

/* A card that tilts in 3D toward the cursor with a soft specular sheen that
   tracks the pointer. Falls back to a flat card under reduced-motion. */
export function TiltCard({ children, className, max = 8, style, ...rest }) {
  const reduce = useReducedMotion();
  const ref = useRef(null);
  const rx = useSpring(0, { stiffness: 200, damping: 20 });
  const ry = useSpring(0, { stiffness: 200, damping: 20 });
  const [glow, setGlow] = useState({ x: "50%", y: "0%", o: 0 });

  const onMove = (e) => {
    if (reduce || !ref.current) return;
    const r = ref.current.getBoundingClientRect();
    const px = (e.clientX - r.left) / r.width;
    const py = (e.clientY - r.top) / r.height;
    ry.set((px - 0.5) * max * 2);
    rx.set((0.5 - py) * max * 2);
    setGlow({ x: `${px * 100}%`, y: `${py * 100}%`, o: 1 });
  };
  const reset = () => { rx.set(0); ry.set(0); setGlow((g) => ({ ...g, o: 0 })); };

  return (
    <motion.div
      ref={ref}
      onMouseMove={onMove}
      onMouseLeave={reset}
      style={{ rotateX: rx, rotateY: ry, transformPerspective: 900, transformStyle: "preserve-3d", ...style }}
      className={className}
      {...rest}
    >
      {children}
      <div className="tiltGlow" style={{
        background: `radial-gradient(220px circle at ${glow.x} ${glow.y}, rgba(255,255,255,0.18), transparent 60%)`,
        opacity: glow.o,
      }} />
    </motion.div>
  );
}

/* Thin reading-progress bar pinned to the top of the page. */
export function ScrollProgress() {
  const { scrollYProgress } = useScroll();
  const scaleX = useSpring(scrollYProgress, { stiffness: 120, damping: 30, mass: 0.3 });
  return <motion.div className="scrollProgress" style={{ scaleX }} aria-hidden="true" />;
}

/* A slowly drifting aurora mesh — three blurred color blobs that breathe behind
   the dark sections. Pure decoration; disabled under reduced motion. */
export function Aurora({ className }) {
  const reduce = useReducedMotion();
  if (reduce) return <div className={`aurora ${className || ""}`} aria-hidden="true" />;
  return (
    <div className={`aurora ${className || ""}`} aria-hidden="true">
      {[0, 1, 2].map((i) => (
        <motion.span
          key={i}
          className={`auroraBlob ab${i}`}
          animate={{
            x: [0, 40 - i * 22, -20 + i * 14, 0],
            y: [0, -30 + i * 18, 24 - i * 10, 0],
            scale: [1, 1.18, 0.92, 1],
          }}
          transition={{ duration: 16 + i * 5, repeat: Infinity, ease: "easeInOut" }}
        />
      ))}
    </div>
  );
}

/* Headline that reveals word-by-word as it enters — Apple's signature staggered
   type. Pass a string; `\n` becomes a line break. */
export function WordReveal({ text, className }) {
  const reduce = useReducedMotion();
  const lines = text.split("\n");
  return (
    <h1 className={className}>
      {lines.map((line, li) => (
        <span key={li} style={{ display: "block", overflow: "hidden" }}>
          {line.split(" ").map((word, wi) => (
            <motion.span
              key={wi}
              style={{ display: "inline-block", willChange: "transform" }}
              initial={{ y: reduce ? 0 : "0.9em", opacity: reduce ? 1 : 0 }}
              animate={{ y: 0, opacity: 1 }}
              transition={{ duration: 0.8, delay: 0.3 + (li * 4 + wi) * 0.06, ease: [0.22, 1, 0.36, 1] }}
            >
              {word}&nbsp;
            </motion.span>
          ))}
        </span>
      ))}
    </h1>
  );
}

export { useScroll, useTransform, useSpring, useMotionValue, useMotionValueEvent };
