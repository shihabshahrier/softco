# 13 — Design (UI products only)

For any product with a user-facing surface (web app, mobile, dashboard, marketing
site), decide *how it looks and feels* before writing frontend code. Skipping
this produces generic, inconsistent UI that gets rebuilt later. This is the
lightweight design phase — runs as **Phase 1.5**, between the TDR and the
documentation package, and gates Phase 3 frontend work.

Skip entirely for headless products: APIs, CLIs (beyond help-text ergonomics),
libraries, infra-only work.

---

## Contents

- [When it runs](#when-it-runs)
- [Step 1 — Direction (pick a feel)](#step-1--direction-pick-a-feel)
- [Step 2 — Design tokens](#step-2--design-tokens)
- [Step 3 — Component inventory](#step-3--component-inventory)
- [Step 4 — Key screens](#step-4--key-screens)
- [Output — DESIGN.md](#output--designmd)
- [Gating Phase 3](#gating-phase-3)
- [Anti-slop checklist](#anti-slop-checklist)

---

## When it runs

After the TDR is approved (Phase 1), before the doc package (Phase 2). It is
fast — one or two turns — and produces a single `docs/DESIGN.md` plus token
config the frontend stack consumes directly (Tailwind theme, CSS variables,
shadcn/ui base). Get the user to pick a direction; do not silently decide taste
for them.

---

## Step 1 — Direction (pick a feel)

Offer **2–3 concrete directions**, not an open question. Each named, with a
one-line feel, a reference point, and the trade-off. Example:

```
A. "Calm utility"  — Linear/Notion feel: neutral grays, one accent, dense,
   keyboard-first. Best for power users; less friendly to first-timers.
B. "Warm consumer" — Duolingo/Cal.com feel: rounded, soft shadows, playful
   accent, generous spacing. Best for broad consumer; can feel toy-like for B2B.
C. "Sharp enterprise" — Stripe/Vercel feel: high contrast, tight type scale,
   confident. Best for credibility; unforgiving of weak content.
```

Let the user pick or blend. Lock the choice in `DESIGN.md`. This single decision
prevents the most common failure: every screen looking subtly different because
no one set the tone.

> Richer variant generation (multiple rendered mockups to compare) is a heavier
> workflow than this phase targets; the goal here is one decisive direction, fast.

## Step 2 — Design tokens

Concrete values, not adjectives. These become the Tailwind/CSS config so the
whole app is consistent by construction.

```
Color:    background, surface, border, text, text-muted, primary, primary-fg,
          success, warning, danger  (light + dark)
Type:     font family (one sans, optional mono), scale (xs→3xl), weights used
Spacing:  base unit (4px), scale
Radius:   sm/md/lg + which components use which
Shadow:   none | subtle | elevated (define the 2–3 you allow)
Motion:   default duration + easing; what animates, what does not
```

Emit these as the actual config (e.g. `tailwind.config` theme extension or
`:root` CSS variables) so Phase 3 imports them rather than re-inventing.

## Step 3 — Component inventory

List the reusable components the screens need, mapped to the chosen library
(default shadcn/ui). One source for each; never two button styles.

```
Primitives:  Button, Input, Select, Checkbox, Badge, Avatar, Tooltip
Layout:      AppShell (nav + content), Card, Table, Tabs, Dialog/Sheet
Feedback:    Toast, EmptyState, Skeleton/Loading, ErrorState
Forms:       Field (label+input+error), Form (RHF + Zod wired)
```

Mark which are off-the-shelf vs. custom. Custom components get their own module
in `MODULES.md`.

## Step 4 — Key screens

For the 3–5 screens on the critical path (from Phase 0 core workflows), sketch
layout in words or low-fi ASCII — enough to agree on structure before pixels.
Always specify the non-happy states, the part most often skipped:

- loading (skeleton, not spinner-on-blank)
- empty (first-run, no data — with a clear primary action)
- error (what the user sees and does next)
- the populated/success state

A screen spec that only describes the happy path is incomplete.

---

## Output — DESIGN.md

```markdown
# DESIGN — <project>

## Direction
<chosen name + one-line feel + reference point>

## Principles
- 3–5 rules this UI follows (e.g. "one accent color", "no modal stacking",
  "every async state has a defined loading + error view")

## Tokens
<color / type / spacing / radius / shadow / motion — concrete values>
(authoritative copy lives in tailwind.config / :root variables)

## Components
<inventory table: name | source (shadcn/custom) | notes>

## Screens
### <Screen name>
- Layout: <structure>
- States: loading / empty / error / populated
- Primary action: <what>

## Accessibility baseline
- Contrast ≥ WCAG AA, visible focus rings, keyboard reachable, labelled inputs,
  respects prefers-reduced-motion
```

Update it when the design evolves; it is the taste source of truth the same way
`AGENT.md` is the architecture source of truth.

---

## Gating Phase 3

Frontend modules in Phase 3 must consume `DESIGN.md` + the token config:

- No hardcoded colors / spacing / radii in components — reference tokens only.
- No new component variant that is not in the inventory without updating
  `DESIGN.md` first.
- Every screen ships all four states (loading / empty / error / populated), not
  just the happy path.
- Verification gate for UI is L4 (browser screenshot, `12-verification.md`) —
  and the screenshot is checked against the design direction, not just "renders".

---

## Anti-slop checklist

The tells of generic AI UI — avoid all:

- [ ] More than one accent color, or accent used for non-primary actions
- [ ] Inconsistent spacing (eyeballed margins instead of the scale)
- [ ] Default browser focus/validation styling left unstyled
- [ ] Spinner on a blank page instead of a skeleton
- [ ] No empty state (table renders nothing on first run)
- [ ] Centered everything / no visual hierarchy
- [ ] Emoji as icons in a serious product
- [ ] Light-mode-only when the direction called for dark
- [ ] Inaccessible contrast or missing focus rings
