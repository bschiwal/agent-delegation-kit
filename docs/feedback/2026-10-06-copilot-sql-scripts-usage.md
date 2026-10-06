# Copilot build: six SQL scripts - usage report

Source: a `triage-lead` session in VS Code Copilot on a work machine (work
preset), writing six SQL scripts over existing views for an aggregate-only
export. Reported cost: about 1,000 credits. Names of views, columns and
clients made generic for this public repo.

**Limit on the figures.** Per-run tokens were not recorded, and credits were
not visible to the session. The counts below are runs, not tokens.

## Runs (about 35, plus the orchestrator's own turns)

| Agent | Runs | Purpose |
|---|---|---|
| repo-scout | 1 (plus 1 failed on a missing parameter) | Locate the plan |
| sql-developer | 6 builds, 6 round-1 fixes, 5 round-2 resumes, 2 final fixes | Scripts and fixes |
| data-model-reviewer | 6 round-1, 2 round-2, 1 final | Review |
| security-reviewer | 2 | PII review |
| doc-writer | 1 | Decision register |
| Wasted | 3 | A "reply OK" call, a built-in task agent with no shell, a general-purpose agent sent to run `git status` |

About 12 orchestrator turns were only "waiting" messages after background
launches, each re-reading the orchestrator's context.

## What worked

The reviews found real defects: a proof query that could never fail, selectors
that picked out one entity's timeline (a PII risk), a `;;` compile error,
missing `GO` batching in two scripts, and small-cell leaks by subtraction.

## What cost more than it should

- **No shared conventions.** Six builders each invented their own, and the
  same classes of finding recurred in every file: `GO` batching, small-cell
  suppression, SQLCMD variable validation, replicating a view's logic exactly,
  untrimmed typed audits. Round 1 (six reviews, six fixes) was mostly that.
- **Repeated reads.** Each builder re-read the plan preamble, the brief and
  the shared view; each of nine reviewers re-read the views.
- **One reviewer per file** in round 1. Grouped reviewers in round 2 paid the
  floor fewer times.
- **Review work a script could do.** Header, `GO` structure, forbidden
  keywords, `;;`, PII-column grep. Three late premium findings were that kind.
- **Wasted runs**, and agents picked without checking their tools.
- **Background launches** against the profile's foreground rule, then waiting.
- **Resuming large fix agents** for small, fully specified edits.
- **Two security passes** over everything for aggregate-only scripts.

The session judged one agent doing everything would not clearly be cheaper
(no independent review, a growing context over ~2,500 lines of SQL), and
estimated a 30-50% saving from: one conventions spec, one or two builders,
a lint script, two grouped reviewers.

## Changes asked for

- triage-lead: conventions and brief template before parallel builders;
  record tokens per run; check tool access before delegating; parallel
  foreground calls, no trivial agents.
- sql-developer: standing rules (GO batching, small-cell suppression, SQLCMD
  validation, no `;;`, view-faithful replication).
- Reviewers: group by file set; one fix round plus one re-review of changed
  hunks.
- Kit: ship a Phase 0 SQL lint script.
