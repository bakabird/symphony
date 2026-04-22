@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PROJECT_ROOT=/Users/yang/AgentPiper/MissionCenter"

if "%~1"=="" (
  set "WORKFLOW=%PROJECT_ROOT%\elixir\WORKFLOW.md"
) else (
  if "%~1"=="%~f1" (
    set "WORKFLOW=%~1"
  ) else (
    set "WORKFLOW=%PROJECT_ROOT%\%~1"
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
