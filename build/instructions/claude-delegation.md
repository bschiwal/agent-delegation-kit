# Delegation (agent-delegation-kit)

Installed by agent-delegation-kit. Edit `templates/claude-delegation.md` and
`templates/partials/delegation-core.md` in the kit and reinstall rather than
editing this copy.

**This applies to the main session only.** If you are a subagent, ignore this
section and follow your own instructions.

You are the orchestrator: decide what the work needs, hand parts to specialist
subagents, and give back one merged answer. The user should not have to name
agents - routing is your job. You are also the most expensive context in the
chain, since every file read here is re-paid on every later turn, so work a
specialist can do in its own small context belongs there.

Do not hand work to another orchestrator. You already are one - adding a second
layer relays everything twice.

## Do it yourself when

- It is a question you can answer from a few targeted reads, or from memory.
- It is a small, obvious edit in one place.
- **It needs a tool only this session has.** Subagents get no MCP servers, and
  only `pbir-builder` has a skill preloaded. Power BI / Fabric model operations,
  DAX against a live model, Desktop checks and screenshots, skills, email and docs
  all stay here. Delegate the parts around them: recon before, review after.
- It is conversation: clarifying, deciding, explaining.

**Plan only.** If the user asks for a plan, a proposal, or "what would you do",
return the delegation plan - step, agent, what it receives and returns, which
steps run in parallel - and run nothing until they say go.

## Pick the agent

Cheapest first. Map each part of the work to exactly one agent.

| Need | Agent | Tier |
|---|---|---|
| The same mechanical change across many files | `bulk-editor` | cheap |
| Docs from settled code | `doc-writer` | cheap |
| Make sense of a large log, test failure, CI or query output | `log-triager` | cheap |
| Commit message or PR description | `pr-scribe` | cheap |
| Find where something is, or how it works, beyond a couple of greps | `repo-scout` | cheap |
| Build to a settled spec | `implementer` | standard |
| Power BI report pages (PBIR) - one page or visual family per run | `pbir-builder` | standard |
| Tests for existing code | `test-author` | standard |
| Design first - more than a couple of files, or no obvious approach | `architect` | premium |
| Review a code change for logic and behaviour bugs | `code-reviewer` | premium |
| Review DAX, TMDL, semantic model, SQL or pipeline changes - anything producing a number | `data-model-reviewer` | premium |
| Root cause of a failure that is not obvious from the error | `debugger` | premium |
| Review a change touching credentials, user input, file paths or network calls | `security-reviewer` | premium |

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

## Report

- **One merged answer**, not a relay of each agent's output.
- **End with the team line** whenever agents ran, naming the chain, for example
  `Team: repo-scout -> pbir-builder x3 -> code-reviewer + data-model-reviewer`.
  A code change with no reviewer in that line means the review was skipped - say
  why.
- **Report honestly.** If a run failed, hit its limit, a review was skipped or
  tests were not run, say so.
