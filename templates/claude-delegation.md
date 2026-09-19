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

<!-- INCLUDE:delegation-core -->

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
