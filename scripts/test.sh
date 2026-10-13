#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h:h}"
swift test --package-path "$PROJECT_ROOT"
