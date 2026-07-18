#!/usr/bin/env bash
# merge-order.sh — print the order in which open PRs must receive a merge
# verdict, for a gate that only inspects the single newest open PR each cycle.
#
# WHY: if your review/merge gate does something like
#   gh pr list --state open --limit 1        (newest-first)
# then verdicting an OLDER PR while a NEWER, un-verdicted PR is still open
# will stall forever — the gate keeps looking at the newer one, sees no
# verdict, refuses it, and never gets back to the one you verdicted.
#
# FIX: always verdict newest-first. This script just prints that order so a
# human or orchestrating agent doesn't have to eyeball `gh pr list` under
# time pressure.
#
# USAGE:
#   cd <repo> && ./merge-order.sh
#   ./merge-order.sh --base main             # only PRs targeting a specific base
#
# Requires: gh (authenticated), run from inside the target repo.

set -euo pipefail

BASE_FILTER=()
if [[ "${1:-}" == "--base" && -n "${2:-}" ]]; then
  BASE_FILTER=(--base "$2")
fi

echo "Open PRs, newest-first (this is the order to verdict them in):"
echo

gh pr list --state open "${BASE_FILTER[@]}" \
  --json number,title,headRefName,createdAt,mergeable \
  --jq 'sort_by(.number) | reverse | .[] |
    "  #\(.number)  \(.title)  [\(.headRefName)]  mergeable=\(.mergeable)"'

echo
echo "Verdict and merge #-highest first. Only after it merges, rebase the next"
echo "branch onto the new base and repeat — do NOT verdict an older PR while a"
echo "newer one is still open, or a newest-first gate will never reach it."
