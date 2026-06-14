# Learning Protocol

`vortex` is a **learning vehicle**, not just a thing to ship. This document governs how the human
(owner) and the AI collaborate so the owner actually **learns** the two CV-gap skills —
**Kubernetes/orchestration** and **observability** — instead of watching an agent build a platform.

> Theory/reference lives in the sibling repo: `../platform-engineer-handbook`.
> This doc is the *mechanism* that turns reading into understanding.

## Starting a new session (cold start)

Sessions are stateless — the chat history is gone next time. **All durable context lives in files**,
so a fresh session (or a fresh agent) re-derives it automatically:

```
new session in the vortex repo
  → auto-loads CLAUDE.md
      → Golden rule 0 points here (docs/LEARNING.md)
          → which points to ../platform-engineer-handbook (theory)
  → decisions are already in docs/adr/*.md
```

So you don't carry context manually. The ritual:
1. `cd ~/projects/own-develop/vortex && claude` (CLAUDE.md loads itself).
2. Say where you are + the mode, e.g. **"Phase 2, Kubernetes, tutor mode."**
3. The AI: reads this protocol, ports/opens the matching handbook doc, runs the Theory → Lab → Check loop.

If something must survive across sessions, it goes in a **file** (ADR, this doc, the handbook),
never "in the conversation." Chat is scratch; repo is memory.

## The anti-goal

> ❌ "The AI builds the platform while I review the diff."

For the **gap skills**, that produces a portfolio you can't defend in an interview. The whole point
of vortex is *senior judgment you can explain*. If you can't explain it, it isn't done.

## Three modes (chosen explicitly per task)

| Mode | Use for | AI does | Human does |
|---|---|---|---|
| **Tutor** | CV-gap skills: **K8s, observability, networking, cloud/IaC** | Explains the concept + *why* + links the handbook doc. **Does NOT write the target artifact.** Reviews + quizzes after. | Writes the manifests/config **by hand**. |
| **Pair** | medium-novelty: GitOps/ArgoCD, Helm templating, CI pipelines | Scaffolds a skeleton with `# TODO` + "why" comments. Reviews. | Fills the gaps; resolves the TODOs. |
| **Autopilot** | boilerplate you've already done by hand once: service CRUD, repeat Dockerfiles, repetitive YAML | Writes it. | Reviews the diff and **must be able to explain every part**. |

### Default mode by area (override explicitly when you want to)

```
Kubernetes (Phase 2, headline) ........ tutor
Observability (Phase 3) ............... tutor
Networking / cloud / OpenTofu (infra) . tutor
GitOps / ArgoCD (Phase 4) ............. pair
Helm templating ....................... pair
Service business logic (dummy) ........ autopilot
Dockerfile (after the first by hand) .. autopilot
CI YAML boilerplate ................... autopilot
ADR prose formatting (you decide; AI drafts) . pair
```

First time you touch *any* skill → **tutor**, regardless of the table.

## The per-task loop

1. **Concept first.** AI states the concept + *why this approach* + the handbook link. **No code yet.**
2. **You implement.** Tutor/pair → you write it by hand. Autopilot → AI writes, you review the diff.
3. **Break it, fix it.** Deliberately break one thing (wrong port, missing probe, bad selector),
   observe the failure, fix it. This is where understanding actually forms.
4. **Quiz.** AI asks the handbook's skill-check questions. Can't answer → not done.
5. **Decide → ADR.** Any non-trivial choice → `docs/adr/ADR-NNN-*.md` (already vortex law).

## Tutor mode format (HTB-style)

Tutor mode mirrors **Hack The Box Academy**: read theory, do tasks in a lab, then submit answers
that get graded. The lab is **not a sandbox VM — it's your real NixOS machine + vortex itself**.
Each handbook section ends with:

```
<theory>
🎯 Lab        — guided tasks with hints (run the commands)
🏴 Challenge  — one unguided task: do it, then BREAK it and identify the layer
❓ Skill check — deterministic questions (a number / one word / command output)
                you submit answers; the AI grades pass/fail. Answer key hidden in <details>.
🧠 Explain    — the interview exam: explain out loud, AI critiques
```

Why deterministic answers: a number or a socket state can be **graded unambiguously** — you can't
hand-wave past it. A section isn't "done" until the skill check passes *and* you can do the explain tier.
Progression is always **guided → unguided → skill check**, never straight to the answer.

## Definition of "done" (extends the roadmap's "finished + understood")

A task/phase is done only when **all** hold:
- [ ] It works (and you've seen it fail and recover — step 3).
- [ ] If it involved a decision → an ADR exists.
- [ ] **You can explain it out loud** — the handbook interview questions, from memory.

## Rules for the AI (so the protocol is actually enforced)

- **Announce the mode** at the start of a gap-skill task ("Tutor mode: I'll explain, you implement").
- In **tutor mode, do not output the finished manifest/config.** Explain, link the handbook, give
  hints, review what the human wrote. Provide a full solution only if the human explicitly switches
  to autopilot or asks after a genuine attempt.
- **End every gap-skill task with 2–3 quiz questions** from the relevant `platform-engineer-handbook`
  doc. Don't skip this.
- If asked to "just build" a gap-skill artifact, **push back once** and offer tutor/pair first; obey
  if the human confirms autopilot.
- Default to the mode table above; the human can override per task with one word
  ("tutor" / "pair" / "autopilot").

## Switching modes

Say the word: `tutor`, `pair`, or `autopilot`. Pragmatic pattern — **tutor the first instance,
autopilot the repeats**: learn one Dockerfile/Service/Deployment by hand, then let the AI replicate
the pattern across the other services while you review.
