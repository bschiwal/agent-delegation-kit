# SQL project tools (starter files)

Starter scripts for a SQL project worked on with the kit's agents. **Copy them
into the project and own them there** - the kit never runs or updates them, and
the project's rules belong in the project's copy.

| File | Copy to | What it does |
|---|---|---|
| `sql-query.ps1` | `tools\sql-query.ps1` | Runs a read-only query using the connection in the project's `.env`. Agents query the database without opening `.env` or seeing a password. |
| `sql-lint.ps1` | `tools\sql-lint.ps1` | Mechanical checks - batches, `;;`, view headers, `SELECT *`, `NOLOCK`, SQLCMD validation, never-output columns - so reviewers spend their turns on logic. |
| `conventions-sql.md` | `docs\conventions-sql.md` | The shared conventions file every builder brief names. Fill in the project's rules. |
| `never-output.txt` | `tools\never-output.txt` | Columns that must never appear in an output: names, IDs that identify a person, free text. One per line. |

Windows PowerShell 5.1 or PowerShell 7. No modules: `sql-query.ps1` uses the
SQL client built into .NET.

## Setup

1. Copy the files. Make sure `.env` is in the project's `.gitignore`.
2. Point `.env` at the database with a **read-only login** (`db_datareader`,
   or `SELECT` and `VIEW DEFINITION` only). The script refuses writes, but its
   keyword check is a guard rail; the login is the real protection.

   ```
   SQL_SERVER=myserver.database.windows.net
   SQL_DATABASE=Analytics
   SQL_USER=reporting_reader
   SQL_PASSWORD=...
   ```

   Or `SQL_CONNECTION_STRING=...`. Leave out `SQL_USER` for Windows
   authentication, or set `SQL_AUTHENTICATION=Active Directory Integrated`.
   `DB_SERVER`, `DB_NAME`, `DB_USER` and `DB_PASSWORD` are read too, if the
   `.env` already uses those names. Add `SQL_TRUST_SERVER_CERT=true` for a server
   with a self-signed certificate.
3. Test it yourself once:

   ```powershell
   .\tools\sql-query.ps1 -Query "SELECT DB_NAME() AS db, SUSER_SNAME() AS login"
   .\tools\sql-lint.ps1 -Path .\sql -NeverOutputFile .\tools\never-output.txt
   ```

4. Put both command lines in the project README, under a heading like
   **Agent commands**. That is where `sql-developer` and the reviewers look for
   how to query, and where the orchestrator copies them into briefs from.

## Why a script and not the `.env`

The agents are told never to look for credentials. A password read into an
agent's context is sent to the model provider, stays in the transcript, and is
re-read - and paid for - on every later turn. The script keeps the secret on
your machine: agents run it and see only the answer.
