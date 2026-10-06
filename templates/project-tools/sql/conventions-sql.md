# SQL conventions

Every builder brief names this file. Builders follow it; reviewers don't report
what `tools\sql-lint.ps1` already checks. Change it here, once, not per script.

## Commands

- Query (read-only): `.\tools\sql-query.ps1 -Query "..."` or `-File <path>`
- Lint: `.\tools\sql-lint.ps1 -Path <files> -NeverOutputFile .\tools\never-output.txt`

## Header

Every view and script starts with:

```sql
-- Grain: one row per <entity> per <period>
-- Source: <views and tables it reads>
-- Filters: <what it leaves out, and why>
```

## Batches and variables

- `GO` before and after every `CREATE OR ALTER VIEW`, procedure and function.
- One statement terminator. Never `;;`.
- SQLCMD variables: `:setvar` defaults at the top, then one `IF` per variable
  that checks its value and `THROW`s on a bad one, before anything else runs.
- A `@variable` doesn't survive a `GO`. Re-declare it, or keep its uses in one batch.

## Building on views

- `<schema.view>`: <grain, key columns, filters - checked on <date>>
- Replicate a view's logic from its definition, with the lines cited, or select
  from the view.
- Compare values at the declared type, with the source's `TRIM` and `CAST`.

## Outputs

- Never output a column in `tools\never-output.txt`.
- Suppress counts below **<n>**, and suppress a second cell (or the total)
  wherever a suppressed cell could be recovered by subtraction.
- <anything else the project decides>

## Proof

Every check names the case it would catch, and compares two independently
computed results.
