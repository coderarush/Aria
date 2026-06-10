# ARIA V9 PRE-RELEASE

## MASTER PRODUCT + ENGINEERING CONSTITUTION

### Vision

Build the execution layer for macOS.

Aria is not a chatbot.

Aria is not a Siri clone.

Aria is not an LLM wrapper.

Aria is an execution-first intelligence layer that transforms user intent into completed work.

The user should think:

"I'll ask Aria."

instead of:

"I'll open an application and do it myself."

The true competitor is friction.

Every engineering decision should reduce friction between intent and execution.

---

## Product Identity

Traditional assistants answer questions.

Aria completes work.

Traditional Flow:

User → Assistant → Answer

Aria Flow:

User → Objective → Understand → Plan → Execute → Verify → Report Completion

Whenever possible:

* Execute instead of explain
* Automate instead of instruct
* Complete instead of suggest

Applications should become implementation details.

Users should think in outcomes.

---

## Core Principle

The model is not the product.

The execution engine is the product.

The workflow engine is the product.

The context engine is the product.

The memory engine is the product.

The reliability of execution is the product.

Models are replaceable components.

---

## Product Preservation

Aria already contains valuable functionality.

Preserve:

* Blob interface
* Wake phrase system
* Voice interactions
* Overlay UI
* Existing workflows
* Existing execution systems
* Existing context systems
* Existing memory systems
* Existing approval systems
* Existing branding

Default philosophy:

Preserve → Improve → Expand

Never remove working functionality without explicit justification.

---

## Local-First Strategy

Primary goals:

* Privacy
* Speed
* Reliability
* Offline capability
* Low operating cost
* Independence from providers

Cloud intelligence should enhance Aria.

Cloud intelligence should never be required for Aria to function.

---

## Local Model Strategy

Target Hardware:

* Apple Silicon
* M4
* 16 GB Unified Memory

Primary Runtime Targets:

* MLX
* Ollama
* LM Studio

### Preferred Local Model

Primary:

Qwen 3 8B

Secondary:

Llama 3.1 8B
Gemma 12B

Reasoning:

Aria is an execution-first agent platform.

Prioritize:

* Tool use
* Workflow planning
* Structured outputs
* Agent orchestration
* Reliability

Benchmark scores are secondary.

Execution quality is primary.

Qwen is the default local target unless future testing proves otherwise.

---

## Provider Architecture

Implement provider abstraction.

Examples:

* LocalProvider
* GeminiProvider
* ClaudeProvider
* GrokProvider
* OpenAIProvider

The rest of Aria must remain provider-agnostic.

Providers should be replaceable.

---

## Routing Philosophy

Target Architecture:

90% Local
10% Cloud

### Local Tasks

* File management
* Browser automation
* Productivity actions
* Context retrieval
* Memory retrieval
* Knowledge retrieval
* Workflow execution
* Document understanding

### Cloud Tasks

* Deep research
* Complex reasoning
* Competitive analysis
* Large codebase analysis
* Multi-source synthesis

Cloud is optional.

Local is default.

---

## Context Engine

Maintain awareness of:

* Active app
* Active window
* Browser tabs
* Clipboard
* Selected files
* Open documents
* Calendar state
* Email state
* Project state
* Historical workflow state

Context retrieval should be:

* Relevant
* Efficient
* Explainable
* Lazy-loaded

---

## Memory Engine

Maintain:

* User preferences
* Session memory
* Workflow memory
* Long-term memory
* Project memory

Memory exists to reduce user effort.

---

## Local Knowledge Engine

Strategic Priority.

Index:

* PDFs
* Notes
* Documents
* Repositories
* Project folders

Requirements:

* Local-first
* Incremental indexing
* Fast retrieval
* Privacy-first

Users should be able to naturally query their own knowledge.

---

## Execution Engine

Execution is Aria's primary value.

Support:

### System Actions

* Open applications
* Close applications
* Window management
* File management
* Search machine
* Search web

### Browser Actions

* Navigate websites
* Fill forms
* Extract information
* Upload files
* Download files

### Productivity Actions

* Email drafting
* Calendar management
* Notes
* Summaries
* Reports
* Meeting preparation

Prefer execution over explanation.

---

## Agent System

Strategic Priority.

Support:

* Multi-step planning
* Workflow chaining
* Background execution
* Retry systems
* Recovery systems
* Progress tracking
* Long-running workflows

Users provide objectives.

Aria determines execution.

---

## Background Agents

Examples:

* Downloads monitoring
* Daily founder briefing
* Repository monitoring
* Recurring workflow execution

Requirements:

* User visibility
* User control
* Low resource usage
* Safe execution

Background agents must never feel hidden.

---

## Skills Architecture

Examples:

* Finder
* Browser
* Calendar
* Email
* Terminal
* System

Future:

* GitHub
* Slack
* Notion
* Linear
* Figma
* Claude Code

Skills must be modular.

---

## Interaction Layer

Support:

* Wake phrase
* Global push-to-talk
* Overlay interaction
* Voice workflows
* Text workflows

Wake phrase and push-to-talk must coexist.

---

## Transparency

Implement:

### Context Inspector

Display:

* Active context
* Active app
* Active model
* Retrieved memory
* Workflow state

### Workflow History

Display:

* Running workflows
* Completed workflows
* Failed workflows

### Model Router Dashboard

Display:

* Selected model
* Routing reason
* Task classification

Avoid black-box behavior.

---

## Safety

Before impactful actions:

Display plan.

Require approval when appropriate.

Examples:

* Sending emails
* Deleting files
* System modifications

Prioritize trust.

---

## Reliability First

If choosing between:

New Feature
or
Reliability Improvement

Choose reliability.

---

## Bug Hunting Directive

Assume bugs exist until proven otherwise.

Continuously test:

* Runtime failures
* Race conditions
* Memory leaks
* Workflow failures
* Context failures
* Permission failures
* Voice failures
* UI failures

---

## Regression Prevention

Verify:

* Existing UI
* Existing workflows
* Existing memory
* Existing context
* Existing voice systems
* Existing integrations

No feature is complete without regression validation.

---

## Failure Simulation

Test:

* API failures
* Network failures
* Permission failures
* Invalid input
* Interrupted workflows
* Corrupted responses

Aria should fail safely.

Never fail silently.

---

## North Star

Build the fastest, most private, most reliable, and most useful execution layer available on macOS.

Compete against friction.

Compete against manual work.

Help users accomplish meaningful work with the least possible effort.

