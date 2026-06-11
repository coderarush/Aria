# ARIA V11 — LAUNCH CANDIDATE

## MISSION

V10 established the foundation.

V11 is the final launch-candidate release before public launch.

The objective is not to maximize feature count.

The objective is to make Aria feel like the most capable, intelligent, premium, and useful AI operating layer available on macOS.

Aria should feel:

* Native
* Fast
* Intelligent
* Context-aware
* Personalized
* Trustworthy
* Proactive

Preserve all V10 functionality.

Do not remove existing features.

Follow:

**Preserve → Improve → Expand**

All changes must be additive.

---

# NORTH STAR

Aria should become:

> The fastest way to get work done on a Mac.

Users should feel:

* Aria understands my work
* Aria remembers my projects
* Aria can take action
* Aria can automate tasks
* Aria saves me time every day
* Aria feels like part of macOS

Compete through:

* Execution quality
* Context awareness
* Memory
* Workflows
* Speed
* Reliability

Not feature count.

---

# EXISTING FUNCTIONALITY PROTECTION

Before modifying any system:

1. Audit current implementation
2. Determine user value
3. Preserve functionality
4. Improve where possible
5. Document any removal

Never remove functionality solely because a newer implementation exists.

All major changes require regression validation.

The goal is to evolve Aria, not rebuild it.

---

# PRIORITY 1 — LOCAL-FIRST ARCHITECTURE

Aria should be local-first.

On first launch:

1. Detect Apple Silicon generation
2. Detect RAM
3. Detect storage
4. Recommend optimal local model
5. Download and configure automatically

Suggested defaults:

### 8GB RAM

* Qwen 3 4B MLX

### 16GB RAM

* Qwen 3 8B MLX

### 24GB+ RAM

* Qwen 3 14B MLX

Requirements:

* One-click onboarding
* Automatic optimization
* Model health monitoring
* Graceful failure handling
* Zero manual setup

Architecture:

Local Model
↓
Local Tools
↓
Local Execution
↓
Optional Cloud Escalation

Cloud models should only activate when:

* User explicitly enables them
* Task exceeds local capabilities

Default philosophy:

**Local First → Cloud Second**

---

# PRIORITY 2 — PREMIUM MACOS EXPERIENCE

Upgrade the overall experience.

Implement and refine:

* Spotlight-quality command palette
* Native-feeling overlays
* Native notifications
* Dynamic blur
* Fluid motion
* Refined orb animations
* Improved menu bar interactions
* Instant visual feedback
* Delightful micro-interactions

Reference quality:

* Apple Intelligence
* Raycast
* Arc Browser
* Linear

The experience should feel calm, premium, and intentional.

---

# PRIORITY 3 — WORKFLOW PLANNING ENGINE

Every meaningful task should follow:

Understand
↓
Plan
↓
Execute
↓
Verify
↓
Report

Example:

User:

> Prepare me for tomorrow.

Aria:

* Check calendar
* Find meeting notes
* Gather documents
* Generate briefing

Then execute.

Execution should feel intelligent.

---

# PRIORITY 4 — DAILY BRIEFING V2

Create a signature workflow.

Inputs:

* Calendar
* Reminders
* Notes
* Work Journal
* Timeline
* Recent activity

Outputs:

* Priorities
* Meetings
* Deadlines
* Action items
* Suggested focus areas

Support:

* On-demand briefing
* Scheduled briefing
* Spoken briefing

Command:

> Brief me.

This should become a flagship Aria feature.

---

# PRIORITY 5 — PROJECT MEMORY 2.0

Expand WorkJournal.

Track:

* Projects
* Sessions
* Tasks
* Documents
* Conversations
* Workflow outcomes

Examples:

> What were we working on yesterday?

> Continue my Verdai work.

> What changed this week?

Memory should reduce user effort.

---

# PRIORITY 6 — ARIA TIMELINE

Create a timeline system.

Track:

* Work sessions
* Tasks completed
* Projects touched
* Files modified
* Agent activity
* Daily accomplishments

Commands:

> What did I do today?

> Show my week.

> What have I accomplished recently?

Timeline should integrate with WorkJournal.

Timeline should become one of Aria's defining features.

---

# PRIORITY 7 — WATCHERS & AUTOMATIONS

Implement persistent automation.

Examples:

Watch Downloads

* Summarize PDFs

Watch Inbox

* Notify on investor emails

Watch Website

* Detect changes

Watch Project Folder

* Generate updates

Requirements:

* Lightweight
* Reliable
* Configurable
* Easy to disable

Aria should become proactive.

---

# PRIORITY 8 — COMMAND RECIPES

Create reusable workflows.

Examples:

Morning Startup

* Open Calendar
* Open Mail
* Open Notes
* Generate Briefing

Developer Startup

* Open VS Code
* Open Terminal
* Open Project
* Summarize status

Users should:

* Create recipes
* Edit recipes
* Save recipes
* Execute recipes

Recipes should be reusable.

---

# PRIORITY 9 — BROWSER RESEARCH AGENT

Research should become a first-class workflow.

Example:

> Research OpenAI competitors.

Aria should:

1. Search
2. Open sources
3. Gather information
4. Compare findings
5. Generate report
6. Save notes

Support:

* Multi-tab workflows
* Source tracking
* Citation collection
* Research summaries

Focus on reliability.

---

# PRIORITY 10 — VISION MODE

Allow Aria to understand visual context.

Examples:

> Explain this.

> Summarize this chart.

> Analyze this dashboard.

> Read this PDF.

Requirements:

* Screen awareness
* Window awareness
* Context awareness
* Workflow integration

Vision should enhance execution.

---

# PRIORITY 11 — CONTEXT AWARENESS 2.0

Expand context sources.

Potential inputs:

* Active app
* Active window
* Open tabs
* Selected text
* Recent activity
* Current project

Examples:

> Summarize this.

> Continue this.

> Finish what I was doing.

Reduce unnecessary user explanation.

---

# PRIORITY 12 — FOCUS MODE

Implement Focus Mode.

Example:

> Enter Focus Mode.

Aria should:

* Open required apps
* Close distractions
* Configure workspace
* Start session
* Track accomplishments
* Generate recap

Modes:

* Student
* Founder
* Developer
* Custom

Focus Mode should feel intentional.

---

# PRIORITY 13 — SMART SUGGESTIONS

Allow Aria to proactively help.

Examples:

Meeting soon:

> Would you like a briefing?

New PDF downloaded:

> Would you like a summary?

Long work session:

> Would you like a recap?

Requirements:

* Helpful
* Configurable
* Non-intrusive
* Respect quiet hours

Avoid annoyance.

---

# PRIORITY 14 — VOICE SYSTEM

Current direction:

* Gemini voice supported
* Gemini voice default if cost remains negligible
* User-selectable providers

Requirements:

* Streaming speech
* Fast response
* Interruptible speech
* Natural conversations

Future support:

* Gemini voices
* Local voice providers
* Premium voices

Voice should feel human.

---

# PRIORITY 15 — VOICE CONVERSATIONS

Expand beyond command execution.

Support:

* Multi-turn conversations
* Follow-up questions
* Clarifications
* Planning discussions

Examples:

> Help me plan my week.

> Help me prepare for this meeting.

Voice should feel natural.

---

# PRIORITY 16 — MULTI-AGENT VISIBILITY

Expose agent execution.

Show:

* Active agents
* Progress
* Current step
* Completed steps
* Errors
* Recovery attempts

Users should understand what Aria is doing.

Avoid black-box behavior.

---

# PRIORITY 17 — WORKFLOW PACK ARCHITECTURE

Create reusable workflow packs.

Examples:

Founder Pack

* Briefings
* Meeting prep
* Research

Student Pack

* Assignments
* Study planning
* Exam prep

Developer Pack

* Project resume
* Code review
* Research

Marketplace UI is not required.

Architecture is required.

---

# PRIORITY 18 — SETTINGS V2

Redesign settings.

Requirements:

* Apple-quality design
* Rich previews
* Searchable settings
* Interactive customization
* Smooth transitions

Settings should feel premium.

---

# PRIORITY 19 — UI V2

Refine entire product experience.

Add:

* Dynamic blur
* Glass materials
* Layered depth
* Fluid motion system
* Orb interaction upgrades
* Motion consistency

Premium over flashy.

---

# PRIORITY 20 — DEMO MODE

Create:

ARIA_DEMO_MODE

Provide:

* Founder Demo
* Student Demo
* Developer Demo

Requirements:

* Repeatable
* Deterministic
* Fast
* Reliable

Demo Mode should never fail.

---

# PRIORITY 21 — REMOTION LAUNCH FILM

Create a launch-film generation system.

Output:

60–90 second launch film.

Include:

* Motion graphics
* Animated typography
* Cinematic transitions
* Dynamic blob animation
* Floating UI
* Product reveals
* Smooth camera movement

Narrative:

Problem
↓
Aria Appears
↓
Daily Briefing
↓
Project Memory
↓
Timeline
↓
Browser Research
↓
Vision Mode
↓
Focus Mode
↓
Agentic Workflows
↓
Closing Brand Moment

Visual inspiration:

* Apple WWDC
* Arc Browser
* Linear
* High-end SaaS launch films

Sell outcomes, not features.

---

# RELIABILITY REQUIREMENTS

Before every merge:

Run:

* Regression tests
* Workflow tests
* Voice tests
* Context tests
* Memory tests
* Automation tests
* Vision tests
* UI tests

Assume bugs exist.

Prove they do not.

---

# PERFORMANCE REQUIREMENTS

Optimize:

* Startup speed
* Agent execution
* Context retrieval
* Memory access
* Animation smoothness
* CPU usage
* RAM usage

Users should consistently feel:

> Aria is faster than doing it myself.

---

# FINAL PRODUCT VISION

Aria is not a chatbot.

Aria is not an LLM wrapper.

Aria is not a Siri clone.

Aria is the execution layer for macOS.

The long-term goal:

User:
"I need to get something done."

Immediate thought:
"I'll ask Aria."

Every decision should move Aria closer to that future.


---

# V11 STATUS (2026-06-11)

All 21 priorities + the first-run experience implemented on branch aria-v11,
in three phases (Preserve → Improve → Expand; zero feature removals):

- v11-1 (e9d9e63): daily habit loop — project memory 2.0, timeline,
  briefing v2, downloads/session proactive signals
- v11-2 (28b6754): differentiation — local-first setup (hardware detect →
  recommend → install → health), mail/url watchers, recipes + persona packs,
  vision deixis, focus mode
- v11-3: FRE onboarding (permissions → model → persona → pack → first
  briefing), settings search, recovery narration, persona demo scripts

Already complete before V11 (extended, not rebuilt): workflow planning engine
(P3), premium surface (P2, V10-B), voice system + conversations (P14/P15 —
frozen by design), multi-agent visibility (P16 core), demo mode (P20 infra),
launch film (P21 — extend with new-feature beats before launch).

Gate results: 428 tests green (359 at V10), make smoke 10/10, verify-release OK.

Remaining for public launch (user decisions): notarization, tester week,
waitlist/domain, film v3 with Timeline/Vision/Focus beats.
