@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "MODE=dev"
set "ENV_FILE="
set "COMPOSE_FILE="
set "TAG="
set "BUILD=0"
set "PROJECT_NAME="
set "CLEAN=0"

:parse
if "%~1"=="" goto after_parse
if /i "%~1"=="dev" set "MODE=dev" & shift & goto parse
if /i "%~1"=="prod" set "MODE=prod" & shift & goto parse
if /i "%~1"=="--dev" set "MODE=dev" & shift & goto parse
if /i "%~1"=="--prod" set "MODE=prod" & shift & goto parse
if /i "%~1"=="--env-file" set "ENV_FILE=%~2" & shift & shift & goto parse
if /i "%~1"=="--compose-file" set "COMPOSE_FILE=%~2" & shift & shift & goto parse
if /i "%~1"=="--tag" set "TAG=%~2" & shift & shift & goto parse
if /i "%~1"=="--build" set "BUILD=1" & shift & goto parse
if /i "%~1"=="--project-name" set "PROJECT_NAME=%~2" & shift & shift & goto parse
if /i "%~1"=="-p" set "PROJECT_NAME=%~2" & shift & shift & goto parse
if /i "%~1"=="--clean" set "CLEAN=1" & shift & goto parse
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
echo ERROR: Unknown argument %~1
goto usage

:after_parse
if not defined COMPOSE_FILE (
    if /i "%MODE%"=="prod" (
        set "COMPOSE_FILE=%SCRIPT_DIR%docker-compose.prod.yml"
    ) else (
        set "COMPOSE_FILE=%SCRIPT_DIR%docker-compose.dev.yml"
    )
)

if not defined ENV_FILE (
    if /i "%MODE%"=="prod" (
        set "ENV_FILE=%SCRIPT_DIR%.env.prod"
    ) else (
        set "ENV_FILE=%SCRIPT_DIR%.env"
    )
)

if not exist "%COMPOSE_FILE%" (
    echo ERROR: Compose file not found: %COMPOSE_FILE%
    exit /b 1
)

if not exist "%ENV_FILE%" (
    echo ERROR: Env file not found: %ENV_FILE%
    exit /b 1
)

where docker >nul 2>&1
if errorlevel 1 (
    echo ERROR: docker is not available on PATH.
    exit /b 1
)

call :load_env "%ENV_FILE%"

if /i "%MODE%"=="dev" (
    call :require_var DOCKER_USERNAME
) else (
    call :require_var DOCKER_USERNAME
    call :require_var IMAGE_TAG
    call :require_var DB_USERNAME
    call :require_var DB_PASSWORD
    call :require_var AUTH_DB_NAME
    call :require_var PATIENT_DB_NAME
    call :require_var KAFKA_BOOTSTRAP_SERVERS
    call :require_var JWT_SECRET
    call :require_var BILLING_SERVICE_ADDRESS
    call :require_var BILLING_SERVICE_GRPC_PORT
)

if defined TAG set "IMAGE_TAG=%TAG%"
if "%BUILD%"=="1" if not defined IMAGE_TAG set "IMAGE_TAG=latest"

call :ensure_docker
call :ensure_project_name
call :ensure_network
call :ensure_volumes
if "%CLEAN%"=="1" (
    call :cleanup_containers
)
if "%BUILD%"=="1" (
    call :build_images
    if errorlevel 1 exit /b 1
)

echo =============================================
echo Starting stack (%MODE%)
echo Compose: %COMPOSE_FILE%
echo Env:     %ENV_FILE%
echo Project: %COMPOSE_PROJECT_NAME%
echo =============================================

docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" up -d --remove-orphans
if errorlevel 1 (
    echo ERROR: docker compose up failed.
    exit /b 1
)

docker compose -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" ps
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

:require_var
set "VAR_NAME=%~1"
if not defined !VAR_NAME! (
    echo ERROR: Required variable not set in %ENV_FILE%: %VAR_NAME%
    exit /b 1
)
goto :eof

:ensure_project_name
if not defined PROJECT_NAME (
    if defined COMPOSE_PROJECT_NAME (
        set "PROJECT_NAME=%COMPOSE_PROJECT_NAME%"
    ) else (
        set "PROJECT_NAME=patient-management"
    )
)
set "COMPOSE_PROJECT_NAME=%PROJECT_NAME%"
goto :eof

:ensure_network
set "NETWORK_NAME=internal"
docker network inspect "%NETWORK_NAME%" >nul 2>&1
if errorlevel 1 (
    echo Creating network: %NETWORK_NAME%
    docker network create --driver bridge "%NETWORK_NAME%" >nul
    if errorlevel 1 exit /b 1
)
goto :eof

:ensure_volumes
set "VOLUME_AUTH=%COMPOSE_PROJECT_NAME%_auth-db-data"
set "VOLUME_PATIENT=%COMPOSE_PROJECT_NAME%_patient-db-data"

docker volume inspect "%VOLUME_AUTH%" >nul 2>&1
if errorlevel 1 (
    echo Creating volume: %VOLUME_AUTH%
    docker volume create "%VOLUME_AUTH%" >nul
    if errorlevel 1 exit /b 1
)

docker volume inspect "%VOLUME_PATIENT%" >nul 2>&1
if errorlevel 1 (
    echo Creating volume: %VOLUME_PATIENT%
    docker volume create "%VOLUME_PATIENT%" >nul
    if errorlevel 1 exit /b 1
)
goto :eof

:cleanup_containers
set "NAMES=auth-service-db patient-service-db zookeeper kafka auth-service billing-service analytics-service patient-service api-gateway"
for %%C in (%NAMES%) do (
    for /f "usebackq delims=" %%I in (`docker ps -a --filter "name=%%C" --format "{{.ID}}"`) do (
        echo Removing container: %%C
        docker rm -f "%%C" >nul 2>&1
    )
)
goto :eof

:build_images
set "SERVICES=auth-service patient-service billing-service analytics-service api-gateway"
echo =============================================
echo Building local images
echo Tag: %IMAGE_TAG%
echo =============================================

for %%S in (%SERVICES%) do (
    set "CONTEXT=%SCRIPT_DIR%%%S"
    if not exist "!CONTEXT!\" (
        echo ERROR: Service folder not found: !CONTEXT!
        exit /b 1
    )

    set "IMAGE=%DOCKER_USERNAME%/%%S:%IMAGE_TAG%"
    echo.
    echo ^>^>^> [%%S] Building !IMAGE! ...
    docker build -t "!IMAGE!" "!CONTEXT!"
    if errorlevel 1 (
        echo ERROR: Failed to build %%S
        exit /b 1
    )
)
goto :eof

:ensure_docker
docker info >nul 2>&1
if %errorlevel%==0 goto :eof

echo Docker engine not responding. Attempting to start...

sc query com.docker.service >nul 2>&1
if %errorlevel%==0 (
    sc start com.docker.service >nul 2>&1
)

if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" (
    start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
) else if exist "%ProgramFiles(x86)%\Docker\Docker\Docker Desktop.exe" (
    start "" "%ProgramFiles(x86)%\Docker\Docker\Docker Desktop.exe"
)

set /a retries=60
:wait_docker
docker info >nul 2>&1
if %errorlevel%==0 goto docker_ready
timeout /t 2 >nul
set /a retries-=1
if %retries% leq 0 (
    echo ERROR: Docker engine did not become ready. Start Docker Desktop and retry.
    exit /b 1
)
goto wait_docker

:docker_ready
echo Docker is running.
goto :eof

:usage
echo Usage:
echo   docker-start.bat [dev^|prod] [--tag TAG] [--env-file FILE] [--compose-file FILE] [--build] [--project-name NAME] [--clean]
echo.
echo Examples:
echo   docker-start.bat
echo   docker-start.bat --build
echo   docker-start.bat --project-name patient-management
echo   docker-start.bat --clean
echo   docker-start.bat prod --env-file .env.prod --tag v1.0.0
exit /b 1
