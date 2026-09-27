# Changelog

What changed in the kit, why, and which evidence drove it. Newest first.

Read **Settled decisions** before changing agent behaviour. Most changes in this
kit come from after-action reports on real builds, and a report written under
pressure can ask for the opposite of what an earlier report fixed. If a proposed
change reverses a settled decision, it needs new evidence, not just a new report.

The long-form reasoning for the first three audits is in
[`docs/routing.md`](docs/routing.md), principle 4. The raw reports from later
builds are in [`docs/feedback/`](docs/feedback/).

## Settled decisions

Each row is a question that has already been answered, what the answer is now,
how it got there, and what would justify reopening it.

| Question | Current answer | History | Reopen only if |
|---|---|---|---|
| Turn caps | Builders (`pbir-builder`, `model-builder`) 40. `implementer` 25, `debugger` 30, reviewers 20, `repo-scout` 15 | Caps were cut from 50 to 25 on 2026-09-18, because runs hit the cap editing one visual per turn. Builders went back up to 40 on 2026-09-25, because they hit 25 while doing the right work. The second change fixed a different problem; it did not reverse the first. | Runs stop at the cap *while working correctly* (raise it), or *while wandering* (fix the brief or the pacing, not the cap). |
| When to stop and reply | Generated footer: stop new work at 75% of the cap, reply by cap−4 (turn 36 for a 40-turn builder). `pbir-builder` also validates by turn 24. In Claude Code, `hooks/turn-budget.ps1` tells the subagent when it reaches each point | 75% point added 2026-09-18. The cap−4 reply deadline added 2026-09-26. The next build still overran with the rule installed, because agents don't count their own turns, so the hook was added 2026-09-27 rather than a different number. | Runs overrun *with* the hook's notes in their transcript. Until then, don't move the numbers. |
| Progress file | Builders append to `.claude/runs/<step>.md` after each milestone. Replies are about 25 lines, details go in the file | Added 2026-09-26 (G3 AAR P1, P6). Reviewers were deliberately left out, because their findings *are* the payload. | - |
| Recon | Where-is and how-does questions go to `repo-scout`. Complete inventories (every page, literal, ID) are a script the orchestrator runs | 2026-09-18: the orchestrator read four large files itself, so recon moved out. 2026-09-27: two scout inventories cost 115k, overran and missed instances, so inventories went to scripts. This narrowed the 09-18 rule; it did not reverse it. | A scout is again asked for a complete list, or an orchestrator reads files itself for a where-is question. |
| Large output | Through `log-triager` or a filter script, never read raw. One validation summary script per project, written before builders start | Filter rule 2026-09-18. Per-project script 2026-09-26: parallel builders each wrote their own filter and disagreed on counts. The kit ships the rule, not the script (the project owns it). | The kit needs a language or runtime dependency anyway. |
| Opus on builders | Default `implement` model. The main session may pass `model: "opus"` for a hard step, a batch that can't be split, or a second attempt. Never for finding out what to fix | 2026-09-25: the default model landed none of a 7-fix batch but landed single fixes. 2026-09-27: an Opus run that bundled diagnosis and fix cost 146k with no fix. | - |
| Fable | Only on a grant in the request or a Yes to one question. Enforced by `hooks/fable-gate.ps1` | 2026-09-22. | - |
| Session length | One session per build pass. A checked Desktop save gate counts as a gate, and at the gate the orchestrator *asks* (`Hand off?`) rather than offering | Rule 2026-09-25, sharpened 2026-09-26. It was ignored both times, so 2026-09-27 changed how it applies (a question the user answers), not what it says. | The question gets asked and sessions still run long. Then it needs a hook, not more wording. |
| Default orchestrator in Claude Code | The main session, via the installed `claude-delegation.md` policy. Not `triage-lead` | 2026-09-18: `"agent": "triage-lead"` replaces the system prompt and drops MCP, skills and Opus. | Claude Code lets an agent-default session keep MCP and skills. |
| Copilot and MCP | Copilot agents get MCP tools through `registry/mcp.json` | 2026-09-18: `model-builder` was made Claude-only on the assumption Copilot couldn't use MCP. That was wrong, and was reversed the same day. | - |
| Plan-only mode | A mode of both orchestrators. There is no separate router agent | 2026-09-18: `delegation-router` was removed because it duplicated `architect`. | - |
| Test and replica queries | `TREATAS` or `SUMMARIZECOLUMNS`, never `CROSSJOIN` grids. Replicas use different mechanics from the measure under test | `CROSSJOIN` rule 2026-09-25; replica rule 2026-09-26. | - |

## 2026-09-27 - SR2 post-G3 AAR
source: [`docs/feedback/2026-09-27-sr2-post-g3-aar.md`](docs/feedback/2026-09-27-sr2-post-g3-aar.md)

Half of this report's recommendations were already in the kit (#3), and were
installed during the session. So this round changes how rules are applied, not
what they say.

- **Turn budget hook** (`hooks/turn-budget.ps1`, installed with
  `-WithInstructions`). It counts a subagent's turns from its transcript and
  adds a note at the stop-new-work turn and from the reply turn on. Tested in
  Claude Code 2.1.283: hook input carries `agent_id` and `agent_type` for
  subagent calls, and a subagent acts on the note. Declaring the hook in agent
  frontmatter did not fire, so the installer registers it in settings. The
  installer's hook code now handles any number of kit hooks.
- **Inventories are a script, not a scout.** `repo-scout` declines complete
  lists and hands back the grep or script, says where every number came from,
  and lists what it did not check.
- **A new shared helper is its own step**, built and reviewed before the pages
  that use it.
- **Performance work is diagnose, then fix.** Time the visual's real query from
  Performance Analyzer, read-only. Fix only once the diagnosis names one lever.
  Opus is never for finding out what to fix.
- **Hand-off at a gate is a question** (`Hand off?`), not an offer.
- **Desktop save routine:** back up, snapshot, diff with the noise filtered out,
  add Desktop edits to the generator, regenerate.
- **Bulk edits check before they write:** a script refuses to write when a
  match falls outside where the change belongs (the Leigh/Lehigh catch).
- Report recommendations not taken: a `perf-probe` agent (a rule covers it), a
  `debugger` DAX tool (`debugger` runs on Opus anyway), moving the reply turn
  from 36 to 32 (the number wasn't the problem), and the `GEN/` save-gate
  scripts (these belong in the report project, not the kit).

## 2026-09-26 - SR2 G3 pass AAR
[#3](https://github.com/bschiwal/agent-delegation-kit/pull/3) ·
source: [`docs/feedback/2026-09-25-sr2-g3-pass-aar.md`](docs/feedback/2026-09-25-sr2-g3-pass-aar.md)

- **All agents:** a reply deadline at cap−4, with open work listed under
  **Not finished**. All four page builders ran out of turns in fix loops before
  reporting.
- **Builders:** a progress and details file at `.claude/runs/<step>.md`, and
  replies of about 25 lines. Claims that something "doesn't exist" cite a source
  or are marked unverified. They never run shared global scripts.
- **`pbir-builder`:** validates by turn 24 and judges only its own pages. Uses
  the backup command from the brief. Structural checks for `active` and the
  tabular matrix.
- **Reviewers:** a **Same pattern elsewhere** list on each finding. Replicas use
  different mechanics from the measure under test.
- **Orchestrator:** one validation summary script per project. Read the progress
  file before resuming. Briefs state git and exact command lines. Artefacts
  authored in Desktop are fixed in Desktop. A Desktop screenshot and an exemplar
  come before `debugger`. User checklists name pages and click paths.

## 2026-09-25 - SR2 v2 build report (third audit)
[#2](https://github.com/bschiwal/agent-delegation-kit/pull/2) · detail:
`docs/routing.md` principle 4, "A third build"

- `model-builder` and `pbir-builder` caps 25 → 40, with checkpoints: something
  written by turn 8, validated or committed by turn 30.
- Short transactions that are never left open. `TREATAS` tests. Split fix
  batches. The resume-vs-fresh rule. Per-step spec files from `architect`.
- Structural self-check in PBIR scripts. A required **Spec items not built**
  section in replies.
- Opus allowed on hard builder steps. One session per build pass.

## 2026-09-23 - Model catalogue refresh
[#1](https://github.com/bschiwal/agent-delegation-kit/pull/1)

- Prices refreshed from GitHub docs. Routing updated for the new models.

## 2026-09-22 - Fable gate

- Fable only by grant or on a Yes answer, enforced by `hooks/fable-gate.ps1`.

## 2026-09-18 - First and second build audits, and the platform work

- **Local employer policy:** `policy.local.json` and `availability.local.json`
  (both gitignored) build to `build/local/`. New `review-critical` tier. A retry
  limit: two identical failures means stop.
- **Copilot MCP:** MCP declared abstractly per agent and mapped by
  `registry/mcp.json`. Reverses the same-day "Claude-only" assumption.
- **`model-builder`:** live model work leaves the main session. It shares the
  main session's connection.
- **Second audit:** the orchestrator's context became the largest cost. Added
  "Keep your own context small", baseline validation, known-issues in briefs,
  and "needs live check".
- **One delegation policy:** `delegation-core.md` partial, generated roster,
  `delegation-router` removed.
- **First audit (56M tokens on one build):** turn caps cut, the generated turn
  budget footer, `pbir-builder` with generators, scoped review, plans on disk.
- **Orchestration:** `triage-lead` added. The Claude Code default is the
  installed policy, not a default agent.
- **Docs:** stopped pointing Claude Code users at `/agents`.

## 2026-09-17 - Initial kit

- Agents name a role and `registry/policy.json` maps roles to models. Builds
  for Claude Code and Copilot from one source.
- Model availability tracking, and a weekly catalogue refresh workflow.
