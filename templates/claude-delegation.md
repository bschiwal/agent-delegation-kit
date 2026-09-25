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
- **It needs a tool only this session has.** Desktop screenshots and visual
  checks, Fabric and other non-Power BI MCP servers, skills, email and docs stay
  here. Delegate the parts around them: recon before, review after.

**Power BI model work is delegable.** Before any semantic model work, connect this
session to the model (`connection_operations` `ListLocalInstances`, then
`Connect`). The Power BI MCP server is shared, so `model-builder` and
`data-model-reviewer` use your connection without reconnecting. Then:

- Model changes (measures, tables, columns, relationships) and the DAX tests that
  prove them go to `model-builder`. It writes each expression once, into the live
  model, and exports TMDL for review.
- `data-model-reviewer` reads that export, and settles its own data assumptions
  with read-only queries.
- You keep the decisions and the Desktop save. Don't re-run the builder's tests or
  read back its measures. Its reply already has the results.
- It is conversation: clarifying, deciding, explaining.

**Plan only.** If the user asks for a plan, a proposal, or "what would you do",
return the delegation plan - step, agent, what it receives and returns, which
steps run in parallel - and run nothing until they say go.

## Opus for hard build steps

Builders run on the `implement` model, which handles a settled, single-focus
spec well. You may pass `model: "opus"` on a builder call, with no need to ask,
for a step that is reasoning more than typing:

- the plan flags it as needing strong reasoning (new calculation logic, a rule
  with several interacting conditions);
- a batch of fixes that interact and cannot be split into separate runs;
- a second attempt at a fix the default model did not land.

Opus reads cached context at the same price and costs about twice as much for
fresh input and output, so it pays off only when it saves a failed run or a
resume. A batch that *can* be split goes out as separate default-model runs
instead. Mark Opus runs in the team line: `model-builder [opus] (92k)`.

## Fable is by request only

Each agent runs on the model its definition names. Passing `model: "fable"` on an
Agent call overrides that, at about twice the per-token price of Opus, so do it only
in one of two cases:

- **The user granted it in this request** - "it's ok to use Fable if you need it".
  The grant is permission, not an instruction. Use Fable only where it is likely to
  change the outcome: `architect` on a hard design, `debugger` after a fix that did
  not hold, a review where a miss is expensive. Builders working to a settled spec
  and the cheap roles stay on their defaults. A grant covers the request it was
  given in. A later request needs a new one.
- **You asked and the user said yes.** If Fable would clearly improve a step and
  there is no grant, ask with `AskUserQuestion`: one question, header `Fable?`,
  that names the step and gives the reason in a sentence - "I think `architect`
  will give a better design on this with Fable. Shall we use it?" Options
  `No, keep the default model` and `Yes, use Fable`, in that order. Ask once per
  request, after recon and before the runs start, and put every step you would
  escalate into that one question. Do not interrupt a run midway to ask.

Anything other than the `Yes` option - No, a typed answer, a dismissed or
unanswered question, an unattended run - means no. Proceed on the default model and
do not ask again for that step. A request that rules Fable out ("don't use Fable")
settles it with no question.

A hook enforces this (`.claude/hooks/fable-gate.ps1`). A Fable call with no grant
and no Yes answer raises a permission prompt, and one the user ruled out is denied.
If you are denied, run the agent on its default model. Do not retry with Fable.

Mark Fable runs in the team line: `architect [fable] (48k)`.

<!-- INCLUDE:delegation-core -->

## One session per build pass

Your context is the biggest cost in a long build, and it only grows. When a
multi-pass build reaches a gate - a pass is built and reviewed, and the next
needs a user decision or a Desktop check - stop there. Write or update a resume
note (`.claude/plans/<task>-resume.md`: what is done, what is open, the next
step and its inputs), and tell the user the next pass should start in a new
session from that note. A fresh session reading a one-page note costs far less
than this one carrying every earlier screenshot, query and diff.

## Background runs

You are the main session, so you are notified when a background agent finishes.
Launch independent agents in the background (`run_in_background: true`) and keep
working - for example, update docs or run your own live-model checks while the
builders and the reviewer run. Use the foreground only when your very next step
needs that agent's result.

## Report

- **One merged answer**, not a relay of each agent's output.
- **End with the team line** whenever agents ran - the chain, with each run's
  tokens, for example
  `Team: repo-scout (8k) -> pbir-builder x2 (92k, 61k) -> data-model-reviewer (57k)`.
- **Name skipped steps.** If the policy called for recon, design or a review and
  you did it yourself or skipped it, add `Skipped: <step> - <why>`. A code change
  with no reviewer in the team line needs that line.
- **Report honestly.** If a run failed, hit its limit, a check did not run, a
  review was skipped or tests were not run, say so.
