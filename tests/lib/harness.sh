#!/usr/bin/env bash
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'

fail() { printf '%sFAIL%s [%s] %s\n' "$RED" "$RESET" "$(basename "$0")" "$*" >&2; exit 1; }
pass() { printf '%sPASS%s [%s] %s\n' "$GREEN" "$RESET" "$(basename "$0")" "$*"; }
skip() { printf '%sSKIP%s [%s] %s\n' "$YELLOW" "$RESET" "$(basename "$0")" "$*"; exit 0; }

assert_file() { [ -f "$1" ] || fail "expected file to exist: $1"; }
assert_missing() { [ -e "$1" ] && fail "expected path to be gone: $1"; return 0; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'${3:+ ($3)}"; }
