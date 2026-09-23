# Claude Code and Claude Desktop setup

Claude Desktop runs the same Claude Code engine as the CLI and reads the same
config folder, so **one install covers both**. There is no separate Desktop step.

## 1. Get Claude Code

If you already use the `claude` CLI or the Claude Desktop app, skip this.

- **Desktop app** (Windows/macOS): download from
  [claude.ai/download](https://claude.ai/download). Claude Code is built in.
- **CLI**: `npm install -g @anthropic-ai/claude-code`, then run `claude` once and
  sign in.
- **VS Code extension**: install `anthropic.claude-code` from the marketplace. It
  drives the same engine and the same agents.

Check it works:

```powershell
claude --version
```

## 2. Install the agents

```powershell
git clone https://github.com/BSchiwal/agent-delegation-kit.git
cd agent-delegation-kit
.\scripts\install.ps1 -Target claude
```

This writes the agent files to `~\.claude\agents\`, which makes them available in
every project on the machine. That's 15 agents, or 14 with `-WithInstructions`,
which skips `triage-lead` because the session itself orchestrates (see below).

If PowerShell refuses to run the script:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 3. Confirm

Restart Claude Code (in VS Code: `Ctrl+Shift+P` -> *Developer: Reload Window*;
in the Desktop app, quit and reopen). Agents are read when a session starts, so an
already-open session will not see them.

Then ask:

```
> which subagents do you have available?
```

You should get `code-reviewer`, `architect`, `repo-scout` and the rest. Current
Claude Code has no `/agents` wizard - it was removed - so asking, or listing the
folder, is how you check:

```powershell
Get-ChildItem ~\.claude\agents
```

Each file's frontmatter shows its model: reviewers say `opus`, `repo-scout` and
the other cheap agents say `haiku`.

## 4. Use them

Two ways:

```
> use code-reviewer on this branch
> review this diff for bugs
```

The second works because Claude reads each agent's `description` and delegates on
its own. You mostly do not have to name them.

To edit an agent, change its source in `registry/agents/` and re-run the install -
not the installed copy, which the next install overwrites.

To run several at once, ask for it - *"have code-reviewer and security-reviewer
both look at this branch"* - and they run in parallel, each in its own context.

## Project-scoped install

To commit the agents into a specific repo so everyone working on it gets them:

```powershell
.\scripts\install.ps1 -Target claude -Scope project -Path C:\repos\my-app
```

That writes to `<repo>\.claude\agents\`. Project agents take precedence over your
user-level ones with the same name, so a repo can specialise an agent without
affecting your other work.

Note that VS Code's Copilot also reads `.claude/agents`, so a project-scope Claude
install makes these agents visible in Copilot too - usually convenient, but worth
knowing.

## Make every session a triage lead

To have every new session orchestrate the agents itself, so you never have to name
one:

```powershell
.\scripts\install.ps1 -Target claude -WithInstructions
```

With this installed, the installer leaves out `triage-lead` (and removes it if it
was installed before). The session is already the orchestrator, and stacking a
second one underneath it relays everything twice. `triage-lead` stays the
orchestrator for Copilot and for Claude Code installs without this flag. Once the
policy is in `CLAUDE.md`, a later plain reinstall still leaves `triage-lead` out.

That copies the delegation policy to `~\.claude\agent-delegation.md` and adds one
marked import block to `~\.claude\CLAUDE.md`:

```
<!-- agent-delegation-kit:begin -->
@~/.claude/agent-delegation.md
<!-- agent-delegation-kit:end -->
```

The install only ever adds or removes that block. Anything else in your
`CLAUDE.md` is left alone, a reinstall does not add a second copy, and
`-Uninstall` removes the block and the policy file.

### Fable by request only

`-WithInstructions` also installs a Fable gate. Subagents run on the model their
definition names, and the session never escalates one to Fable (about twice Opus
per token) unless you allow it:

- **Grant it in the request.** "Redesign the loader - it's ok to use Fable if you
  need it." The session uses Fable only on the steps where it is likely to matter,
  and marks them in the team line.
- **Or answer its question.** Without a grant, the session may ask once per
  request: "I think `architect` will give a better design on this with Fable.
  Shall we use it?" Only `Yes, use Fable` counts. No, a typed answer or a
  dismissed question all mean no, and it carries on with the default model.
- **Or rule it out.** "Don't use Fable" in the request blocks it outright.

The policy text tells the session this. A `PreToolUse` hook enforces it:
`~\.claude\hooks\fable-gate.ps1`, registered on the `Agent` tool in
`~\.claude\settings.json`. For project scope it goes in `.claude\settings.local.json`,
because the command holds an absolute path. The hook reads the transcript and
checks only your latest request and any answers since. If it finds a grant or a
Yes, it stays out of the way. If you ruled Fable out, it denies the call.
Otherwise it raises Claude Code's permission prompt. There is no timeout, so an
interactive session waits for you. An unattended run (`claude -p`, the SDK) has
nobody to approve, so it stays on the default model.

The installer changes only its own hook entry and leaves the rest of
`settings.json` alone. It keeps the previous file as `settings.json.kit-backup`.
Windows PowerShell's JSON writer does re-indent the file. `-Uninstall` removes the
entry and the script.

Switching the main session itself to Fable (`/model`) is your call and is not
gated.

**Why instructions rather than `"agent": "triage-lead"` in settings.** Setting an
agent as the default main session replaces Claude Code's built-in system prompt,
limits the session to that agent's tools, and switches the session to that agent's
model. For `triage-lead` that means Sonnet with no Bash, no Edit, no MCP servers
and no skills in every project. The instructions route work the same way while the
main session keeps Opus, all its tools, MCP, skills and memory.

## Power BI model work

Two agents can reach a live Power BI model through the Power BI modeling MCP:
`model-builder` makes changes, and `data-model-reviewer` can run read-only DAX. The
MCP server is shared across the session, so **connect the main session to the model
first** and the agents use that connection without reconnecting. A good opening
line for a model session:

```
> connect to the model I have open in Power BI Desktop
```

`model-builder` checks that the open connection matches the model named in its
brief, and stops if it doesn't rather than connecting on its own. It works inside a
transaction, tests every change with small DAX queries, and exports TMDL to
`.claude/review/` for the reviewer. You still save in Desktop, which is what
updates the project's own definition folder.

Adding the MCP tools costs roughly 7K tokens per call for `model-builder`, and
about 1K for the reviewer's single DAX tool. Both agents also work in Copilot -
see [vscode-copilot-setup.md](vscode-copilot-setup.md#power-bi-model-agents).

**If Desktop restarts, the connection goes stale.** It comes back on a new port,
and calls fail with "connection is not open". `model-builder` spots this and tells
you to reconnect. Just say "reconnect to the model".

If `model-builder` reports it has no Power BI tools, the MCP server is registered
under a different name on this machine. Fix `claude_prefix` in `registry/mcp.json`
(check the real prefix with `/mcp`), then reinstall.

Everything else that needs a main-session tool - Desktop screenshots, Fabric,
skills - stays in the main session. The specialists handle the recon before it and
the review after it.

If you want the strict version in one repo, put `{ "agent": "triage-lead" }` in
that repo's `.claude\settings.json`. The Claude Code docs only show this at project
scope, and don't say whether the VS Code extension honors it.

## Cost controls worth knowing

The agents already set these, but if you are writing your own:

| Frontmatter | Effect |
|---|---|
| `model: haiku` | Cheapest Claude model |
| `effort: low` | Less reasoning per turn - right for mechanical work |
| `maxTurns: 20` | Hard stop before an agent wanders |
| `tools: Read, Grep, Glob` | No write tools, so no accidental edits and fewer turns |
| `omitClaudeMd: true` | Skips loading CLAUDE.md - saves context for agents that do not need project conventions |

`/context` shows what is actually filling the window, and `/cost` shows the spend
for the session. Both are worth checking the first time you use a new agent.

## Troubleshooting

**Agents do not appear.** Restart Claude Code - the folder is read at startup.
Then confirm the files landed:

```powershell
Get-ChildItem ~\.claude\agents
```

**An agent appears but shows the wrong model.** You are probably looking at an
older copy. Re-run the install; it removes stale files it previously wrote.

**"Install skipped a file."** Something not written by this kit is already at that
path. Look at it first - it may be an agent you wrote. `-Force` overwrites.

**Claude will not delegate on its own.** Name the agent explicitly. If it should
have been picked up automatically, the agent's `description` is too vague about
*when* to use it - descriptions are what Claude matches on.
