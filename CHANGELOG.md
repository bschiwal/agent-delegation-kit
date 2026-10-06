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
| Turn caps | Builders (`pbir-builder`, `model-builder`) 40. `implementer` 25, `debugger` and `sql-developer` 30, reviewers 20, `repo-scout` 15 | Caps were cut from 50 to 25 on 2026-09-18, because runs hit the cap editing one visual per turn. Builders went back up to 40 on 2026-09-25, because they hit 25 while doing the right work. The second change fixed a different problem; it did not reverse the first. | Runs stop at the cap *while working correctly* (raise it), or *while wandering* (fix the brief or the pacing, not the cap). |
| When to stop and reply | Generated footer: stop new work at 75% of the cap, reply by cap−4 (turn 36 for a 40-turn builder). `pbir-builder` also validates by turn 24. In Claude Code, `hooks/turn-budget.ps1` tells the subagent when it reaches each point | 75% point added 2026-09-18. The cap−4 reply deadline added 2026-09-26. The next build still overran with the rule installed, because agents don't count their own turns, so the hook was added 2026-09-27 rather than a different number. | Runs overrun *with* the hook's notes in their transcript. Until then, don't move the numbers. |
| Progress file | Builders append to `.claude/runs/<step>.md` after each milestone. Replies are about 25 lines, details go in the file | Added 2026-09-26 (G3 AAR P1, P6). Reviewers were deliberately left out, because their findings *are* the payload. | - |
| Recon | Where-is and how-does questions go to `repo-scout`. Complete inventories (every page, literal, ID) are a script the orchestrator runs | 2026-09-18: the orchestrator read four large files itself, so recon moved out. 2026-09-27: two scout inventories cost 115k, overran and missed instances, so inventories went to scripts. This narrowed the 09-18 rule; it did not reverse it. | A scout is again asked for a complete list, or an orchestrator reads files itself for a where-is question. |
| Large output | Through `log-triager` or a filter script, never read raw. One validation summary script per project, written before builders start | Filter rule 2026-09-18. Per-project script 2026-09-26: parallel builders each wrote their own filter and disagreed on counts. The kit ships the rule, not the script (the project owns it). 2026-10-06: generic SQL query and lint *starters* ship in `templates/project-tools/sql/` for a project to copy; the project still owns its copy. | The kit needs a language or runtime dependency anyway. |
| Opus on builders | Default `implement` model. The main session may pass `model: "opus"` for a hard step, a batch that can't be split, or a second attempt. Never for finding out what to fix: an Opus brief states the fix in one sentence, and the team line shows it | 2026-09-25: the default model landed none of a 7-fix batch but landed single fixes. 2026-09-27: an Opus run that bundled diagnosis and fix cost 146k with no fix. 2026-09-28: the rule was broken again (three Opus diagnosis runs, 415k), so the brief now has to name the fix. | Opus runs still go out as diagnoses with a named fix in the brief. Then it needs a hook on the Agent call. |
| Run sizing | Size by budget. Every run has a floor of about 50-70k, so trivial, fully specified edits are batched into one run, and edits in ranges the orchestrator has already read are made by the orchestrator. Fixes that need reading or reasoning are still split | Split rule 2026-09-25 (a 7-fix batch landed nothing). Floor and batching 2026-09-28: five trivial edits split across three runs cost about 130k extra. This narrowed the split rule to fixes that need thought; it did not reverse it. | A batch of *trivial* edits fails the way the 09-25 batch did. |
| Shared helpers | Built and reviewed in their own run before pages use them. A helper of about 50 lines with an exact example may go with its first use, or be written by the orchestrator, but is reviewed before anything copies it | Own step 2026-09-27 (a helper plus four visuals overran). Small-helper exception 2026-09-28. The part that matters - reviewed before copied - did not change. | A small helper built with its first use ships a bug into a copy. |
| Review coverage | Every non-trivial change is reviewed. Two exceptions, each named in the Skipped line: a rewrite proven equal to what it replaces over the whole grid, and position-or-size-only changes checked on a screenshot | "Review everything" since 2026-09-17. The exceptions were made case by case in two sessions, and were written down 2026-09-28. | A skipped review lets a wrong number through. |
| Schema-unreachable validation | With the PBIR schema unreachable, `pbir-builder` reports **validation incomplete**, whatever the project's summary script does with the error | 2026-09-25: three structural errors passed an unreachable-schema validation and failed in Desktop. 2026-09-28: two sessions asked for the recurring error to stop failing `validate.py`. That is fine in the project's script (report it on its own line), but it must not turn "incomplete" into "passed". | - |
| Fable | Only on a grant in the request or a Yes to one question. Enforced by `hooks/fable-gate.ps1` | 2026-09-22. | - |
| Session length | One session per build pass. A checked Desktop save gate counts as a gate, and at the gate the orchestrator *asks* (`Hand off?`) rather than offering. `hooks/context-meter.ps1` tells the main session its context size on every user message, and to hand off above about 100k | Rule 2026-09-25, sharpened 2026-09-26, made a question 2026-09-27. The question was still skipped (a session ran through about five save gates), so 2026-09-28 added the hook, as this row said it would. | Sessions still run past 150k with the meter's advice in their transcript. Then the thresholds or the note's wording need a look. |
| Work machine setup | A clone that only pulls, with its own `*.local.json` files, never copied from home. `"config_only_clone": true` makes the build stop if a committed file changed there. Lessons come home as reviews from `docs/feedback/local/` | 2026-10-01. The docs used to say to copy the `.local` files from home to work. New models come from the public catalogue refresh, so there is no local model catalogue (rejected 2026-10-01: work allows fewer models than the public list, not more). | A work model is missing from the public catalogue for longer than a refresh cycle. |
| Copilot-only rules | Copilot sessions orchestrate through `triage-lead`, which edits small things itself and carries Copilot-only cost rules (grouped reviews, fresh fix runs, no waiting turns, usage line) in `IF:copilot` blocks. Conventions-first, lint-before-review and the SQL rules apply to both platforms | 2026-10-06: a Copilot SQL build cost about 35 runs. Rules that hold for any build moved to `delegation-core.md` the same day; the rest stayed Copilot-only. | Claude Code shows the same over-splitting; then move that rule into `delegation-core.md`. |
| Default orchestrator in Claude Code | The main session, via the installed `claude-delegation.md` policy. Not `triage-lead` | 2026-09-18: `"agent": "triage-lead"` replaces the system prompt and drops MCP, skills and Opus. | Claude Code lets an agent-default session keep MCP and skills. |
| Copilot and MCP | Copilot agents get MCP tools through `registry/mcp.json` | 2026-09-18: `model-builder` was made Claude-only on the assumption Copilot couldn't use MCP. That was wrong, and was reversed the same day. | - |
| Plan-only mode | A mode of both orchestrators. There is no separate router agent | 2026-09-18: `delegation-router` was removed because it duplicated `architect`. | - |
| Test and replica queries | `TREATAS` or `SUMMARIZECOLUMNS`, never `CROSSJOIN` grids. Replicas use different mechanics from the measure under test | `CROSSJOIN` rule 2026-09-25; replica rule 2026-09-26. | - |

## 2026-10-06 - Copilot: the picked agent runs on the picker

Tested on a work machine in VS Code 1.139 (Copilot harness), reading the models
from `~/.copilot/session-state`:

- `triage-lead`, picked in the dropdown, ran on the **picker's** model
  (Gemini 3.8 Flash) although its file named GPT-5.6 Terra, as a list and as a
  single name. The picker does not change when an agent is picked.
- Agents it called ran on **their own profiles**: `repo-scout` on GPT-6 Luna,
  `pbir-builder` on GPT-5.6 Terra.

`docs/vscode-copilot-setup.md` no longer says the agent's model is "already
set": the user sets the picker to the picked agent's first model, avoids Auto,
and can check a session's real models with a script over the session log. No
build change: a single model name did not help the picked agent, and lists
work for called agents. Harness support for `model:` on the picked agent
landed in VS Code Insiders 1.141 (microsoft/vscode#338489) - re-test then.

## 2026-10-06 - Copilot triage-lead edits; SQL rules for both platforms; starter SQL tools

Follow-up to the Copilot usage report below, on the user's answers.

- **Copilot `triage-lead` now edits** (`edit` tool) and has a **Do it yourself
  when** section, modelled on the Claude main session's: questions from a few
  reads, a small obvious edit, edits in lines it has already read, review fixes
  it can state exactly, and notes (conventions, resume notes, run logs, session
  reviews). New code, unread code and work across more than about three files
  still go out, and its own edits are reviewed. Asked for because every fix in
  Copilot paid an agent's 50-70K floor. The Claude `triage-lead` is unchanged -
  in Claude Code the main session already does this.
- **Build:** `"copilot": { "description": ... }` replaces the shared
  description on Copilot only, so the two `triage-lead` builds describe what
  each can do.
- **Moved to both platforms**, because they hold for any multi-builder build and
  any SQL: "conventions before parallel builders" and "deterministic checks are
  a script" (now in `delegation-core.md`); the `sql-developer` standing rules;
  the reviewers' "skip what the lint script passed" and "one pass over the
  whole set". Briefs now name the lint and query commands too.
- **Kept Copilot-only**, because the Claude side has no evidence of the problem
  or already has a better tool for it: grouped reviews and one security pass,
  fresh fix runs, no waiting turns, the usage line and loop check (Claude has
  real token figures and the turn-budget hook), and the shell-agents check.
- **Starter SQL tools** in `templates/project-tools/sql/`: `sql-query.ps1`
  (read-only queries using the project's `.env`, so agents never open it or see
  a password; refuses writes, `INTO` and `EXEC`, rolls every batch back),
  `sql-lint.ps1` (batches, `;;`, view headers, `ORDER BY` in views, `SELECT *`,
  `NOLOCK`, variables across `GO`, SQLCMD checks, never-output columns), a
  conventions template and a never-output list. The report's session said it
  had no database access although the project's `.env` had a connection: that
  was `sql-developer` correctly refusing to hunt for credentials.
  `sql-developer` now looks for a query script before giving up, and
  `data-model-reviewer` settles SQL data assumptions with one. These are
  starters a project copies and owns; the kit never runs them, so the settled
  "the project owns the script" row still holds. Tested here against sample
  SQL with each defect class; the query script's guard and `.env` parsing were
  tested, but not a query against a live server.

## 2026-10-06 - Copilot orchestration: fewer runs per build
source: [`docs/feedback/2026-10-06-copilot-sql-scripts-usage.md`](docs/feedback/2026-10-06-copilot-sql-scripts-usage.md)

A Copilot `triage-lead` build of six SQL scripts took about 35 agent runs and
about 1,000 credits. The reviews earned their place - they found real defects -
but most findings were the same five classes in every file, and the run count,
not the work, drove the cost. **Every change is Copilot-only**, inside
`<!-- IF:copilot -->` blocks: the Claude Code side is working well, and none of
`build/claude/` changes.

- **`triage-lead` (Copilot)** gets a read-only terminal (`execute`) for `git
  status`, lint and inventory scripts. Its Claude twin never needed it: there,
  the main session orchestrates and has a shell. This closes a gap with the
  settled "inventories are a script the orchestrator runs".
- **`triage-lead` (Copilot)** new section: check the agent has a shell before
  delegating a command (list generated by `<!-- GENERATE:shell-agents -->`);
  roster agents only; no trivial runs; a **Phase 0 conventions file** before
  parallel builders; fewer builders over groups of files; a project **lint
  script** run before every review round; **one reviewer per lens** over the
  whole set; one security pass at the end; one fix round then one re-review of
  changed hunks; fixes to a **fresh** batched run rather than a resumed builder;
  parallel foreground calls in one message and no waiting turns; a run log
  with `not shown` where no token figure is given; the session-per-pass hand-off
  and session-review shape that until now only the Claude main session had.
- **`sql-developer` (Copilot)**: standing rules - `GO` around every view, no
  `;;`, SQLCMD variables validated, replicate a view from its definition,
  compare at the source's type and trim, a proof that can fail, aggregate-only
  outputs with complementary suppression, and run the lint script.
- **`data-model-reviewer`, `security-reviewer` (Copilot)**: skip what the lint
  script passed; review a file set in one pass and report recurring findings
  once with every location.
- **Usage line and loop check (Copilot).** Copilot shows neither agent nor
  caller a token figure, so every Copilot agent's generated footer now asks it
  to keep a tally and end each reply with `Usage: <calls> of ~<budget> | files
  read (~lines) | edits | repeated calls | stopped: ...` - counts, never a token
  guess - and to stop when it edits the same lines a third time for one problem.
  `triage-lead` logs the line per run, uses calls in the team line, and treats a
  run as looping on: stopped at budget or repeat failure, 3+ repeated calls,
  many calls for few edits, a missing Usage line, or a finding that survives its
  fix round. A looping run is never resumed: fresh narrow run, or ask the user.
  Lives in the `-Soft` branch of `Get-BudgetFooter`, which only Copilot uses, so
  the Claude footer and `hooks/turn-budget.ps1`'s regexes are untouched.
- **Not done: a kit-shipped SQL lint script.** The settled "large output" row
  says the kit ships the rule, not the script; the project owns it. The rule is
  now in `triage-lead` and `sql-developer`.
- **Not done: a third review round.** The Copilot rule is stricter than the
  core's two-round stop (one fix round, one re-review), and asks the user before
  a third. It narrows the core rule for Copilot; it does not reverse it.
- Candidates for both platforms once Claude has evidence: the conventions step,
  grouped reviewers and the `sql-developer` standing rules.

## 2026-10-01 - `sql-developer` agent

A builder for SQL that comes before Power BI and Fabric: views, queries over
existing views, performance tuning, and explaining existing SQL. Until now, SQL
authoring went to `implementer`, which has no rules about grain, proving a
rewrite, or keeping away from a live database.

- **New agent `sql-developer`** (`implement`, 30 turns). T-SQL by default, with
  notes on the narrower Fabric Warehouse / SQL analytics endpoint surface. It
  reads view definitions before building on them, puts a grain/source/filters
  header on every view, and shapes views for a star schema (explicit types, no
  `ORDER BY`, `SELECT *` or `NOLOCK`). A tuning counts only with a before and
  after measurement, and proof of the same result: row count, `EXCEPT` both
  ways, and column totals.
- **Read-only against databases.** It never runs DDL or DML. Views and index
  recommendations are delivered as scripts for the user to deploy, unless the
  brief names a dev database and allows deploying there.
- **Review stays with `data-model-reviewer`**, which already covers SQL. This
  agent's explanations mark suspect logic as unconfirmed and send serious items
  there. `data-model-reviewer` got five view-specific checks: `DISTINCT` covering
  a fan-out, `datetime` end-of-range, `COUNT(col)` versus `COUNT(*)`, a `WHERE`
  that turns a `LEFT JOIN` into an inner join, and a stated grain the joins
  don't keep.
- Under `-Preset work` it follows `implement` to Gemini 3.7 Flash in Copilot.
  Add a `role_overrides` entry in `policy.local.json` if work SQL should stay on
  Claude.
- Driven by a request, not a report: there is no build evidence yet. The turn
  cap and pacing copy the builders' settled rules.

## 2026-10-01 - Config-only work clone

Run the kit on a work machine without carrying files between machines.

- **`"config_only_clone": true`** in `registry/policy.local.json` marks a clone
  that only pulls. `build.ps1` then stops if `git status` shows any change
  outside the gitignored files, names them, and says how to undo them.
  `-AllowTrackedChanges` builds anyway. In such a clone, the SUBSTITUTED
  message points at `policy.local.json`, not `policy.json`.
- **`docs/feedback/local/`** (gitignored except its README) collects session
  reviews. The installed policy has a "Session reviews" section: when asked for
  a review, a session also writes it there, in a fixed shape, with clients,
  people and internal figures kept generic. `install.ps1` fills in the folder's
  path.
- `AGENTS.md` has an "In a config-only clone" section: only the local files
  change, and model update lists are applied through `set-availability -Local`
  and `role_overrides`. `docs/vscode-copilot-setup.md` no longer says to copy
  the local files from home.
- Not done: a local model catalogue. New models come from the public catalogue
  refresh, and the work list is narrower than the public one.

## 2026-09-28 - Five session reviews
source: [`docs/feedback/2026-09-28-sr2-five-session-reviews.md`](docs/feedback/2026-09-28-sr2-five-session-reviews.md)

Across five sessions, the routing, tiers and review gates held, and almost every
run finished first time. The waste was in over-delegating small work, in brief
facts nobody checked, and in two rules the orchestrator skipped again (Opus for
diagnosis, hand-off at a gate).

- **Context meter hook** (`hooks/context-meter.ps1`, `UserPromptSubmit`,
  installed with `-WithInstructions`). On each user message it adds the main
  session's context size and total input read, from the transcript's usage
  figures, and hand-off advice above 100k and 150k. Tested in Claude Code
  2.1.283 against this repo's own session transcript and a live session. The
  session also gets real figures for its team line, which every report said it
  lacked.
- **Run sizing:** a stated floor of 50-70k per run; trivial, fully specified
  edits batched into one run; edits in ranges already read done by the
  orchestrator; "split fix batches" narrowed to fixes that need thought.
- **Small helper exception** to "a new shared helper is its own step".
- **Checked facts only in briefs**, and verified/unverified marks on data values
  in resume notes. Names and layout settled with the user before a run. Briefs
  say who else is running.
- **Deleted or replaced IDs** are a shared change: recon lists every reference.
  `pbir-builder`'s self-check fails on a dangling one.
- **Performance and memory:** get the real query from Performance Analyzer
  first; diagnose one visual (or one measure tree) per run on the default model;
  an Opus brief must name its fix. A pre-publish check runs the heaviest
  visuals' real queries against the service's memory limit.
- **Review:** proven-equal rewrites and position-only changes may skip review,
  named in the Skipped line. "Plausible, needs rendering" findings become Desktop
  checks. An approved fix may be proved and deployed in one run.
- **Smaller:** screenshots are crops of the visual; reusable scripts live in the
  project; direct TMDL edits only with Desktop closed and text-only;
  `model-builder` checks its export paths and points the reviewer at the
  project's own TMDL for the old version.
- **Project fixes, not kit:** the `sr2_common` helper merge trap, `validate.py`
  exit codes and schema noise, the `backup_report.py` naming, the tableEx
  image-fit rule, and keeping the save-diff script.

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
