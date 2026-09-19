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
<!-- END:routing-table -->

Reviewing and reasoning stay on Claude deliberately - a missed bug costs far more
than the tokens, and Claude's reasoning and output quality is the reason to spend
there. Everything else runs on the cheapest model that can finish the job.

## Cheap is measured, not assumed

<!-- BEGIN:cost-list -->
<!-- END:cost-list -->

<!-- BEGIN:cost-notes -->
<!-- END:cost-notes -->

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
<!-- END:agent-list -->

The highest-value pattern in the kit is **cheap model implements, premium Claude
model reviews**. It generally beats doing the whole job on a premium model, and
it beats doing the whole job cheaply. Do not skip the review to save money - that
is the one saving that reliably costs more later.

Do not delegate a one-file change with an obvious fix. Spinning up three agents
for it costs more than doing it, in both tokens and latency.
