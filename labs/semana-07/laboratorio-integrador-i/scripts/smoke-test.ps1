$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "1/4 Docker Compose"
docker compose config --quiet

Write-Host "2/4 Contenedores"
docker compose ps

Write-Host "3/4 Flujo Kestra"
$Response = Invoke-WebRequest -Uri "http://localhost:8080/api/v1/main/flows/labs.semana07/nyc_taxi_end_to_end" -UseBasicParsing
if ($Response.StatusCode -ne 200) {
    throw "Kestra no devolvió el flujo esperado"
}

Write-Host "4/4 Imágenes"
foreach ($Image in @("nyc-taxi-ingest:1.0", "nyc-taxi-dbt:1.0")) {
    docker image inspect $Image | Out-Null
}

Write-Host "Smoke test completado." -ForegroundColor Green

