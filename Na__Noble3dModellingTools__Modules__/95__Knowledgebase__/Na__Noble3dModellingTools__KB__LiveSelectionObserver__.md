# Live Selection Observer — Design Rationale
# =============================================================================
# Knowledgebase : Na Noble3d Modelling Tools
# Topic         : Why the Selection Observer Pattern Produces More Robust Dialogs
# Author        : Noble Architecture
# Date          : 24-Jun-2026

---

## The Problem With a Static Snapshot

When a SketchUp dialog opens, it can capture the current selection and display information about it. That is the straightforward approach, and it works fine for simple one-shot tools — you trigger an action, the result is immediate, the dialog closes. But any tool that is designed to stay open alongside the model while the user continues working runs into a fundamental problem: the world the dialog was built from changes the moment the user clicks something in the model.

Under a static approach, the dialog has no way of knowing this happened. It continues to show information that was true at open time, which may be completely wrong by the time the user actually reads it or acts on it. The user is left reasoning about whether the dialog is still accurate, or has to close and reopen it every time they change their selection. That is friction that should not exist.

---

## What the Observer Pattern Does Differently

The observer approach registers a listener directly with SketchUp's selection mechanism. Rather than taking a photograph of the selection once and walking away, the dialog subscribes to an event stream. Every time anything about the selection changes — something added, something removed, the whole selection cleared, or a bulk replace — the dialog receives an immediate notification and can act on it.

This means the dialog is always describing the current state of the model, not a past state. It reacts to the model rather than ignoring it. The user never has to question whether what they are seeing is still valid.

---

## Practical Benefits in Use

**Always-accurate information.** Switching from one group to another in the model updates the dialog instantly. There is no moment where the dialog is confidently showing data for the wrong thing.

**Informative edge cases.** When the selection is cleared entirely, the dialog does not silently present an empty or meaningless list — it shows a clear message explaining why there is nothing to act on. When the new selection contains no relevant data, the dialog says so plainly. The user is never left wondering why the tool looks broken.

**No manual refresh required.** The user does not need to close and reopen a tool to get current information. The tool stays open and stays correct, which encourages leaving it open as a companion inspector during active modelling work rather than treating it as a one-time trigger.

**Confidence before acting.** Because the checklist the user sees is always a live reflection of their current selection, they can be confident they are about to act on the right things. There is no risk of the dialog silently acting on a stale selection from three clicks ago.

---

## Why Explicit Cleanup Is Non-Negotiable

Attaching an observer is only half the responsibility. The observer must also be removed when the dialog closes. This is not a minor detail — it is a correctness requirement.

An observer that is never detached continues to exist in memory and continues to fire after the dialog it served has been closed and discarded. At best this wastes resources silently. At worst it causes background errors on every subsequent selection change in the session, or interferes with future instances of the same dialog being opened.

Tying the observer's lifespan exactly to the dialog's lifespan — attach on open, detach on close — makes the behaviour completely predictable. Multiple open-and-close cycles within the same SketchUp session each get a fresh, properly wired observer. There is no accumulation of phantom listeners over time.

---

## When This Pattern Should Be Applied

Any dialog that presents information derived from the current SketchUp selection, and is designed to remain open while the user continues working in the model, should use this pattern. The longer the dialog is intended to stay open alongside active modelling, the more important live sync becomes.

Tools that trigger a single immediate action and close automatically gain less from this approach. But any tool that acts as an inspector, a configurator, or a context-aware panel sitting beside the model should treat the selection as a live feed, not a frozen input.

---
