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

This writes 13 agent files to `~\.claude\agents\`, which makes them available in
every project on the machine.

If PowerShell refuses to run the script:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 3. Confirm

Restart Claude Code (or the Desktop app) and run:

```
/agents
```

You should see `code-reviewer`, `architect`, `repo-scout` and the rest, each
showing its model. Reviewers should say Opus; `repo-scout` and the other cheap
agents should say Haiku.

## 4. Use them

Three ways, in increasing order of laziness:

```
> use code-reviewer on this branch
> review this diff for bugs
> /agents
```

The second works because Claude reads each agent's `description` and delegates on
its own. You mostly do not have to name them.

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

## Routing rules for ad-hoc chat

The agents carry their own models, so nothing more is needed for delegation. But if
you want plain Claude Code chat to follow the same cost discipline - summarise
before escalating, search rather than read whole files - add the routing
instructions to your user memory:

```powershell
.\scripts\install.ps1 -Target claude -WithInstructions
```

That prints a single `@`-import line to add to `~\.claude\CLAUDE.md`. It does not
edit that file for you, because it is yours and may already have content you care
about.

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
