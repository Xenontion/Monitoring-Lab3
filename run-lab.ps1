param(
    [int]$Seconds = 30,
    [int]$Port = 5432,
    [string]$Database = "lr3_powa",
    [string]$User = "postgres"
)

$ErrorActionPreference = "Stop"
$psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
$python = "C:\Users\Asus\AppData\Local\Programs\Python\Python314\python.exe"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $psql)) { throw "psql.exe was not found at $psql" }
if (-not (Test-Path $python)) { throw "Python 3.14 was not found at $python" }

if ($Port -eq 55432 -and $Database -eq "powa" -and $User -eq "postgres") {
    $env:PGPASSWORD = "postgres"
}

Write-Host "Creating database $Database if it does not exist..."
& $psql -h localhost -p $Port -U $User -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$Database'" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not connect to PostgreSQL. Enter the password in SQL Shell or configure pgpass.conf." }

$exists = (& $psql -h localhost -p $Port -U $User -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$Database'").Trim()
if ($exists -ne "1") { & $psql -h localhost -p $Port -U $User -d postgres -c "CREATE DATABASE $Database"; if ($LASTEXITCODE -ne 0) { throw "Database creation failed." } }

Write-Host "Applying schema and collecting pg_stat_statements..."
& $psql -h localhost -p $Port -U $User -d $Database -f (Join-Path $root "setup.sql")
if ($LASTEXITCODE -ne 0) { throw "Schema setup failed. Ensure shared_preload_libraries includes pg_stat_statements." }

if (-not (Test-Path (Join-Path $root ".venv\Scripts\python.exe"))) {
    & $python -m venv (Join-Path $root ".venv")
    & (Join-Path $root ".venv\Scripts\python.exe") -m pip install -r (Join-Path $root "requirements.txt")
}

& (Join-Path $root ".venv\Scripts\python.exe") (Join-Path $root "workload.py") --seconds $Seconds --port $Port --database $Database --user $User
if ($LASTEXITCODE -ne 0) { throw "Workload failed." }
Write-Host "Done. Open results\top_queries.tsv, results\explain.txt and report.md."
