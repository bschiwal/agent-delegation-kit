## Pick the agent

Cheapest first. Map each part of the work to exactly one agent.

<!-- GENERATE:roster -->

## The cost model

Cost is **turns x context**. Each API call re-reads the caller's whole context, so
a subagent that runs 50 turns over an 80K-token context costs about 4M tokens,
whatever it produces - and a run that hits its turn limit is paid for again when it
is resumed. Every rule below keeps either turns or context small.

## Size every run to finish

- **One page, one measure group, one module per run.** Never "the whole report"
  or "all the TMDL". Several small parallel runs cost less than one long run,
  because each call re-reads a smaller context and nothing hits the turn limit.
- **Many similar files means a generator.** The brief says "write and run a
  script that generates these from the spec", not "write these files".
- **Plans go to disk.** `architect` writes `.claude/plans/<task>.md` and returns
  the path and a short summary. Hand builders the path and the step number - do
  not paste the plan into a brief.
- **Foreground only.** Launch subagents with `run_in_background: false` and wait
  for them. Ending your turn while children run means being resumed later, after
  the prompt cache has expired.
- **Resume, don't restart.** If a run stops partway, resume it with what it
  already produced. Re-running the same brief from scratch pays for it twice.

## Sequence it

1. **Recon first, cheaply.** Unknown location: `repo-scout` before anyone
   expensive starts. Big error dump: `log-triager` before `debugger`.
2. **Design if it is not obvious** - `architect` before any builder.
3. **Build** - the builder that fits, sized as above.
4. **Review** - below. Always, for code.
5. **Fix** - confirmed findings go back to the builder (or `debugger`), then
   re-review only what changed. Stop after two rounds and report what is open.

Run independent parts in parallel - separate pages, or two reviewers on one diff.
Keep dependent steps sequential.

## Review what is reviewable

Every non-trivial code change is reviewed before you call it done - cheap build
plus premium review is the point of this kit, and skipping review is the one
saving that reliably costs more later. Send it once, and scoped:

- `code-reviewer` for logic and behaviour.
- `data-model-reviewer` for DAX, TMDL, semantic models, SQL and pipelines - only
  those files. Non-additive measures summed over time, fan-out joins and
  filter-context bugs are what it is built to catch.
- `security-reviewer` for credentials, user input, file paths or network calls.

Name the exact files or diff range in the brief. **Do not send generated or
validator-checked output** - PBIR JSON that passed `powerbi-report-author
validate`, build output, lock files. Send the generator and its spec instead. On
round two send **only the files that changed**.

## Hand-offs

Each delegation gets a self-contained brief - the agent sees only what you send:

- **Goal** - one or two sentences.
- **Where** - exact `file:line` locations from recon. Never make an agent
  rediscover what recon already found.
- **Constraints** - conventions, what not to touch, how to verify.
- **Done looks like** - the concrete output you need back.

Paths and line ranges, never pasted file contents.
