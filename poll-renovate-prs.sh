#!/bin/bash
# poll-renovate-prs.sh - Checks, tests, merges and restarts the monitoring stack
set -euo pipefail

# Check if the REPO is available
if [ -z "$REPO" ]; then
    echo "Error: REPO is not set."
    echo "Usage: export REPO='owner/repo' && ./poll-renovate-prs.sh"
    echo "for example: export REPO='tedsluis/monitoring' && ./poll-renovate-prs.sh"
    exit 1
fi

# Variables
WORKDIR="$(pwd)"
STATE_FILE="$WORKDIR/pr_state.json"
LOCK_FILE="/tmp/renovate-poller.lock"
LOG_DIR="$WORKDIR/logs"

# Flags and tracking
MAIN_NEEDS_UPDATE=false
MERGED_PRS=()

# --- HELPER FUNCTIONS ---

# Safe state update using mktemp to prevent corruption
safe_state_update() {
    local jq_filter="$1"
    local tmpfile
    tmpfile=$(mktemp)
    jq "$jq_filter" "$STATE_FILE" > "$tmpfile" && mv "$tmpfile" "$STATE_FILE"
}

# Retry mechanism for temporary API/network errors
retry() {
    local n=1
    local max=3
    local delay=5
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                echo "[WARN] Command failed. Attempt $n/$max in $delay seconds..."
                sleep $delay;
            else
                echo "[ERROR] The command has failed after $max attempts."
                return 1
            fi
        }
    done
}

# --- INITIALIZATION ---

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

# Fetch open PRs that MUST be authored by you, have the 'renovate' label, and start with 'renovate/'
PRS=$(retry gh pr list --repo "$REPO" --state open --author "@me" --label "renovate" --json number,headRefName,headRepository,updatedAt --jq '.[] | select(.headRefName | startswith("renovate/")) | "\(.number) \(.headRefName) \(.updatedAt)"' || echo "")

if [ -z "$PRS" ]; then
    echo "✅ No open Renovate PRs found at this time."
    exit 0
fi

# --- MAIN LOOP ---

while read -r pr_number branch updated; do
    if [ -z "$pr_number" ]; then continue; fi
    
    echo "----------------------------------------"
    echo "📌 Inspecting PR #$pr_number (Branch: $branch)"

    # Exclude major updates for manual review
    if gh pr view "$pr_number" --repo "$REPO" --json labels --jq '.labels[].name' | grep -q "major-update"; then
        echo "⏩ PR #$pr_number has the 'major-update' label. Skipping for manual review."
        continue
    fi

    echo "[INFO] Fetching the latest commit SHA for PR #$pr_number..."
    current_sha=$(retry gh api "repos/$REPO/pulls/$pr_number" --jq .head.sha)
    last_sha=$(jq -r ".\"$pr_number\".last_commit_sha // empty" "$STATE_FILE")
    status=$(jq -r ".\"$pr_number\".status // empty" "$STATE_FILE")

    echo "[DEBUG] Current PR SHA: $current_sha"
    echo "[DEBUG] Last tested SHA: ${last_sha:-None}"
    echo "[DEBUG] Current status in state file: ${status:-None}"

    if [[ "$current_sha" == "$last_sha" && "$status" != "pending" ]]; then
        echo "⏩ PR #$pr_number (Commit: $current_sha) is already tested (Status: $status). Skipping."
        continue
    fi

    echo "⚙️ New or updated PR found. Starting test cycle..."
    
    # Update state to testing & save the timestamp
    safe_state_update ".\"$pr_number\".status = \"testing\" | .\"$pr_number\".last_commit_sha = \"$current_sha\" | .\"$pr_number\".timestamp = \"$(date -Iseconds)\""

    # Identify and save the working base branch commit for rollback purposes
    base_branch=$(retry gh pr view "$pr_number" --repo "$REPO" --json baseRefName --jq .baseRefName)
    base_sha=$(git ls-remote origin "$base_branch" | awk '{print $1}')
    safe_state_update ".\"$pr_number\".last_working_base_sha = \"$base_sha\""
    echo "[INFO] Base branch identified as: $base_branch (SHA: $base_sha)"
    
    # Checkout branch and reset the environment
    echo "[INFO] Executing git operations: fetching and checking out branch '$branch'..."
    retry git fetch origin "$branch"
    git checkout --force "$branch"
    git pull origin "$branch"

    echo "🚀 Starting containers for PR #$pr_number..."
    echo "[INFO] Running 'podman-compose pull' to ensure all images are up to date..."
    retry podman-compose pull
    echo "[INFO] Tearing down any existing stack (timeout 30s)..."
    podman-compose down -t 30
    
    TEST_LOG="$LOG_DIR/pr-${pr_number}-$(date +%s).log"
    stack_started=true

    # Check podman-compose up -d exit-code
    echo "[INFO] Bringing up the new stack with '--force-recreate'..."
    if ! podman-compose up -d --force-recreate; then
        echo "❌ podman-compose up -d failed! Check for port conflicts or invalid configs." | tee "$TEST_LOG"
        stack_started=false
    fi

    # Executing tests with timeout if stack successfully started
    if [ "$stack_started" = true ]; then
        echo "🔬 Running tests... (Output will be heavily logged in $TEST_LOG)"
        if timeout 300 ./run-tests.sh > "$TEST_LOG" 2>&1; then
            test_passed=true
        else
            test_passed=false
        fi
    else
        test_passed=false
    fi

    # --- HANDLE TEST RESULTS ---

    if [ "$test_passed" = true ]; then
        echo "✅ Test passed for PR #$pr_number!"
        
        retry gh pr edit "$pr_number" --repo "$REPO" --add-label "test-passed" --remove-label "test-failed" 2>/dev/null || true
        
        LOG_CONTENT=$(tail -n 50 "$TEST_LOG")
        retry gh pr comment "$pr_number" --repo "$REPO" --body "✅ **Automatic Validation Passed!**
The stack successfully started on commit \`$current_sha\`. No healthcheck errors found.

<details><summary>View the successful test log</summary>

\`\`\`text
$LOG_CONTENT
\`\`\`
</details>"
        
        ISSUE_NUM=$(jq -r ".\"$pr_number\".issue_number // empty" "$STATE_FILE")
        if [ -n "$ISSUE_NUM" ] && [ "$ISSUE_NUM" != "null" ]; then
            echo "✅ Closing previously failed issue #$ISSUE_NUM..."
            retry gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "✅ Test successfully completed on the newer commit \`$current_sha\`. This issue is automatically closed."
            retry gh issue close "$ISSUE_NUM" --repo "$REPO"
            safe_state_update "del(.\"$pr_number\".issue_number)"
        fi

        safe_state_update ".\"$pr_number\".status = \"passed\""

        echo "🔀 Merging PR #$pr_number into $base_branch..."
        if retry gh pr merge "$pr_number" --repo "$REPO" --merge --delete-branch; then
            echo "✅ PR successfully merged!"
            MAIN_NEEDS_UPDATE=true
            MERGED_PRS+=("$pr_number")
            
            echo "[INFO] Bringing down the test stack..."
            podman-compose down -t 30
            
            # Update base branch after merge to prevent stale base for the next iteration
            echo "[INFO] Syncing local base branch ($base_branch) with origin..."
            git checkout --force "$base_branch"
            retry git fetch origin
            git reset --hard origin/"$base_branch"
        else
            echo "⚠️ Could not merge PR automatically. Rolling back..."
            # Rollback after merge error using pull/reset
            git checkout --force "$base_branch"
            retry git fetch origin
            git reset --hard origin/"$base_branch"
            
            podman-compose down -t 30
            podman-compose up -d --force-recreate
        fi

    else
        echo "❌ Test failed for PR #$pr_number!"
        
        retry gh pr edit "$pr_number" --repo "$REPO" --add-label "test-failed" --remove-label "test-passed" 2>/dev/null || true
        
        FAIL_LOG=$(tail -n 50 "$TEST_LOG")
        ISSUE_NUM=$(jq -r ".\"$pr_number\".issue_number // empty" "$STATE_FILE")
        
        if [ -z "$ISSUE_NUM" ] || [ "$ISSUE_NUM" == "null" ]; then
            echo "[INFO] Creating a new GitHub Issue for the failed test..."
            # Safe ISSUE_NUM parsing via --json
            ISSUE_NUM=$(gh issue create --repo "$REPO" \
                --title "🚨 Test Failed: Renovate PR #$pr_number" \
                --body "The automatic test failed for PR #$pr_number (Commit \`$current_sha\`).
                
<details><summary>View the error log</summary>

\`\`\`text
$FAIL_LOG
\`\`\`
</details>

*System rolled back to the stable branch.*" \
                --label "bug" \
                --json number --jq .number)

            echo "[INFO] New issue created: #$ISSUE_NUM. Updating state file."
            safe_state_update ".\"$pr_number\".issue_number = \"$ISSUE_NUM\""

            retry gh pr comment "$pr_number" --repo "$REPO" --body "❌ **Automatic Validation Failed.**
I have created an issue with the log details: #$ISSUE_NUM
*System has been rolled back to the latest stable branch.*"

        else
            echo "[INFO] Updating existing GitHub Issue #$ISSUE_NUM..."
            retry gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "🚨 **Failed again** on newer commit \`$current_sha\`.

<details><summary>View the new error log</summary>

\`\`\`text
$FAIL_LOG
\`\`\`
</details>"
            retry gh pr comment "$pr_number" --repo "$REPO" --body "❌ **Automatic Validation Failed (Update).** See issue #$ISSUE_NUM"
        fi

        safe_state_update ".\"$pr_number\".status = \"failed\""
        
        # ROLLBACK TO STABLE STATE including current origin sync
        echo "⏪ Rolling back to base branch ($base_branch)..."
        git checkout --force "$base_branch"
        retry git fetch origin
        git reset --hard origin/"$base_branch"
        
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
    
    echo "[INFO] Checking out main branch and fetching latest changes..."
    git checkout --force main
    retry git fetch origin main
    git reset --hard origin/main
    
    echo "⬇️ Pulling new images on main..."
    retry podman-compose pull
    
    echo "🔄 Restarting stack with latest main branch..."
    podman-compose down -t 30
    podman-compose up -d --force-recreate
    
    echo "🎉 Main stack successfully updated and running on the latest versions!"

    # Notification after main update for all successful PRs in this run
    for merged_pr in "${MERGED_PRS[@]}"; do
        retry gh pr comment "$merged_pr" --repo "$REPO" --body "🎉 **Production Updated!**
The main monitoring stack has been successfully restarted with the code from this PR."
    done
fi

# ---------------------------------------------------------
# CLEANUP
# ---------------------------------------------------------
echo "[INFO] Performing safe image cleanup (removing untagged images older than 7 days)..."
podman image prune -f --filter "until=168h"

echo "✅ Poller run completed at $(date)."