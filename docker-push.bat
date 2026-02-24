@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "ENV_FILE=%SCRIPT_DIR%.env"
set "USERNAME="
set "TAG="

:parse
if "%~1"=="" goto after_parse
if /i "%~1"=="-u" set "USERNAME=%~2" & shift & shift & goto parse
if /i "%~1"=="--username" set "USERNAME=%~2" & shift & shift & goto parse
if /i "%~1"=="-t" set "TAG=%~2" & shift & shift & goto parse
if /i "%~1"=="--tag" set "TAG=%~2" & shift & shift & goto parse
if /i "%~1"=="--env-file" set "ENV_FILE=%~2" & shift & shift & goto parse
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
echo ERROR: Unknown argument %~1
goto usage

:after_parse
if exist "%ENV_FILE%" call :load_env "%ENV_FILE%"

if not defined USERNAME set "USERNAME=%DOCKER_USERNAME%"
if not defined TAG set "TAG=%IMAGE_TAG%"
if not defined TAG set "TAG=latest"

where docker >nul 2>&1
if errorlevel 1 (
    echo ERROR: docker is not available on PATH.
    exit /b 1
)

if not defined USERNAME (
    echo ERROR: DOCKER_USERNAME not set. Provide -u/--username or set it in %ENV_FILE%.
    exit /b 1
)

set "SERVICES=auth-service patient-service billing-service analytics-service api-gateway"

echo =============================================
echo  Building ^& Pushing Docker Images
echo  Username: %USERNAME% ^| Tag: %TAG%
echo =============================================

for %%S in (%SERVICES%) do (
    set "CONTEXT=%SCRIPT_DIR%%%S"
    if not exist "!CONTEXT!\" (
        echo ERROR: Service folder not found: !CONTEXT!
        exit /b 1
    )

    set "IMAGE=%USERNAME%/%%S:%TAG%"
    echo.
    echo ^>^>^> [%%S] Building !IMAGE! ...
    docker build -t "!IMAGE!" "!CONTEXT!"
    if errorlevel 1 (
        echo ERROR: Failed to build %%S
        exit /b 1
    )

    echo ^>^>^> [%%S] Pushing !IMAGE! ...
    docker push "!IMAGE!"
    if errorlevel 1 (
        echo ERROR: Failed to push %%S
        exit /b 1
    )

    echo ^>^>^> [%%S] Done!
)

echo.
echo =============================================
echo  All images pushed successfully!
echo =============================================
exit /b 0

:load_env
set "ENV_PATH=%~1"
for /f "usebackq tokens=1* delims==" %%A in ("%ENV_PATH%") do (
    set "KEY=%%A"
    set "VAL=%%B"
    if not "!KEY!"=="" if not "!KEY:~0,1!"=="#" (
        set "!KEY!=!VAL!"
    )
)
goto :eof

:usage
echo Usage:
echo   docker-push.bat [--username USERNAME] [--tag TAG] [--env-file FILE]
echo.
echo Examples:
echo   docker-push.bat
echo   docker-push.bat --username myuser --tag v1.0.0
echo   docker-push.bat --env-file .env
exit /b 1
