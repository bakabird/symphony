#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/Users/yang/AgentPiper/MissionCenter"
LOCAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -gt 0 ]; then
  case "$1" in
    /*) WORKFLOW_FILE="$1" ;;
    *) WORKFLOW_FILE="$LOCAL_ROOT/$1" ;;
  esac
else
  WORKFLOW_FILE="$LOCAL_ROOT/WORKFLOW.md"
fi

cd "$PROJECT_ROOT/elixir"

if [ ! -x "./bin/symphony" ]; then
  mise exec -- mix build
fi

exec mise exec -- ./bin/symphony --i-understand-that-this-will-be-running-without-the-usual-guardrails "$WORKFLOW_FILE"
