@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PROJECT_ROOT=/Users/yang/AgentPiper/MissionCenter"
set "LOCAL_ROOT=%~dp0"

if "%~1"=="" (
  set "WORKFLOW=%LOCAL_ROOT%WORKFLOW.md"
) else (
  if "%~1"=="%~f1" (
    set "WORKFLOW=%~1"
  ) else (
    set "WORKFLOW=%LOCAL_ROOT%%~1"
  )
)

set "ELIXIR_DIR=%PROJECT_ROOT%\elixir"
set "SYMPHONY_BIN=%ELIXIR_DIR%\bin\symphony"

pushd "%ELIXIR_DIR%" >nul

if not exist "%SYMPHONY_BIN%" (
  call mise exec -- mix build
  if errorlevel 1 (
    set "EXITCODE=%ERRORLEVEL%"
    popd >nul
    exit /b %EXITCODE%
  )
)

call mise exec -- .\bin\symphony --i-understand-that-this-will-be-running-without-the-usual-guardrails "%WORKFLOW%"
set "EXITCODE=%ERRORLEVEL%"

popd >nul
exit /b %EXITCODE%
