---
name: technical-docs
description: Use when writing or reviewing technical documentation - tutorials, how-to guides, reference docs, or explanatory content. Applies the Divio documentation system to produce documentation that is clearly scoped, correctly typed, and useful to its audience.
---

# Technical Documentation Expert Skill

Guidance for writing effective technical documentation based on the Divio Documentation System. The core insight: there is no single thing called "documentation" — there are four fundamentally different types, each with a distinct purpose, audience state, and writing approach. Mixing them is the most common source of documentation that feels incomplete, confusing, or unhelpful.

## When to Use This Skill

**Activate this skill when:**
- Writing a tutorial, quickstart, or getting-started guide
- Writing a how-to guide or recipe for a specific task
- Writing API reference, CLI reference, or configuration reference
- Writing conceptual explanations, background context, or architectural rationale
- Reviewing existing docs that feel unclear or hard to navigate
- Deciding where a new piece of documentation belongs

---

## The Four Types at a Glance

| | Tutorials | How-To Guides | Reference | Explanation |
|---|---|---|---|---|
| **Orientation** | Learning | Task | Information | Understanding |
| **Answers** | "Can you teach me?" | "How do I...?" | "What is...?" | "Why does...?" |
| **Reader state** | Studying, learning | Working, needs result | Working, needs lookup | Studying, reflecting |
| **Analogy** | Cooking lesson | Recipe | Encyclopedia entry | Essay / background reading |
| **Tone** | Encouraging, hand-holding | Focused, direct | Neutral, precise | Discursive, exploratory |

The most important rule: **keep these types strictly separate.** A document that tries to be both a tutorial and a reference, or both a how-to and an explanation, will fail at both.

---

## Tutorials

### Purpose

Tutorials transform a complete beginner into a user. Their job is not to document the product — it is to build the reader's confidence and capability through a guided, hands-on experience that works.

> "The most important thing is that what you ask the beginner to do must work."

### Characteristics

- **Learning by doing** — The reader performs actions. They do not read about actions.
- **Concrete outcomes** — Every step produces a visible, comprehensible result, however small.
- **No decisions required** — Remove all optional paths. The learner follows one track.
- **No prior knowledge assumed** — Write for someone who has never touched the product.
- **Reliability above all** — Test on multiple platforms and experience levels. A broken tutorial loses users permanently.

### Structure

```
1. Brief orientation — What will the reader have built/done by the end?
2. Prerequisites — Minimal. Only what is strictly required.
3. Step 1: [Simplest possible first action with immediate feedback]
4. Step 2: [Slightly more complex, builds on step 1]
   ...
N. Conclusion — What the reader now has; what to explore next.
```

### Do

- Start with the smallest possible action that produces a visible result
- Keep each step self-contained and verifiable
- Use a friendly, encouraging tone
- Accept that beginners will do things sub-optimally — that is fine
- Test the entire tutorial end-to-end before publishing, and after every product change

### Don't

- Introduce optional features, alternative approaches, or advanced variations
- Explain concepts unless strictly required to complete the step
- Assume any prior knowledge about the product
- Treat the tutorial as a best-practices guide
- Let the tutorial grow into a reference or how-to guide

### Diagnostic Questions

- Can a brand-new user complete this without leaving the page?
- Does every step produce a visible result?
- Are there any decision points where the user could get lost?
- Have you tested it recently on a clean environment?

---

## How-To Guides

### Purpose

How-to guides help an already-capable user accomplish a specific real-world goal. The reader knows what they want to achieve — they need the steps to do it.

> "How-to guides are recipes. They answer the question: how do I...?"

### Characteristics

- **Goal-oriented** — One guide, one goal. Everything else is a distraction.
- **Action-forward** — Steps first. Explanation, if needed at all, comes after or is linked.
- **Assumes baseline competence** — The reader understands the fundamentals. You don't need to re-explain the product.
- **Allows for variation** — Unlike tutorials, a how-to can acknowledge that there are several valid ways to reach the goal.
- **Scoped, not exhaustive** — Practical usability beats completeness.

### Structure

```
# How to [accomplish specific goal]

Brief statement of what this guide achieves and any important prerequisites.

## Steps

1. [Action]
2. [Action]
3. [Action]

## Result

What the reader now has.

## Next steps / Related guides (optional)
```

### Naming Convention

Titles must be goal-oriented. "How to" should naturally precede the title:

| Bad | Good |
|---|---|
| "Authentication" | "How to authenticate with the API" |
| "Deployment" | "How to deploy to production with zero downtime" |
| "Docker" | "How to run the app in a Docker container" |
| "Webhooks" | "How to set up a webhook for order events" |

### Do

- Name the guide with a clear action ("How to configure X", "How to migrate from Y to Z")
- Start from where the user is — not from scratch
- Keep each step as a single, unambiguous action
- Link to reference or explanation docs for deeper detail — don't inline them
- Omit anything that doesn't directly serve the goal

### Don't

- Explain concepts (link to explanation docs instead)
- Reproduce the tutorial — assume they've already learned the basics
- Turn one guide into a guide for multiple different goals
- Add caveats and edge cases that distract from the main path (put those in reference)

### Diagnostic Questions

- Does the title answer "How do I...?" naturally?
- Is there exactly one goal?
- Can a user with baseline knowledge follow this without context they don't have?
- Does every step directly contribute to the goal?

---

## Reference

### Purpose

Reference documentation describes the machinery — what it is, what it does, what values it accepts, what it returns. It is consulted during work by users who already know what they're looking for.

> "Reference material is like an encyclopedia: you consult it, you don't read it."

### Characteristics

- **Information-oriented** — Describes, does not instruct
- **Structured to mirror the code** — APIs, CLI commands, config keys: the documentation structure matches the product structure so users can navigate both simultaneously
- **Accurate and current** — A discrepancy between docs and code is worse than no docs
- **Consistent** — Every entry follows the same format (encyclopedia convention)
- **Terse** — No friendliness needed; speed of lookup is the priority

### Structure

For API / function reference:

```
## function_name(param1, param2, ...)

Brief one-line description.

**Parameters**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| param1 | string | Yes | — | What it does |
| param2 | int | No | 10 | What it does |

**Returns**

Description of the return value and type.

**Raises / Errors**

Conditions under which errors are thrown and what they mean.

**Example**

\`\`\`python
result = function_name("value", param2=5)
\`\`\`

**Notes / Warnings**

Any non-obvious behaviors, constraints, or deprecation notices.
```

For CLI reference:

```
## command subcommand [options]

Brief description.

**Options**

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| --flag | string | — | What it does |

**Examples**

\`\`\`bash
command subcommand --flag value
\`\`\`
```

For configuration reference:

```
## config.key

| Type | Default | Required |
|------|---------|----------|
| string | "default" | No |

Description of what this setting controls.

Valid values: `"option-a"`, `"option-b"`.

**Example**

\`\`\`yaml
config:
  key: "option-a"
\`\`\`
```

### Do

- Mirror the structure of the codebase or product
- Include every parameter, return value, error, and side effect
- Add a minimal working example for each entry
- Call out warnings, deprecations, and non-obvious behaviors explicitly
- Keep entries consistent in format — use a template

### Don't

- Explain background concepts (link to explanation docs)
- Include task-oriented walkthroughs (that's a how-to)
- Express opinions or recommend one approach over another
- Let the docs drift out of sync with the code — automate generation where possible

### Diagnostic Questions

- Does every public API/config/command have an entry?
- Is the structure of the docs parallel to the structure of the code?
- Is every entry in the same format?
- Is this accurate against the current version?

---

## Explanation

### Purpose

Explanation docs give users the conceptual background to understand *why* the product works the way it does. They are not consulted during work — they are read during study, away from the keyboard.

> "Explanation is like background reading. It widens understanding. The reader has time to think."

### Characteristics

- **Understanding-oriented** — Builds mental models, not skills
- **Discursive in nature** — Explores a topic from multiple angles; may meander
- **Context-rich** — Covers history, trade-offs, design decisions, alternatives
- **Non-prescriptive** — Can present competing approaches without picking one
- **Not task-shaped** — Never organized around "what the user needs to accomplish"

### Topics That Belong Here

- Why the product was designed the way it was ("Design decisions in the auth system")
- Background context for understanding a domain ("How HTTP caching works")
- Trade-offs between approaches ("SQL vs. NoSQL for this use case")
- Explanation of a non-obvious behavior or constraint
- The "big picture" view of an architecture or system

### Structure (flexible — this type resists rigid templates)

```
# [Topic] / Background on [X] / Understanding [Y]

Opening that situates the reader — what question this answers.

## [First angle or sub-topic]
...

## [Trade-offs / alternatives / history]
...

## [Implications or summary of the mental model]
...

## Further reading (optional links to reference or how-to docs)
```

### Naming

Titles that work: "Background", "Key concepts", "Understanding X", "Why Y works this way", "Discussions", "Architecture overview"

### Do

- Write at a leisurely pace — the reader is not in a hurry
- Present multiple perspectives and acknowledge trade-offs
- Explain the reasoning behind design decisions
- Use analogies and higher-level abstractions
- Link to reference and how-to docs for the practical counterpart

### Don't

- Instruct (that's a tutorial or how-to)
- List specifications (that's reference)
- Organize the content around tasks the user needs to complete
- Assume the reader is at a keyboard

### Diagnostic Questions

- Would a reader need this while actively coding? If yes, it might be reference or how-to.
- Does it explain *why*, not just *what* or *how*?
- Is it free of step-by-step instructions?

---

## Diagnosing Existing Documentation

Use this to identify where documentation is failing:

| Symptom | Likely Problem |
|---|---|
| Users can't get started | Tutorial is missing, broken, or too abstract |
| Users keep asking "how do I...?" | How-to guides are missing or buried in reference |
| Users don't trust the docs | Reference is out of date or incomplete |
| Users use the product but don't understand it | Explanation docs are missing |
| Docs feel bloated and hard to navigate | Types are mixed — a reference page is also trying to be a tutorial |
| Users skim and miss critical details | Reference is written in tutorial prose style |
| Tutorial feels overwhelming | It's actually a how-to guide masquerading as a tutorial |

---

## Applying the System to a Project

### Starting a new documentation set

1. Create four top-level sections: `Getting Started` (tutorials), `How-To Guides`, `Reference`, `Concepts` (explanation)
2. Put every piece of existing content into exactly one section — resist the urge to put things in two places
3. Write the tutorial first — it is the highest-leverage investment and defines your product's "on-ramp"
4. Fill in reference next — it has the highest maintenance burden and should be automated where possible
5. Add how-to guides as users repeatedly ask "how do I...?" questions
6. Add explanation docs when users understand the mechanics but not the reasoning

### Growing an existing documentation set

- When you add a feature: add a reference entry (required), a how-to if the feature involves non-trivial steps, and an explanation if the design is non-obvious
- When you get a support question: ask "what type of doc would have answered this?" and create it
- When docs feel wrong: diagnose by type — is the problem that it's the wrong type for its section, or the wrong content for its type?

### Maintenance

| Type | Maintenance trigger |
|---|---|
| Tutorial | Every product change that affects the flow; test on every release |
| How-to | When the steps change; when a new common question emerges |
| Reference | On every API/config/CLI change — automate where possible |
| Explanation | Rarely; only when the design rationale or context changes |
