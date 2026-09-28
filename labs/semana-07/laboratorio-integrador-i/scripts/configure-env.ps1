$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvExample = Join-Path $ProjectRoot ".env.example"
$EnvFile = Join-Path $ProjectRoot ".env"
$KestraEnvFile = Join-Path $ProjectRoot ".env.kestra"

if (-not (Test-Path $EnvFile)) {
    Copy-Item $EnvExample $EnvFile
    Write-Host "Se creó .env." -ForegroundColor Yellow
    Write-Host "Edítalo, reemplaza los valores TODO y vuelve a ejecutar este script."
    exit 1
}

$Values = @{}
Get-Content $EnvFile | ForEach-Object {
    $Line = $_.Trim()
    if ($Line -and -not $Line.StartsWith("#") -and $Line.Contains("=")) {
        $Key, $Value = $Line.Split("=", 2)
        $CleanValue = $Value.Trim()
        if ($CleanValue.Length -ge 2) {
            $First = $CleanValue.Substring(0, 1)
            $Last = $CleanValue.Substring($CleanValue.Length - 1, 1)
            if (($First -eq '"' -and $Last -eq '"') -or
                ($First -eq "'" -and $Last -eq "'")) {
                $CleanValue = $CleanValue.Substring(1, $CleanValue.Length - 2)
            }
        }
        $Values[$Key.Trim()] = $CleanValue
    }
}

$Required = @(
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PASSWORD",
    "SNOWFLAKE_ROLE",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE"
)

foreach ($Key in $Required) {
    if (-not $Values.ContainsKey($Key) -or
        [string]::IsNullOrWhiteSpace($Values[$Key]) -or
        $Values[$Key].StartsWith("TODO_")) {
        throw "Falta configurar $Key en .env"
    }
}

$PasswordBytes = [System.Text.Encoding]::UTF8.GetBytes($Values["SNOWFLAKE_PASSWORD"])
$PasswordBase64 = [Convert]::ToBase64String($PasswordBytes)

$KestraLines = @(
    "ENV_SNOWFLAKE_ACCOUNT=$($Values['SNOWFLAKE_ACCOUNT'])",
    "ENV_SNOWFLAKE_USER=$($Values['SNOWFLAKE_USER'])",
    "ENV_SNOWFLAKE_ROLE=$($Values['SNOWFLAKE_ROLE'])",
    "ENV_SNOWFLAKE_WAREHOUSE=$($Values['SNOWFLAKE_WAREHOUSE'])",
    "ENV_SNOWFLAKE_DATABASE=$($Values['SNOWFLAKE_DATABASE'])",
    "SECRET_SNOWFLAKE_PASSWORD=$PasswordBase64"
)

[System.IO.File]::WriteAllLines(
    $KestraEnvFile,
    $KestraLines,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ".env y .env.kestra están listos para Docker y Kestra." -ForegroundColor Green
