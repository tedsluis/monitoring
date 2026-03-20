#!/bin/bash
# poll-renovate-prs.sh - Checks and tests Renovate PRs automatically
set -uo pipefail

# Variables
REPO="tedsluis/monitoring"
WORKDIR="$(pwd)"
STATE_FILE="$WORKDIR/pr_state.json"
LOCK_FILE="/tmp/renovate-poller.lock"
LOG_DIR="$WORKDIR/test-logs"

# Ensure required directories/files exist
mkdir -p "$LOG_DIR"
if [ ! -f "$STATE_FILE" ]; then
    echo "{}" > "$STATE_FILE"
fi

# Concurrency lock
if [ -f "$LOCK_FILE" ]; then
    echo "Poller already running. Exiting."
    exit 0
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

echo "🔄 Starting Renovate PR Poller at $(date)"

# Fetch open PRs from the renovate bot
PRS=$(gh pr list --repo "$REPO" --state open --label "renovate" --json number,headRefName,headRepository,updatedAt --jq '.[] | "\(.number) \(.headRefName) \(.updatedAt)"' || echo "")

if [ -z "$PRS" ]; then
    echo "No open Renovate PRs found."
    exit 0
fi

# Iterate over each PR
while read -r pr_number branch updated; do
    if [ -z "$pr_number" ]; then continue; fi
    
    echo "----------------------------------------"
    echo "📌 Inspecting PR #$pr_number (Branch: $branch)"

    current_sha=$(gh api "repos/$REPO/pulls/$pr_number" --jq .head.sha)
    last_sha=$(jq -r ".\"$pr_number\".last_commit_sha // empty" "$STATE_FILE")
    status=$(jq -r ".\"$pr_number\".status // empty" "$STATE_FILE")

    # Skip if this commit is already tested successfully or failed
    if [[ "$current_sha" == "$last_sha" && "$status" != "pending" ]]; then
        echo "⏩ PR #$pr_number (Commit: $current_sha) has already been tested (Status: $status). Skipping."
        continue
    fi

    echo "⚙️ New or updated PR found. Starting test cycle..."
    
    # Update state to testing
    jq ".\"$pr_number\" = {status: \"testing\", last_commit_sha: \"$current_sha\", timestamp: \"$(date -Iseconds)\"}" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"

    # Current working base (usually 'main')
    base_branch=$(gh pr view "$pr_number" --repo "$REPO" --json baseRefName --jq .baseRefName)
    
    # Checkout branch and reset environment
    git fetch origin "$branch"
    git checkout --force "$branch"
    git pull origin "$branch"

    echo "🚀 Starting containers for PR #$pr_number..."
    podman-compose pull
    podman-compose down
    podman-compose up -d --force-recreate

    # Run tests
    TEST_LOG="$LOG_DIR/pr-${pr_number}-$(date +%s).log"
    echo "🔬 Running tests... (Output logged in $TEST_LOG)"
    
    if ./run-tests.sh > "$TEST_LOG" 2>&1; then
        echo "✅ Test passed for PR #$pr_number!"
        
        # GitHub actions
        gh pr edit "$pr_number" --repo "$REPO" --add-label "test-passed" --remove-label "test-failed" 2>/dev/null || true
        gh pr comment "$pr_number" --repo "$REPO" --body "✅ **Automatic Validation Passed!**
The stack (including Prometheus, Grafana and Exporters) started successfully on commit \`$current_sha\`. No health check errors found."
        
        # Update State
        jq ".\"$pr_number\".status = \"passed\"" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"

    else
        echo "❌ Test failed for PR #$pr_number!"
        
        # GitHub actions
        gh pr edit "$pr_number" --repo "$REPO" --add-label "test-failed" --remove-label "test-passed" 2>/dev/null || true
        
        # Capture the last 15 lines of the log for the issue body
        FAIL_LOG=$(tail -n 15 "$TEST_LOG")
        
        # Create issue
        ISSUE_URL=$(gh issue create --repo "$REPO" \
            --title "🚨 Test Failed: Renovate PR #$pr_number" \
            --body "The automatic test failed for PR #$pr_number (Commit \`$current_sha\`).
            
**Error snippet:**
\`\`\`text
$FAIL_LOG
\`\`\`
Check the local log file for details: \`$TEST_LOG\`

*Rollback was automatically performed to the \`$base_branch\` branch.*" \
            --label "bug")

        # Comment on PR with issue link
        gh pr comment "$pr_number" --repo "$REPO" --body "❌ **Automatic Validation Failed.**
The stack did not start correctly. I created an issue with the log details: $ISSUE_URL
*System rolled back to the last stable branch.*"

        # Update State
        jq ".\"$pr_number\".status = \"failed\"" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"
    fi

    # ROLLBACK always back to base branch after testing a PR (keep the server tidy)
    echo "⏪ Rolling back to base branch ($base_branch)..."
    git checkout --force "$base_branch"
    podman-compose down
    podman-compose up -d --force-recreate

done <<< "$PRS"

echo "✅ Poller run complete."