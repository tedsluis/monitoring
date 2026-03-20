#!/bin/bash
# poll-renovate-prs.sh - Checks, tests, merges and restarts the monitoring stack
set -uo pipefail

# Variables
REPO="tedsluis/monitoring"
WORKDIR="$(pwd)"
STATE_FILE="$WORKDIR/pr_state.json"
LOCK_FILE="/tmp/renovate-poller.lock"
LOG_DIR="$WORKDIR/test-logs"

# Flag to track if we need to restart main at the end
MAIN_NEEDS_UPDATE=false

# Ensure required directories/files exist
echo "[INFO] Verifying required directories and state files..."
mkdir -p "$LOG_DIR"
if [ ! -f "$STATE_FILE" ]; then
    echo "[INFO] State file not found. Creating a new empty JSON state file at $STATE_FILE"
    echo "{}" > "$STATE_FILE"
fi

# Concurrency lock
if [ -f "$LOCK_FILE" ]; then
    echo "[WARN] Poller is already running (lock file $LOCK_FILE exists). Exiting to prevent concurrent execution."
    exit 0
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

echo "🔄 Starting Renovate PR Poller at $(date)"

# Fetch open PRs with the 'renovate' label
echo "[INFO] Fetching open Pull Requests with the label 'renovate' from $REPO..."
PRS=$(gh pr list --repo "$REPO" --state open --label "renovate" --json number,headRefName,headRepository,updatedAt --jq '.[] | "\(.number) \(.headRefName) \(.updatedAt)"' || echo "")

if [ -z "$PRS" ]; then
    echo "✅ No open Renovate PRs found at this time."
    exit 0
fi

# Loop through each PR
while read -r pr_number branch updated; do
    if [ -z "$pr_number" ]; then continue; fi
    
    echo "----------------------------------------"
    echo "📌 Inspecting PR #$pr_number (Branch: $branch)"

    echo "[INFO] Fetching the latest commit SHA for PR #$pr_number..."
    current_sha=$(gh api "repos/$REPO/pulls/$pr_number" --jq .head.sha)
    last_sha=$(jq -r ".\"$pr_number\".last_commit_sha // empty" "$STATE_FILE")
    status=$(jq -r ".\"$pr_number\".status // empty" "$STATE_FILE")

    echo "[DEBUG] Current PR SHA: $current_sha"
    echo "[DEBUG] Last tested SHA: ${last_sha:-None}"
    echo "[DEBUG] Current status in state file: ${status:-None}"

    # Skip if we already tested this successfully or failed on THIS commit
    if [[ "$current_sha" == "$last_sha" && "$status" != "pending" ]]; then
        echo "⏩ PR #$pr_number (Commit: $current_sha) is already tested (Status: $status). Skipping."
        continue
    fi

    echo "⚙️ New or updated PR found. Starting test cycle..."
    
    # Update state to testing (but keep any issue_numbers)
    echo "[INFO] Updating local state file to 'testing'..."
    jq ".\"$pr_number\".status = \"testing\" | .\"$pr_number\".last_commit_sha = \"$current_sha\" | .\"$pr_number\".timestamp = \"$(date -Iseconds)\"" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"

    # Current working base (usually 'main')
    echo "[INFO] Identifying base branch for PR #$pr_number..."
    base_branch=$(gh pr view "$pr_number" --repo "$REPO" --json baseRefName --jq .baseRefName)
    echo "[INFO] Base branch identified as: $base_branch"
    
    # Checkout branch and reset the environment
    echo "[INFO] Executing git operations: fetching and checking out branch '$branch'..."
    git fetch origin "$branch"
    git checkout --force "$branch"
    git pull origin "$branch"

    echo "🚀 Starting containers for PR #$pr_number..."
    echo "[INFO] Running 'podman-compose pull' to ensure all images are up to date..."
    podman-compose pull
    echo "[INFO] Tearing down any existing stack (timeout 30s)..."
    podman-compose down -t 30
    echo "[INFO] Bringing up the new stack with '--force-recreate'..."
    podman-compose up -d --force-recreate

    # Executing tests
    TEST_LOG="$LOG_DIR/pr-${pr_number}-$(date +%s).log"
    echo "🔬 Running tests... (Output will be heavily logged in $TEST_LOG)"
    
    if ./run-tests.sh > "$TEST_LOG" 2>&1; then
        echo "✅ Test passed for PR #$pr_number!"
        
        # Github actions
        echo "[INFO] Applying 'test-passed' label to GitHub PR..."
        gh pr edit "$pr_number" --repo "$REPO" --add-label "test-passed" --remove-label "test-failed" 2>/dev/null || true
        
        LOG_CONTENT=$(tail -n 50 "$TEST_LOG")
        echo "[INFO] Commenting success message and test logs to GitHub PR..."
        gh pr comment "$pr_number" --repo "$REPO" --body "✅ **Automatic Validation Passed!**
The stack (including Prometheus, Grafana and Exporters) successfully started on commit \`$current_sha\`. No healthcheck errors found.

<details><summary>View the successful test log</summary>

\`\`\`text
$LOG_CONTENT
\`\`\`
</details>"
        
        # Check if an old issue was open for this PR
        ISSUE_NUM=$(jq -r ".\"$pr_number\".issue_number // empty" "$STATE_FILE")
        if [ -n "$ISSUE_NUM" ] && [ "$ISSUE_NUM" != "null" ]; then
            echo "✅ Closing previously failed issue #$ISSUE_NUM..."
            gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "✅ Test successfully completed on the newer commit \`$current_sha\`. This issue is automatically closed."
            gh issue close "$ISSUE_NUM" --repo "$REPO"
            # Remove issue number from the state
            jq "del(.\"$pr_number\".issue_number)" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"
        fi

        # Update State
        jq ".\"$pr_number\".status = \"passed\"" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"

        # MERGE DE PR
        echo "🔀 Merging PR #$pr_number into $base_branch..."
        if gh pr merge "$pr_number" --repo "$REPO" --merge --delete-branch; then
            echo "✅ PR successfully merged!"
            MAIN_NEEDS_UPDATE=true
            # Bring test-stack down. (Main will be restarted at the end)
            echo "[INFO] Bringing down the test stack..."
            podman-compose down -t 30
        else
            echo "⚠️ Could not merge PR automatically. Rolling back..."
            git checkout --force "$base_branch"
            podman-compose down -t 30
            podman-compose up -d --force-recreate
        fi

    else
        echo "❌ Test failed for PR #$pr_number!"
        
        echo "[INFO] Applying 'test-failed' label to GitHub PR..."
        gh pr edit "$pr_number" --repo "$REPO" --add-label "test-failed" --remove-label "test-passed" 2>/dev/null || true
        
        FAIL_LOG=$(tail -n 50 "$TEST_LOG")
        ISSUE_NUM=$(jq -r ".\"$pr_number\".issue_number // empty" "$STATE_FILE")
        
        if [ -z "$ISSUE_NUM" ] || [ "$ISSUE_NUM" == "null" ]; then
            # Create new issue
            echo "[INFO] Creating a new GitHub Issue for the failed test..."
            ISSUE_URL=$(gh issue create --repo "$REPO" \
                --title "🚨 Test Failed: Renovate PR #$pr_number" \
                --body "The automatic test failed for PR #$pr_number (Commit \`$current_sha\`).
                
<details><summary>View the error log</summary>

\`\`\`text
$FAIL_LOG
\`\`\`
</details>

*System rolled back to the stable branch.*" \
                --label "bug")

            ISSUE_NUM=${ISSUE_URL##*/} # Extracts the ID from the URL
            echo "[INFO] New issue created: #$ISSUE_NUM. Updating state file."
            jq ".\"$pr_number\".issue_number = \"$ISSUE_NUM\"" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"

            gh pr comment "$pr_number" --repo "$REPO" --body "❌ **Automatic Validation Failed.**
I have created an issue with the log details: #$ISSUE_NUM
*System has been rolled back to the latest stable branch.*"

        else
            # Update existing issue
            echo "[INFO] Updating existing GitHub Issue #$ISSUE_NUM..."
            gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "🚨 **Failed again** on newer commit \`$current_sha\`.

<details><summary>View the new error log</summary>

\`\`\`text
$FAIL_LOG
\`\`\`
</details>"
            gh pr comment "$pr_number" --repo "$REPO" --body "❌ **Automatic Validation Failed (Update).** See issue #$ISSUE_NUM"
        fi

        # Update State
        jq ".\"$pr_number\".status = \"failed\"" "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"
        
        # ROLLBACK TO STABLE STATE
        echo "⏪ Rolling back to base branch ($base_branch)..."
        git checkout --force "$base_branch"
        echo "[INFO] Destroying failed test stack..."
        podman-compose down -t 30
        echo "[INFO] Starting stable stack..."
        podman-compose up -d --force-recreate
    fi

done <<< "$PRS"

# ---------------------------------------------------------
# PRODUCTION (MAIN) UPDATE & RESTART
# ---------------------------------------------------------
if [ "$MAIN_NEEDS_UPDATE" = true ]; then
    echo "========================================"
    echo "🚀 PRs have been successfully merged!"
    echo "The production (main) stack is now being permanently updated..."
    
    # Ensure we are on main and up-to-date with GitHub
    echo "[INFO] Checking out main branch and fetching latest changes..."
    git checkout --force main
    git fetch origin main
    git reset --hard origin/main
    
    echo "⬇️ Pulling new images on main..."
    podman-compose pull
    
    echo "🔄 Restarting stack with latest main branch..."
    podman-compose down -t 30
    podman-compose up -d --force-recreate
    
    echo "🎉 Main stack successfully updated and running on the latest versions!"
fi

echo "✅ Poller run completed at $(date)."