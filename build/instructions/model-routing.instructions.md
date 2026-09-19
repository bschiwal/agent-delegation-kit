---
name: 'Model routing and delegation'
description: 'Which model to use for which kind of work, and when to hand off to a specialist agent.'
applyTo: '**'
---

# Model routing

Installed by [agent-delegation-kit](https://github.com/BSchiwal/agent-delegation-kit).
Regenerate from `registry/policy.json`; do not hand-edit this file.

## Pick the model from the kind of work, not the size of the task

<!-- BEGIN:routing-table -->
| Kind of work | Model |
|---|---|
| Correctness, security and architecture review. Judgement work where a missed bug costs more than the tokens. | **Claude Opus 5** (fall back: Claude Opus 4.8, Claude Opus 4.7, GPT-6 Astra) |
| Planning, architecture design, tricky debugging, ambiguous tradeoffs. | **Claude Opus 5** (fall back: Claude Opus 4.8, GPT-5.6 Sol) |
| Front door for a request: classify it, route each part to a specialist agent, sequence the handoffs, merge the results. | **Claude Sonnet 5** (fall back: GPT-5.3-Codex, Gemini 3.7 Flash) |
| Write real code against a clear spec. Needs competence, not brilliance. | **Claude Sonnet 5** (fall back: GPT-5.3-Codex, Gemini 3.7 Flash) |
| Mechanical, verifiable changes - renames, import fixes, formatting, codemods, boilerplate. | **MAI-Code-1.1-Flash** (fall back: GPT-5.6 Luna, Gemini 3.7 Flash) |
| Locate code, trace usages, answer where-is questions. Read-only reconnaissance. | **GPT-5.6 Luna** (fall back: Gemini 3.7 Flash, MAI-Code-1.1-Flash) |
| Condense logs, diffs, docs, meeting notes, test output into something a human or a premium agent can read. | **GPT-5.6 Luna** (fall back: Gemini 3.7 Flash) |
| Docs, READMEs, commit messages, PR descriptions, changelogs. | **GPT-5.6 Luna** (fall back: Gemini 3.7 Flash, Claude Haiku 4.5) |
<!-- END:routing-table -->

Reviewing and reasoning stay on Claude deliberately - a missed bug costs far more
than the tokens, and Claude's reasoning and output quality is the reason to spend
there. Everything else runs on the cheapest model that can finish the job.

## Cheap is measured, not assumed

Per 1M tokens, blended as `0.8 x input + 0.2 x output` (agent turns are
input-heavy):

<!-- BEGIN:cost-list -->
- GPT-5.6 Luna - **0.40**
- MAI-Code-1.1-Flash - **0.40**
- Gemini 3.7 Flash - **1.35**
- Claude Haiku 4.5 - **1.80**
- Claude Sonnet 5 - **3.60**
- GPT-5.3-Codex - **4.20**
- GPT-5.6 Sol - **7.20**
- Claude Opus 5 - **9.00**
- Claude Opus 4.7 - **9.00**
- Claude Opus 4.8 - **9.00**
- GPT-6 Astra - **18.00**
<!-- END:cost-list -->

Two consequences that trip people up:

1. **Claude Sonnet 5 is cheaper than GPT-5.4, GPT-5.5, GPT-5.6 Sol and Gemini
   3.5 Flash.** Swapping Sonnet 5 out "to save money" in favour of one of those
   costs more, not less. The old advice to avoid Sonnet was written against
   Sonnet 4 at $3/$15; Sonnet 5 is $2/$10.
2. **Claude Opus 5 is cheaper than GPT-5.5 and GPT-6 Astra.** If the work genuinely
   needs a frontier model, Opus 5 is the economical frontier choice.

Never pick a model that is both worse and pricier than an alternative. Claude
Sonnet 4.6, Gemini 3.5 Flash and GPT-5.5 are all dominated by something cheaper.

## Fewer tokens beats a cheaper model

Most overspend is context, not price per token. Before reaching for a cheaper
model, do these - they save more:

- **Summarise before escalating.** Run a cheap pass over the 50,000-token build
  log and hand the premium model the 500 tokens that matter.
- **Search, do not read.** Grep and read line ranges. Do not read whole files, and
  do not read a directory to "get oriented".
- **Give concrete paths.** Naming `src/client/options.ts:42` costs a few tokens;
  making the model rediscover it costs thousands.
- **One task per session.** Unrelated work in one long thread means every later
  turn re-pays for all the earlier context.
- **Stop when the answer is found.** Completeness for its own sake is pure cost.

## Delegate rather than doing everything inline

When a specialist agent from this kit fits the task, hand off to it - it already
carries the right model and the right instructions:

<!-- BEGIN:agent-list -->
`architect` `bulk-editor` `code-reviewer` `data-model-reviewer` `debugger` `doc-writer` `implementer` `log-triager` `pbir-builder` `pr-scribe` `repo-scout` `security-reviewer` `test-author` `triage-lead`
<!-- END:agent-list -->

The highest-value pattern in the kit is **cheap model implements, premium Claude
model reviews**. It generally beats doing the whole job on a premium model, and
it beats doing the whole job cheaply. Do not skip the review to save money - that
is the one saving that reliably costs more later.

Do not delegate a one-file change with an obvious fix. Spinning up three agents
for it costs more than doing it, in both tokens and latency.
