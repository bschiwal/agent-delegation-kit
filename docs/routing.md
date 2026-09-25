# Why the routing policy is what it is

The short version: **model quality pays for itself when judging, and is largely
wasted when producing.** So reviewing and reasoning get the best Claude model,
and everything else gets the cheapest model that can finish the job.

This document explains the reasoning so you can disagree with it deliberately
rather than by accident.

## The five principles

### 1. Reviewing is where quality pays for itself

A review agent's entire output is judgement. There is no mechanical part to it -
you are paying for the model's ability to notice that an `if` branch leaves a
transaction open on the error path. A missed bug costs hours of debugging and
sometimes a bad number in front of a client; the review that would have caught it
costs cents.

So every review role runs on Claude Opus 5, the highest merit score in the
catalogue, and cost is not a consideration there.

The non-Claude fallback on a review role is GPT-6 Astra, which is the only other
model rated equal on merit. It sits last, and it is an *availability* backstop,
not a saving - it costs roughly twice what Opus 5 does. If GPT-6 Astra were
clearly better than Opus 5 at finding bugs, it would be first; on the evidence of
actually reading both models' review output, it is not.

### 2. Producing is where money leaks

Writing code to a settled spec, applying a codemod, searching a repo, condensing a
log - these are bounded tasks with a checkable result. A cheaper model that gets
there is worth exactly as much as an expensive one that gets there. This is where
the volume is, and therefore where the spend is.

### 3. Cheap is measured, not assumed

This is the principle most often violated, usually by a policy written against
last year's prices.

Blended cost per 1M tokens, `0.8 x input + 0.2 x output`:

| Model | Blended | Merit |
|---|---:|---:|
| GPT-5.6 Luna | 0.40 | 3.0 |
| MAI-Code-1.1-Flash | 0.40 | 2.5 |
| GPT-5.4 nano | 0.41 | 2.0 |
| GPT-5 mini | 0.60 | 2.5 |
| Gemini 3.7 Flash | 1.35 | 3.0 |
| Claude Haiku 4.5 | 1.80 | 3.0 |
| Grok 4.6 | 2.80 | 3.5 |
| Claude Sonnet 5 | 3.60 | 4.0 |
| GPT-5.6 Terra | 4.00 | 4.0 |
| GPT-5.3-Codex | 4.20 | 4.0 |
| GPT-5.4 | 5.00 | 3.5 |
| GPT-5.6 Sol | 7.20 | 4.5 |
| Claude Opus 5 | 9.00 | 5.0 |
| GPT-5.5 | 10.00 | 4.0 |
| GPT-6 Astra | 18.00 | 5.0 |

Read that table before assuming which vendor is the cheap one:

- **Claude Sonnet 5 (3.60) is cheaper than GPT-5.4 (5.00), GPT-5.5 (10.00),
  GPT-5.6 Sol (7.20) and Gemini 3.5 Flash (3.00 at lower merit).** A rule that
  says "use GPT instead of Sonnet to save money" makes the bill go *up* against
  most of the GPT line.
- **Claude Opus 5 (9.00) is cheaper than GPT-5.5 (10.00) and GPT-6 Astra
  (18.00)**, at equal or higher merit than both.
- The actual cheap tier is around $0.20 input: GPT-5.6 Luna,
  MAI-Code-1.1-Flash, GPT-5.4 nano, GPT-5 mini. Those are the models worth
  routing bulk work to, and the kit does.

Why blend at 0.8/0.2 rather than quote the headline output price? Because an agent
turn is dominated by input - the system prompt, the file contents, the tool
results, the conversation so far - while output is usually a short patch or a
paragraph. Ranking by output price alone badly misprices models like GPT-5.3-Codex
($1.75 in, $14.00 out) that look cheap on input and are not. Adjust the weights in
`scripts/build.ps1` if your workload skews differently.

#### Never pick a dominated model

Some models are both worse and pricier than an alternative. These are flagged in
`registry/models.json` and should never appear in a role:

- **Claude Sonnet 4.6** ($3/$15) - Sonnet 5 is better and cheaper.
- **Gemini 3.5 Flash** ($1.50/$9) - 3.6 and 3.7 are better and cheaper.
- **GPT-5.5** (10.00) - costs more than Opus 5 at lower merit.
- **Grok 4.5** - superseded by 4.6 at identical price.

### 4. Cost is turns times context

Every API call re-reads the calling agent's whole context. A subagent that runs
50 turns over an 80K-token context costs about 4M tokens, whatever it produces,
and a run cut off at its turn limit gets paid for again when it is resumed.

This was learned the expensive way. On 2026-09-18 one Power BI report build used
56M tokens across 22 agent runs, which was a full 5-hour usage window plus $25.
93% of it was cache re-reads. The audit's findings, and what changed because of
them:

| Finding | Change |
|---|---|
| 9 of 22 runs stopped exactly at `maxTurns` and had to be resumed or re-run | Lower caps (implementer 50 -> 25, reviewers 30 -> 20), plus a generated turn-budget footer on every agent: hand back partial results at 75% |
| Implementers edited PBIR JSON one visual per turn: 11 runs, 30M tokens | `pbir-builder`: one page per run, writes and runs a generator, validates with the CLI, preloads the report-authoring skill |
| `triage-lead` sat under an Opus main session that already orchestrated, couldn't reach the Power BI tools, and stopped with background children still running | The main-session policy never hands off to `triage-lead`; `triage-lead` hands back MCP-dependent work and delegates in the foreground only |
| 8 reviewer runs on Opus `xhigh` cost 10.5M, including a full re-review and a review of already-validated JSON | Review effort `xhigh` -> `high`; each reviewer prompt says to review only named files, only the changes on round two, never generated output, and to stay in its own area |
| The architect returned a 5K-word plan as text, which was written to disk again and then carried in the main context | The architect writes `.claude/plans/<task>.md` early and replies with the path plus 10 lines |

A follow-up build on the same model, after those changes, used about 210K tokens
across three subagent runs. None of them came near its turn limit, and the
reviewer caught two real bugs. With the subagents that lean, **the orchestrator's
own context became the biggest cost**: about 60 turns over a context above 100K
tokens. It had read four large files for recon and pulled validator JSON and query
dumps straight into its context. The shared delegation rules now open with "keep
your own context small", and the builder and reviewer gaps that run exposed are
fixed:

- baseline validation in `pbir-builder`, and re-runnable, surgical patch scripts
  for existing pages;
- a "known and accepted issues" field in every brief;
- a "needs live check" list in `data-model-reviewer` for unverified data
  assumptions;
- reviews that run as soon as their inputs are settled, instead of after the build.

A test after that run confirmed two things, using an agent with unrestricted
tools. A subagent can use the Power BI modeling MCP, and it **shares the main
session's live connection** (same connection and session ID, no reconnect). The
eight modeling tool definitions add roughly 7K tokens per call. That made
`model-builder` worthwhile: model changes and their DAX tests leave the main
session, each expression is written once into the live model, and TMDL is
exported for review. `data-model-reviewer` got the read-only DAX tool, so it can
settle its own data assumptions.

The model routing was never the problem. Each agent ran the
model it was meant to. The problem was how many turns each run took, over how much
context.

A third build (2026-09-24/25, 21 subagent runs, about 2.65M subagent tokens) was
lean per run, about 120K each, but 16 of 21 runs hit the 25-turn cap, 20 stops
in all. The cap was no longer a safety net; it was where runs ended. The runs
did not wander. Builders spent their early turns reading long plans and kept a
DAX transaction open while they tested. What changed:

| Finding | Change |
|---|---|
| 16 of 21 builder runs stopped at 25 turns; three page builds spent their first run only reading | `model-builder` and `pbir-builder` go to 40 turns (the others stay put), with checkpoints in the definitions: something written by turn 8, committed or validated by turn 30 |
| Builders read a 1,400-line plan, a mockup and the generator before writing | `architect` writes a separate spec file for any long build step; the orchestrator gives a builder its step, not the plan |
| A long-open transaction caused a spurious error; two runs stopped with one still open | `model-builder` keeps transactions short, commits before testing and never hands back with one open |
| A `CROSSJOIN` test harness gave wrong counts and nearly blocked a correct fix | `model-builder` and `data-model-reviewer` test the way a visual queries: `TREATAS` or `SUMMARIZECOLUMNS`, never `CROSSJOIN` grids |
| The default model applied none of a seven-item fix batch, but landed single fixes | Fix batches are split into single-focus runs. The main session may put a builder on Opus for a batch that cannot be split, or for a plan step flagged as hard |
| With the PBIR schema unreachable, validation passed three structural errors that Desktop rejected | `pbir-builder` scripts end with a structural self-check (`expr` wrappers, selector-less default entries), and an unreachable schema is reported as "validation incomplete" |
| Builders skipped spec items and reported them only as deviations | A required **Spec items not built** section in both builders' replies |
| A report-level filter change broke five existing pages, and the plan had accepted it | Plans list the impact of every shared change, and the orchestrator checks it before the step runs |
| A fresh 93K run with a 15-line brief beat resuming a 190K run | Resume only a run that is nearly done on a modest context; otherwise start fresh with a narrow brief |
| The orchestrator's context was again the largest cost | One session per build pass, with a resume note at each gate |

Raising the cap is not a reversal of the first audit. Then, runs hit a 50-turn
cap because they edited one visual per turn. Now they hit a 25-turn cap while
doing the right work, and each stop cost an orchestrator turn and a resume. The
checkpoints are what keep 40 turns from turning into 40 turns of reading.

### 5. Fewer tokens beats a cheaper model

Substituting a model changes the price per token by maybe 5x. Cutting the context
in half cuts the bill in half *and* usually improves the answer. The second lever
is bigger and it is the one people ignore.

This is why the kit's cheap agents are shaped the way they are:

- `log-triager` exists so a premium agent never reads 50,000 tokens of build
  output. Compressing that to 500 tokens before escalating saves more than every
  model swap in this document combined.
- `repo-scout` is told, repeatedly, to return `file:line` citations and not file
  contents. An agent that dumps what it read has defeated its own purpose.
- `architect` is told to put concrete paths and signatures in its plan, so the
  implementer does not re-discover them.
- Read-only agents get no write tools; mechanical agents get `effort: low`,
  `omitClaudeMd: true` and a turn cap. Every one of those is a token reduction.

## The combination that actually wins

**Cheap model implements, Claude reviews.** `implementer` then `code-reviewer`.

This beats doing the whole task on a premium model, because the premium model's
judgement is spent on the part that needs judgement rather than on typing. It also
beats doing the whole task cheaply, because the cheap model's mistakes get caught.

The one saving never worth taking is skipping the review. A bug that reaches main
costs more than every token the review would have used.

## When to override

Move a role up a tier when:

- The cheap model has failed the same task twice. Two failures means it cannot do
  this, not that it needs a third try.
- The task turns out to need judgement you did not anticipate - an ambiguous spec,
  a design decision buried in what looked like a mechanical change.
- A human is blocked waiting on the answer. Latency has a cost that does not
  appear in the price table. (This is the only honest use for
  `Claude Opus 4.8 (fast mode)`, which is twice the price of plain Opus 4.8 and
  buys speed, not quality.)

Move a role down a tier when:

- You are running the same verified operation across many files.
- The output is fully checkable by tests, a type checker, or a grep.

## Where these numbers come from

`registry/models.json`, refreshed from
[GitHub's pricing docs](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
by `scripts/refresh-models.ps1`.

Prices, vendors and release status are scraped. **`merit` is not** - it is a
hand-maintained 1-5 judgement of quality ignoring price, and it is the opinionated
part of this repo. Re-tune it when your own experience disagrees; the refresh
script will never overwrite it.

Note also that GitHub moved to usage-based billing on 2026-06-01. The older
"premium request multiplier" model only still applies to Pro/Pro+ annual plans
that stayed on request-based billing. If your org still talks in multipliers, the
per-token numbers above are not what you are being billed on - check which scheme
you are on before optimising against the wrong one.
