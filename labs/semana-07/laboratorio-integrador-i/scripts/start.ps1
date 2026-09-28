$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

& (Join-Path $PSScriptRoot "configure-env.ps1")

Write-Host "Validando Docker Compose..."
docker compose config --quiet

Write-Host "Construyendo las dos imágenes de trabajo..."
docker compose --profile jobs build pipeline-ingest pipeline-dbt

Write-Host "Levantando Kestra y su PostgreSQL..."
docker compose up -d kestra-db kestra

Write-Host "Esperando la API de Kestra..."
$Ready = $false
for ($Attempt = 1; $Attempt -le 60; $Attempt++) {
    try {
        $Response = Invoke-WebRequest -Uri "http://localhost:8080/api/v1/main/flows/labs.semana07/nyc_taxi_end_to_end" -UseBasicParsing -TimeoutSec 3
        if ($Response.StatusCode -eq 200) {
            $Ready = $true
            break
        }
    }
    catch {
        Start-Sleep -Seconds 2
    }
}

if (-not $Ready) {
    docker compose logs --tail 80 kestra
    throw "Kestra no quedó listo. Revisa los logs anteriores."
}

Write-Host "Infraestructura lista: http://localhost:8080" -ForegroundColor Green
Write-Host "En Kestra abre labs.semana07 / nyc_taxi_end_to_end y presiona Execute."

