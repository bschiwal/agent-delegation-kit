# Why the routing policy is what it is

The short version: **model quality pays for itself when judging, and is largely
wasted when producing.** So reviewing and reasoning get the best Claude model,
and everything else gets the cheapest model that can finish the job.

This document explains the reasoning so you can disagree with it deliberately
rather than by accident.

## The four principles

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

### 4. Fewer tokens beats a cheaper model

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
