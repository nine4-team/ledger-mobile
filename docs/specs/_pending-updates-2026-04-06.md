# Pending Updates — 2026-04-06
These updates need to be merged into the locked files (_feedback-log.md, _index.md, _changelog.md) when they become accessible.

---

## Append to _feedback-log.md

## 2026-04-06

### Raw Feedback
In the needs review tab, this idea is cool in theory, but we're running into the same issue we had with the previous search bar, where when I click into a thing that needs review I have no context on which client it's for, what project it's living in, or if I'm supposed to assign it to something. it just doesn't give the full picture.

Follow-up clarification: Would like a breadcrumb trail for context, but also items organized per project / inventory when you go into the needs review page. A visual divide based on what project the transaction is for. Then if there are transactions that are undefined, can easily assign them to the right project. Assignment mechanism is TBD — needs more thought.

### Screenshots
None this session.

### What I Did With It
Created new spec file: needs-review-tab.md (status: modify). Covers the grouped-by-project list layout, breadcrumb navigation on item detail, inventory/unassigned section, and the assign-to-project concept as an open question.

---

## Add to _index.md (under appropriate section)

- [modify] [Needs Review Tab](needs-review-tab.md) — Review queue for items needing attention, grouped by project with breadcrumb context

---

## Append to _changelog.md

### 2026-04-06
- **Created** `needs-review-tab.md` — New spec for the Needs Review tab. Core issue: items shown without project/client context (same problem as the old search bar). Spec covers: grouping the list by project with visual dividers, an inventory/unassigned section, breadcrumb navigation (Client > Project > Category) on item detail views, and an assign-to-project action (TBD). Several open questions flagged around what triggers "needs review," assignment flow mechanics, and whether breadcrumbs should be adopted globally.
