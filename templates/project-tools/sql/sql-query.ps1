<#
.SYNOPSIS
    Run a read-only SQL query and print a short answer. For agents and people alike.

.DESCRIPTION
    Starter script from agent-delegation-kit. Copy it into the project's tools
    folder; the project owns it from then on.

    Reads the connection from the project's .env file, so an agent can query the
    database without ever opening .env or seeing a password. Refuses anything that
    is not a read: statements that write, change schema, execute procedures or
    SELECT ... INTO are rejected before connecting, and every batch runs inside a
    transaction that is rolled back.

    The keyword check is a guard rail, not a security boundary. The real guarantee
    is a login that can only read (db_datareader, or a role with SELECT and VIEW
    DEFINITION only). Use one in .env.

    .env keys (first match wins):
      SQL_CONNECTION_STRING                         - a full connection string, or:
      SQL_SERVER    | DB_SERVER   | DB_HOST
      SQL_DATABASE  | DB_DATABASE | DB_NAME
      SQL_USER      | DB_USER     | DB_USERNAME     - leave out for Windows auth
      SQL_PASSWORD  | DB_PASSWORD
      SQL_AUTHENTICATION                            - e.g. Active Directory Integrated
      SQL_TRUST_SERVER_CERT=true                    - for a server with a self-signed cert

.EXAMPLE
    .\tools\sql-query.ps1 -Query "SELECT COUNT(*) AS n FROM dbo.vw_Sales WHERE OrderDate >= '2026-01-01'"
.EXAMPLE
    .\tools\sql-query.ps1 -File .\sql\checks\row-counts.sql -Var @{ StartDate = '2026-01-01' } -Statistics
#>
param(
    [string]$Query,
    [string]$File,
    [hashtable]$Var = @{},
    [int]$MaxRows = 20,
    [int]$TimeoutSeconds = 120,
    [string]$EnvFile,
    [string]$Database,
    [switch]$Statistics
)

$ErrorActionPreference = 'Stop'

# One plain line on stderr and exit 1: agents read this output, so no stack dumps.
function Stop-Query([string]$Message) { [Console]::Error.WriteLine("sql-query: $Message"); exit 1 }

if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($File)) { Stop-Query 'Give -Query or -File.' }
if (-not [string]::IsNullOrWhiteSpace($File)) { $Query = [System.IO.File]::ReadAllText((Resolve-Path $File)) }

# --- .env --------------------------------------------------------------------
# Search upward from the current folder, so the script works from any subfolder.
if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    $dir = (Get-Location).Path
    while ($dir) {
        $candidate = Join-Path $dir '.env'
        if (Test-Path $candidate) { $EnvFile = $candidate; break }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
}
if ([string]::IsNullOrWhiteSpace($EnvFile) -or -not (Test-Path $EnvFile)) {
    Stop-Query 'No .env found. Put one at the project root (it must be gitignored), or pass -EnvFile.'
}
$envVars = @{}
foreach ($line in [System.IO.File]::ReadAllLines($EnvFile)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $eq = $t.IndexOf('=')
    if ($eq -lt 1) { continue }
    $k = $t.Substring(0, $eq).Trim()
    if ($k.StartsWith('export ')) { $k = $k.Substring(7).Trim() }
    $v = $t.Substring($eq + 1).Trim()
    if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) { $v = $v.Substring(1, $v.Length - 2) }
    $envVars[$k] = $v
}
function Get-EnvValue([string[]]$Names) {
    foreach ($n in $Names) { if ($envVars.ContainsKey($n) -and $envVars[$n] -ne '') { return $envVars[$n] } }
    return $null
}

$secret = $null
$connStr = Get-EnvValue @('SQL_CONNECTION_STRING')
if ($null -eq $connStr) {
    $server = Get-EnvValue @('SQL_SERVER', 'DB_SERVER', 'DB_HOST')
    $dbName = Get-EnvValue @('SQL_DATABASE', 'DB_DATABASE', 'DB_NAME')
    if ($null -eq $server) { Stop-Query ".env has no SQL_SERVER (or SQL_CONNECTION_STRING). Keys found: $(($envVars.Keys | Sort-Object) -join ', ')" }
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b['Data Source'] = $server
    if ($dbName) { $b['Initial Catalog'] = $dbName }
    $user = Get-EnvValue @('SQL_USER', 'DB_USER', 'DB_USERNAME')
    $auth = Get-EnvValue @('SQL_AUTHENTICATION')
    if ($auth) { $b['Authentication'] = $auth }
    if ($user) {
        $b['User ID'] = $user
        $secret = Get-EnvValue @('SQL_PASSWORD', 'DB_PASSWORD')
        if ($secret) { $b['Password'] = $secret }
    }
    elseif (-not $auth) { $b['Integrated Security'] = $true }
    $b['Encrypt'] = $true
    if ((Get-EnvValue @('SQL_TRUST_SERVER_CERT')) -match '^(1|true|yes)$') { $b['TrustServerCertificate'] = $true }
    $connStr = $b.ConnectionString
}
else {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($connStr)
    if ($b.ContainsKey('Password')) { $secret = [string]$b['Password'] }
}
$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($connStr)
$b['ApplicationIntent'] = 'ReadOnly'
$b['Application Name'] = 'sql-query.ps1'
if ($Database) { $b['Initial Catalog'] = $Database }
$connStr = $b.ConnectionString

function Hide-Secret([string]$Text) {
    if ($secret -and $Text) { return $Text.Replace($secret, '***') }
    return $Text
}

# --- read-only guard -----------------------------------------------------------
# Blank out comments and string literals (keeping line breaks), so a keyword in a
# comment or a literal does not count, and one hidden in neither cannot slip by.
function Remove-CommentsAndStrings([string]$Sql) {
    $sb = New-Object System.Text.StringBuilder $Sql.Length
    $i = 0; $n = $Sql.Length
    while ($i -lt $n) {
        $c = $Sql[$i]
        if ($c -eq '-' -and $i + 1 -lt $n -and $Sql[$i + 1] -eq '-') {
            while ($i -lt $n -and $Sql[$i] -ne "`n") { [void]$sb.Append(' '); $i++ }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $n -and $Sql[$i + 1] -eq '*') {
            $depth = 0
            do {
                if ($i + 1 -lt $n -and $Sql[$i] -eq '/' -and $Sql[$i + 1] -eq '*') { $depth++; [void]$sb.Append('  '); $i += 2; continue }
                if ($i + 1 -lt $n -and $Sql[$i] -eq '*' -and $Sql[$i + 1] -eq '/') { $depth--; [void]$sb.Append('  '); $i += 2; continue }
                if ($Sql[$i] -eq "`n") { [void]$sb.Append("`n") } else { [void]$sb.Append(' ') }
                $i++
            } while ($i -lt $n -and $depth -gt 0)
        }
        elseif ($c -eq "'") {
            [void]$sb.Append("'"); $i++
            while ($i -lt $n) {
                if ($Sql[$i] -eq "'") {
                    if ($i + 1 -lt $n -and $Sql[$i + 1] -eq "'") { [void]$sb.Append('  '); $i += 2; continue }
                    break
                }
                if ($Sql[$i] -eq "`n") { [void]$sb.Append("`n") } else { [void]$sb.Append(' ') }
                $i++
            }
            if ($i -lt $n) { [void]$sb.Append("'"); $i++ }
        }
        else { [void]$sb.Append($c); $i++ }
    }
    return $sb.ToString()
}

foreach ($k in $Var.Keys) { $Query = $Query.Replace('$(' + $k + ')', [string]$Var[$k]) }
if ($Query -match '\$\((\w+)\)') { Stop-Query "SQLCMD variable `$($($Matches[1])) has no value. Pass it with -Var @{ $($Matches[1]) = '...' }." }

$bare = Remove-CommentsAndStrings $Query
$forbidden = 'INSERT|UPDATE|DELETE|MERGE|TRUNCATE|DROP|ALTER|CREATE|EXEC|EXECUTE|GRANT|REVOKE|DENY|BACKUP|RESTORE|DBCC|SHUTDOWN|KILL|RECONFIGURE|OPENROWSET|OPENDATASOURCE|OPENQUERY|BULK|INTO|WRITETEXT|UPDATETEXT|sp_\w+|xp_\w+'
$hit = [regex]::Match($bare, "(?im)(?<![\w@#\.\[])($forbidden)(?![\w\]])")
if ($hit.Success) {
    $lineNo = ($bare.Substring(0, $hit.Index) -split "`n").Count
    Stop-Query "Refused: '$($hit.Value)' on line $lineNo. This script only reads. Deliver changes as a script for the user to deploy."
}

# Split on GO lines, as sqlcmd does.
$batches = @()
$current = New-Object System.Text.StringBuilder
$origLines = $Query -split "`r?`n"
$bareLines = $bare -split "`r?`n"
for ($li = 0; $li -lt $origLines.Count; $li++) {
    if ($bareLines[$li] -match '^\s*GO\s*$') {
        if ($current.ToString().Trim()) { $batches += $current.ToString() }
        $current = New-Object System.Text.StringBuilder
    }
    else { [void]$current.AppendLine($origLines[$li]) }
}
if ($current.ToString().Trim()) { $batches += $current.ToString() }

# --- run -----------------------------------------------------------------------
$conn = New-Object System.Data.SqlClient.SqlConnection $connStr
$messages = New-Object System.Collections.Generic.List[string]
$conn.add_InfoMessage({ param($s, $e) foreach ($m in $e.Errors) { $messages.Add($m.Message) } }.GetNewClosure())
try {
    try { $conn.Open() }
    catch {
        $ex = $_.Exception
        if ($ex.InnerException) { $ex = $ex.InnerException }
        Stop-Query "could not connect: $(Hide-Secret $ex.Message)"
    }
    $tx = $conn.BeginTransaction()
    $set = 0
    try {
        if ($Statistics) {
            $s = $conn.CreateCommand(); $s.Transaction = $tx
            $s.CommandText = 'SET STATISTICS IO, TIME ON;'; [void]$s.ExecuteNonQuery()
        }
        foreach ($batch in $batches) {
            $cmd = $conn.CreateCommand()
            $cmd.Transaction = $tx
            $cmd.CommandTimeout = $TimeoutSeconds
            $cmd.CommandText = $batch
            $reader = $cmd.ExecuteReader()
            try {
                do {
                    if ($reader.FieldCount -eq 0) { continue }
                    $set++
                    $names = @(); for ($f = 0; $f -lt $reader.FieldCount; $f++) { $names += $reader.GetName($f) }
                    Write-Output ("-- result $set`n" + ($names -join "`t"))
                    $rows = 0
                    while ($reader.Read()) {
                        $rows++
                        if ($rows -le $MaxRows) {
                            $vals = @()
                            for ($f = 0; $f -lt $reader.FieldCount; $f++) {
                                if ($reader.IsDBNull($f)) { $v = 'NULL' } else { $v = [string]$reader.GetValue($f) }
                                $v = $v -replace "[`r`n`t]+", ' '
                                if ($v.Length -gt 60) { $v = $v.Substring(0, 57) + '...' }
                                $vals += $v
                            }
                            Write-Output ($vals -join "`t")
                        }
                    }
                    if ($rows -gt $MaxRows) { Write-Output "($rows rows, first $MaxRows shown - aggregate instead of reading rows)" }
                    else { Write-Output "($rows rows)" }
                } while ($reader.NextResult())
            }
            finally { $reader.Close() }
        }
    }
    finally { $tx.Rollback() }
}
catch { Stop-Query (Hide-Secret $_.Exception.Message) }
finally { $conn.Close() }

if ($messages.Count -gt 0) {
    # STATISTICS output is verbose; keep the lines that carry numbers that matter.
    $keep = @($messages | Where-Object { $_ -match 'logical reads|elapsed time|rows affected' -or -not $Statistics })
    if ($keep.Count -gt 0) { Write-Output "-- messages`n$(Hide-Secret (($keep | Select-Object -First 30) -join "`n"))" }
}
