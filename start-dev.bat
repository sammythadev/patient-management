@echo off
setlocal EnableExtensions

REM Usage:
REM   start-dev.bat [additional docker-start.bat args]

set "SCRIPT_DIR=%~dp0"
call "%SCRIPT_DIR%docker-start.bat" dev %*
