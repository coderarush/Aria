# Aria — landing / storefront site

A self-contained one-page site (`index.html`, no build step) to sell the app.

## Make it live (free)
**GitHub Pages:** repo Settings → Pages → Source = `main` branch, `/website` folder (or
move `index.html` to `/docs`). Your site is at `https://coderarush.github.io/Aria/`.
(Or drag `index.html` to Netlify/Cloudflare Pages for a custom domain.)

## Before launch — fill in the 3 placeholders
1. **Demo video** — replace the `.demo` block with your screen-recording (an
   `<video>` tag or a YouTube/Loom embed). This is the single most important asset:
   a 20–40s clip of Aria operating your Mac by voice.
2. **Buy link** — uncomment the line at the bottom of `index.html` and point `#buy`
   at your Gumroad / Lemon Squeezy product URL (they handle payment + license keys).
3. **Name** — "Aria" has SEO/trademark conflicts (Opera's AI, the ARIA web standard).
   Swap in your final brand name + grab the `.app`/`.ai` domain.

## Selling checklist
- [ ] Apple Developer account ($99/yr) → notarize the `.dmg` so it opens cleanly.
- [ ] Build the `.dmg` (`make release` + create a disk image).
- [ ] Gumroad / Lemon Squeezy product (upload `.dmg`, set price, get license keys).
- [ ] Record the demo clip → embed here + post to Show HN, r/macapps, Product Hunt, X.
