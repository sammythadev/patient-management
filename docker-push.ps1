# =============================================================================
# docker-push.ps1 - Build and push all service images to Docker Hub
# =============================================================================
# Prerequisites:
#   docker login
#
# Usage:
#   .\docker-push.ps1
#   .\docker-push.ps1 -Username "your-dockerhub-username"
#   .\docker-push.ps1 -Tag "v1.0.0"
#   .\docker-push.ps1 -Username "your-dockerhub-username" -Tag "v1.0.0"
#   .\docker-push.ps1 -EnvFile ".env"
# =============================================================================

param(
    [string]$Username,
    [string]$Tag,
    [string]$EnvFile = (Join-Path $PSScriptRoot ".env")
)

$ErrorActionPreference = "Stop"

function Load-EnvFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return
    }

    Get-Content $Path | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Item -Path "env:$key" -Value $value
        }
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker is not available on PATH."
    exit 1
}

Load-EnvFile -Path $EnvFile

if (-not $Username) {
    $Username = $env:DOCKER_USERNAME
}

if (-not $Tag) {
    $Tag = $env:IMAGE_TAG
}

if (-not $Tag) {
    $Tag = "latest"
}

if (-not $Username) {
    Write-Error "DOCKER_USERNAME not set. Provide -Username or set it in $EnvFile or environment."
    exit 1
}

$services = @(
    "auth-service",
    "patient-service",
    "billing-service",
    "analytics-service",
    "api-gateway"
)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Building & Pushing Docker Images" -ForegroundColor Cyan
Write-Host " Username: $Username | Tag: $Tag" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

foreach ($service in $services) {
    $contextPath = Join-Path $PSScriptRoot $service
    if (-not (Test-Path $contextPath)) {
        Write-Error "Service folder not found: $contextPath"
        exit 1
    }

    $imageName = "${Username}/${service}:$Tag"

    Write-Host "`n>>> [$service] Building $imageName ..." -ForegroundColor Yellow
    docker build -t $imageName $contextPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build $service"
        exit 1
    }

    Write-Host ">>> [$service] Pushing $imageName ..." -ForegroundColor Yellow
    docker push $imageName
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to push $service"
        exit 1
    }

    Write-Host ">>> [$service] Done!" -ForegroundColor Green
}

Write-Host "`n=============================================" -ForegroundColor Green
Write-Host " All images pushed successfully!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
