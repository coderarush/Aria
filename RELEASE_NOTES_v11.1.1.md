# Aria v11.1.1 — "The Operator"

Aria stops being a thing you summon and becomes a presence that **operates your computer with you** — acting highly autonomously, but safely: everything she does is logged and reversible.

## Highlights

- **Trust layer.** Every action produces a **receipt** (what, when, how consequential), shown in a new **Receipts pane** with **one-click undo** on anything reversible. Each step **verifies its effect** before counting as done.
- **High autonomy.** She acts without asking — permission is requested **only** for the extremely important and irreversible (money, deletes with no undo, external comms, raw shell). Everything reversible just happens, receipted.
- **Connectors that act.** Gmail (send/draft), Google Calendar (create), Notion (search/append), Slack (read/send), Google Drive (search/read/create) — read **and** write, through your connected accounts. New writes (drafts, events) are undoable from Receipts.
- **Personalization — a model of you.** On-device entity graph (so "Sara" or "the launch deck" resolve) + a writing-style profile learned from your sent mail so her drafts sound like you. Opt-in, local-only.
- **Anticipation that acts.** Very-high-confidence reversible routines run on their own (receipted + undoable + notified) instead of only suggesting. Opt-in.
- **Computer-use targeting.** Confidence-gated clicks (she asks instead of clicking a low-confidence guess), element re-resolution on retry, dry-run preview.
- **Hosted OAuth relay (client-side).** A sign-in mode that needs no per-service client ID once the relay server is deployed — one setting to switch.

## Engineering

- 779 tests, release build verified (`-Onone`). Branch merged from `aria-v11.1.1`.

## Setup notes

- Connectors need their OAuth apps registered and the accounts connected; **re-consent Google** for the new send/draft/calendar/drive scopes.
- The hosted OAuth relay server is not yet deployed (design in `docs/v11.1/OAUTH_RELAY_DESIGN.md`); default sign-in mode is bring-your-own-client-ID until it is.
- Live end-to-end validation (voice, dictation, the acting loop, connectors) is pending real-device + real-account testing.

Requirements: macOS 14+.
