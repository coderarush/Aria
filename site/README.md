# Aria — marketing site

React + Vite + framer-motion. Cream editorial design (approved — preserve;
enhance with motion, never redesign). The blob is the main character: every
section's motion originates from her (`Blob.jsx` moods: idle / listening /
thinking / executing / calm / confident).

```bash
npm install
npm run dev      # localhost:5173
npm run build    # → dist/ (deploy to GitHub Pages or any static host)
```

## Waitlist

`src/App.jsx` has `WAITLIST_ENDPOINT = ""`. While empty, the form is hidden and
Download stays the only CTA. To go live:

1. Create a form endpoint (Formspree, Buttondown, or any URL accepting
   `POST {"email": "..."}` JSON).
2. Paste it into `WAITLIST_ENDPOINT`.
3. `npm run build` and redeploy.

## Launch checklist

- [ ] Waitlist endpoint set
- [ ] Demo recordings (use `ARIA_DEMO_MODE=1 make run` in the app repo for
      deterministic takes) embedded in the knowledge/agents sections
- [ ] Final product name decision (Aria has SEO/TM collisions — see memory)
- [ ] Domain + GitHub Pages (or host) wired
- [ ] OG image (real screenshot of the orb + caption)
