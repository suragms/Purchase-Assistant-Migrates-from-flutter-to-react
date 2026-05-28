# Harisree documentation hub

Canonical product documentation for the Harisree Purchase Assistant (warehouse + purchase + stock).

## Read order (every Cursor session)

1. **[MASTER_REFERENCE.md](MASTER_REFERENCE.md)** — infra, UX system, page matrix, priorities, deploy (read first)
2. **[../../CURRENT_CONTEXT.md](../../CURRENT_CONTEXT.md)** — current focus and key paths
3. **[../../PROGRESS_LOG.md](../../PROGRESS_LOG.md)** — what changed and when
4. **[FEATURES_DEEP_PLAN.md](FEATURES_DEEP_PLAN.md)** — owner-visibility and feature deep specs (when relevant)
5. **[IMPLEMENTATION_PHASES.md](IMPLEMENTATION_PHASES.md)** — ordered completion phases and verification gates

## Before any API or app test

**Step 0:** Resume Render (`my-purchases-api`) and verify `curl https://my-purchases-api.onrender.com/health` returns ok. See MASTER_REFERENCE § STEP 0.

## Files in this folder

| File | Purpose |
|------|---------|
| `MASTER_REFERENCE.md` | Single source for Harisree decisions, costs, pages, todos |
| `FEATURES_DEEP_PLAN.md` | Detailed feature specs (feed, variance, health score, etc.) |
| `IMPLEMENTATION_PHASES.md` | Ordered phase plan for cleanup, stock correctness, notifications, scan, PDFs, stock workflows, responsive UI, performance, help, backup, sales comparison |
| **[`../../plando/README.md`](../../plando/README.md)** | **Canonical sprint hub** — TODO P0–P3, audits, patches (2026-05-28) |

## Section prompt files

The `dfiles/` folder mirrors the master agent prompt as ordered implementation sections:

- `00_MASTER_RULES_AND_PLAN.md` through `07_OPENING_STOCK_PHYSICAL_STOCK.md`
- `08_STAFF_PURCHASE_LOGS.md`
- `09_DESKTOP_RESPONSIVE_LAYOUT.md`
- `10_PERFORMANCE_OPTIMIZATIONS.md`
- `11_HELP_GUIDE.md`
- `12_AUTO_BACKUP.md` (deferred after manual backup)
- `13_SALES_COMPARISON_REPORT.md` (first-pass pasted-row matcher shipped; PDF/XLSX upload pending)

## Related docs (repo root)

- `CURRENT_CONTEXT.md`, `PROGRESS_LOG.md`, `BUGS.md`, `TASKS.md` — session trackers
- `ALL_REMAINING_BLOCKERS.md` — known blockers (if present)
