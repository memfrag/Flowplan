#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Report whether the CloudKit Production schema is behind Development, and show
# exactly what a promotion would add.
#
# SwiftData mirrors to CloudKit, so any new @Model stored property exists only in
# the Development schema until it is promoted. Ship without promoting and the new
# field silently doesn't sync — no error, it just never appears on other devices.
# This script is the check that catches that before a release.
#
# It does NOT promote. cktool cannot: both `import-schema` and `validate-schema`
# reject the production environment with
#     BadRequestException: endpoint not applicable in the environment 'production'
# Promotion has to be done in the CloudKit Console:
#     https://icloud.developer.apple.com/dashboard
#     -> select the container -> Schema -> Deploy Schema Changes...
#
# IMPORTANT: the Development schema is only updated when a build containing the
# new @Model properties actually RUNS against the development environment (the
# Debug build). Building alone does nothing. So the order is:
#     run the Debug app once -> run this script -> promote in the Console.
#
# Prerequisites:
#   - A CloudKit management token, saved once with:
#       xcrun cktool save-token --type management
#     Create the token at https://icloud.developer.apple.com/dashboard
#     under Settings ▸ Tokens ▸ Management Tokens. cktool needs a real terminal to
#     prompt for it (it can't prompt from a non-interactive shell). Tokens expire —
#     if this script reports an auth failure, mint a new one and save it again.
#
# Usage:
#   ./Scripts/check-cloudkit-schema.sh
#
# Exit codes:
#   0  production is up to date
#   1  an error occurred
#   2  production is behind development — promotion needed
# -----------------------------------------------------------------------------

# --- Constants ---
TEAM_ID="CQXRBQKG85"
CONTAINER_ID="iCloud.pizza.martin.Flowplan"
CONSOLE_URL="https://icloud.developer.apple.com/dashboard"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="$PROJECT_DIR/build/cloudkit"
DEV_SCHEMA="$WORK_DIR/schema-development.ckdb"
PROD_SCHEMA="$WORK_DIR/schema-production.ckdb"

# --- Helpers ---
error() {
    echo "ERROR: $1" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            echo "Usage: $0"
            echo "  Diffs the CloudKit Development schema against Production and reports whether"
            echo "  a promotion is needed. Promotion itself must be done in the CloudKit Console."
            exit 0
            ;;
        *) error "Unknown argument: $1" ;;
    esac
done

command -v xcrun >/dev/null 2>&1 || error "xcrun not found — install Xcode."
xcrun cktool --version >/dev/null 2>&1 || error "cktool not available — install Xcode command line tools."

mkdir -p "$WORK_DIR"

cktool() {
    xcrun cktool "$@" --team-id "$TEAM_ID" --container-id "$CONTAINER_ID"
}

# --- Export both environments ---
echo "==> Exporting Development schema..."
cktool export-schema --environment development --output-file "$DEV_SCHEMA" \
    || error "Export failed. If this is an auth error, run (in a real terminal): xcrun cktool save-token --type management"

echo "==> Exporting Production schema..."
# A container that has never been promoted has no production schema; that's fine.
cktool export-schema --environment production --output-file "$PROD_SCHEMA" 2>/dev/null || true

# --- Report ---
echo
if [ ! -s "$PROD_SCHEMA" ]; then
    echo "==> No production schema yet — this would be the initial promotion."
    echo "    Promote in the CloudKit Console: $CONSOLE_URL"
    exit 2
fi

if diff -u "$PROD_SCHEMA" "$DEV_SCHEMA" > "$WORK_DIR/schema.diff"; then
    echo "==> Production is up to date. Nothing to promote."
    exit 0
fi

echo "==> Production is BEHIND development. Pending changes:"
echo
cat "$WORK_DIR/schema.diff"
echo
echo "==> Promote in the CloudKit Console (cktool can't do this):"
echo "    $CONSOLE_URL"
echo "    -> $CONTAINER_ID -> Schema -> Deploy Schema Changes..."
echo
echo "    Production schema is additive-only: promoted fields can never be removed"
echo "    or retyped, so check the diff above before deploying."
exit 2
