$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

docker compose up -d
if ($LASTEXITCODE -ne 0) { throw "Could not start PoWA with Docker Compose." }

Write-Host "PoWA is starting. Open http://localhost:8888 in a few seconds."
Write-Host "Container status:"
docker compose ps
