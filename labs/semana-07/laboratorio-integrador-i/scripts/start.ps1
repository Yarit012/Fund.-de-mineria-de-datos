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
$FlowUri = "http://localhost:8080/api/v1/main/flows/labs.semana07/nyc_taxi_end_to_end"
$ApiReady = $false
$FlowExists = $false

for ($Attempt = 1; $Attempt -le 60; $Attempt++) {
    try {
        $Response = Invoke-WebRequest -Uri $FlowUri -UseBasicParsing -TimeoutSec 3
        if ($Response.StatusCode -eq 200) {
            $ApiReady = $true
            $FlowExists = $true
            break
        }
    }
    catch {
        if ($null -ne $_.Exception.Response -and
            [int]$_.Exception.Response.StatusCode -eq 404) {
            $ApiReady = $true
            break
        }

        Start-Sleep -Seconds 2
    }
}

if (-not $ApiReady) {
    docker compose logs --tail 80 kestra
    throw "La API de Kestra no quedó lista. Revisa los logs anteriores."
}

if (-not $FlowExists) {
    Write-Host "El flujo no está registrado; importándolo desde el repositorio..."

    $FlowPath = Join-Path $ProjectRoot "kestra\flows\nyc_taxi_end_to_end.yml"
    $FlowYaml = [System.IO.File]::ReadAllText($FlowPath)

    Invoke-WebRequest `
        -Uri "http://localhost:8080/api/v1/main/flows" `
        -Method Post `
        -ContentType "application/x-yaml" `
        -Body $FlowYaml `
        -UseBasicParsing | Out-Null
}

$Response = Invoke-WebRequest -Uri $FlowUri -UseBasicParsing -TimeoutSec 10
if ($Response.StatusCode -ne 200) {
    throw "Kestra respondió, pero el flujo nyc_taxi_end_to_end no quedó registrado."
}

Write-Host "Infraestructura lista: http://localhost:8080" -ForegroundColor Green
Write-Host "En Kestra abre labs.semana07 / nyc_taxi_end_to_end y presiona Execute."
