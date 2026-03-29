# Automated Dependency Management & Testing

This guide describes how we keep the container images in this monitoring stack up-to-date automatically using Mend Renovate. It all runs on your local Fedora server. 

A custom poller automatically detects pending Renovate Pull Requests, checks them out, starts the updated stack, validates the health of all services, and reports back to GitHub with labels, comments, and (on failure) issues.

## 1. Goal of the Scripts

The primary goal of these scripts is to safely and automatically update container images without human intervention, while guaranteeing that the production monitoring stack remains stable. 

To achieve this, we use three distinct scripts working together:
1.  **`renovate.sh`**: Runs the Mend Renovate bot locally via Podman to scan the repository for outdated container images and creates Pull Requests on GitHub.
2.  **`poll-renovate-prs.sh`**: The orchestrator. It polls GitHub for open Renovate PRs, checks out the code, runs the test script, handles the GitHub administration (merging, labeling, commenting), and ensures the main production stack is updated.
3.  **`run-tests.sh`**: The validation suite. It verifies that all 19 required containers are running, waits for health checks (like MinIO and Keep-db) to pass, and uses an ephemeral curl container within the internal Podman network to test all API endpoints.

## 2. The Renovate & Poller Workflow

The complete lifecycle of a container update looks like this:

1. **Scan & PR Creation**: `renovate.sh` runs and detects an outdated image (e.g., `grafana/alloy`). It creates a Pull Request and applies the `renovate` label. Note: PRs labeled with `major-update` are ignored by the automated poller and require manual review.
2. **Detection & State Tracking**: `poll-renovate-prs.sh` detects the open PR. It checks the `pr_state.json` file to see if the latest commit SHA has already been tested to avoid redundant runs.
3. **Checkout & Teardown**: The poller checks out the PR branch locally, pulls the new images, and safely tears down the current running stack (timeout 30s).
4. **Validation**: The poller brings up the stack with the updated configuration (`--force-recreate`) and triggers `run-tests.sh`.
5. **Results Handling**:
   * **On Success**: The script applies the `test-passed` label, posts a successful log comment on the PR, merges the PR into `main`, and deletes the remote branch. If a previous failure issue existed, it is automatically closed.
   * **On Failure**: The script applies the `test-failed` label, creates a GitHub Issue containing the error logs, and immediately **rolls back** to the stable base branch to restore the working stack.
6. **Production Update**: If any PRs were successfully merged during the run, the poller checks out the `main` branch, pulls the latest images, and restarts the production stack so it runs the newly merged versions.

## 2. Prerequisites

Before running the automation, ensure your environnment is properly configured.

### 2.1 Required Packages
Ensure you have the GitHub CLI (`gh`) and `jq` installed:
```bash
sudo dnf install jq gh -y
```

### 2.2 GitHub Authentication
The GitHub CLI must be authenticated to interact with repositories, PRs, and Issues. Create a Personal Access Token (classic) with repo scope and export it:
```bash
export GITHUB_COM_TOKEN='pat_*****************************************'
echo "$GITHUB_COM_TOKEN" | gh auth login --with-token
```

### 2.3 Set required enviroment variables
```bash
export GITHUB_COM_TOKEN="your_personal_access_token"
export RENOVATE_GIT_AUTHOR="Your Name <your.email@example.com>"
export REPO="tedsluis/monitoring" # Adjust to your repository format: owner/repo
```

### 2.4 Add Github labels

The scripts use specific labels to track status. Create them once in your repository:
```bash
gh label create "test-passed" --color "0E8A16" --description "Automated smoke test passed"
gh label create "test-failed" --color "D93F0B" --description "Automated smoke test failed"
✓ Label "test-passed" created in tedsluis/monitoring
✓ Label "test-failed" created in tedsluis/monitoring

```

## 3. Execution Examples
You can run these scripts manually for debugging or immediate updates.

### 3.1 Running Renovate

To manually trigger the Renovate bot to scan for updates and create PRs:
```bash
$ ./renovate.sh 
🚀 Starting Mend Renovate via Podman...
 INFO: Renovate started
       "renovateVersion": "43.77.7"
 INFO: Repository started (repository=tedsluis/monitoring)
       "renovateVersion": "43.77.7"
 INFO: Dependency extraction complete (repository=tedsluis/monitoring, baseBranch=main)
       "stats": {
         "managers": {"docker-compose": {"fileCount": 1, "depCount": 19}},
         "total": {"fileCount": 1, "depCount": 19}
       }
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(Use `node --trace-warnings ...` to show where the warning was created)
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
(node:4) MetadataLookupWarning: received unexpected error = All promises were rejected code = UNKNOWN
 INFO: Branch created (repository=tedsluis/monitoring, branch=renovate/observability-extras)
       "commitSha": "4f91d4452a4dedd2b53a374838356c4e4c171017"
 INFO: PR created (repository=tedsluis/monitoring, branch=renovate/observability-extras)
       "pr": 16,
       "prTitle": "chore(deps): update observability tools to v0.148.0",
       "labels": []
 INFO: Deleting orphan branch (repository=tedsluis/monitoring, branch=renovate/minor-patch)
 INFO: Repository finished (repository=tedsluis/monitoring)
       "cloned": true,
       "durationMs": 61442,
       "result": "done",
       "status": "activated",
       "enabled": true,
       "onboarded": true
 INFO: Renovate was run at log level "info". Set LOG_LEVEL=debug in environment variables to see extended debug logs.
✅ Renovate run is complete. Check your GitHub repository for possible Pull Requests!
```

The log file created during the run of `renovate.sh` is stored in **./logs/pr-*.log**

### 3.2 Running the Poller

To manually trigger the poller to process any open Renovate PRs:
```bash
$ ./poll-renovate-prs.sh
[INFO] Verifying required directories and state files...
🔄 Starting Renovate PR Poller at Mon Mar 23 07:05:12 AM CET 2026
[INFO] Fetching open Pull Requests with the label 'renovate' from tedsluis/monitoring...
----------------------------------------
📌 Inspecting PR #16 (Branch: renovate/observability-extras)
[INFO] Fetching the latest commit SHA for PR #16...
[DEBUG] Current PR SHA: 4f91d4452a4dedd2b53a374838356c4e4c171017
[DEBUG] Last tested SHA: None
[DEBUG] Current status in state file: None
⚙️ New or updated PR found. Starting test cycle...
[INFO] Base branch identified as: main (SHA: cdfd04b67e96370410aafd7496e22b4f4253997a)
[INFO] Executing git operations: fetching and checking out branch 'renovate/observability-extras'...
remote: Enumerating objects: 5, done.
remote: Counting objects: 100% (5/5), done.
remote: Compressing objects: 100% (1/1), done.
remote: Total 3 (delta 2), reused 3 (delta 2), pack-reused 0 (from 0)
Unpacking objects: 100% (3/3), 384 bytes | 384.00 KiB/s, done.
From github.com:tedsluis/monitoring
 * branch            renovate/observability-extras -> FETCH_HEAD
 * [new branch]      renovate/observability-extras -> origin/renovate/observability-extras
branch 'renovate/observability-extras' set up to track 'origin/renovate/observability-extras'.
Switched to a new branch 'renovate/observability-extras'
From github.com:tedsluis/monitoring
 * branch            renovate/observability-extras -> FETCH_HEAD
Already up to date.
🚀 Starting containers for PR #16...
[INFO] Running 'podman-compose pull' to ensure all images are up to date...
[INFO] Tearing down any existing stack (timeout 30s)...  
[INFO] Bringing up the new stack with '--force-recreate'...
🔬 Running tests... (Output will be heavily logged in /home/tedsluis/monitoring/logs/pr-16-1774245969.log)
✅ Test passed for PR #16!
https://github.com/tedsluis/monitoring/pull/16
https://github.com/tedsluis/monitoring/pull/16#issuecomment-4108234413
🔀 Merging PR #16 into main...
✓ Merged pull request tedsluis/monitoring#16 (chore(deps): update observability tools to v0.148.0)
✓ Deleted remote branch renovate/observability-extras
✅ PR successfully merged!
[INFO] Bringing down the test stack...
[INFO] Syncing local base branch (main) with origin...
Switched to branch 'main'
Your branch is up to date with 'origin/main'.
remote: Enumerating objects: 1, done.
remote: Counting objects: 100% (1/1), done.
remote: Total 1 (delta 0), reused 0 (delta 0), pack-reused 0 (from 0)
Unpacking objects: 100% (1/1), 932 bytes | 466.00 KiB/s, done.
From github.com:tedsluis/monitoring
   cdfd04b..9ef55c7  main       -> origin/main
HEAD is now at 9ef55c7 Merge pull request #16 from tedsluis/renovate/observability-extras
========================================
🚀 PRs have been successfully merged!
The production (main) stack is now being permanently updated...
[INFO] Checking out main branch and fetching latest changes...
Already on 'main'
Your branch is up to date with 'origin/main'.
From github.com:tedsluis/monitoring
 * branch            main       -> FETCH_HEAD
HEAD is now at 9ef55c7 Merge pull request #16 from tedsluis/renovate/observability-extras
⬇️ Pulling new images on main...
🔄 Restarting stack with latest main branch...
🎉 Main stack successfully updated and running on the latest versions!
https://github.com/tedsluis/monitoring/pull/16#issuecomment-4108240074
[INFO] Performing safe image cleanup (removing untagged images older than 7 days)...
✅ Poller run completed at Mon Mar 23 07:08:21 AM CET 2026.
```

The test log file created during the `poll-renovate-prs.sh` is stored in **./logs/pr-*.log**

### 3.3 Running Tests Manually
If you want to validate the stack without interacting with GitHub:
```bash
$ ./run-tests.sh 
========================================
🚀 Starting Automated Validation Suite
========================================
🔍 [CHECK] Smoketest: Are all defined containers running?
   [INFO] Expected container count from compose.yml: 19
   [INFO] Currently running containers: 19
✅ [SUCCESS] All required containers are running.
----------------------------------------
⏳ [WAIT] Checking container health status (Minio, Loki, Tempo)...
   [INFO] Waiting for minio to become healthy...
   [SUCCESS] minio is healthy!
   [INFO] Waiting for keep-db to become healthy...
   [SUCCESS] keep-db is healthy!
🔍 [CHECK] Identifying internal Podman network...
🔌 [INFO] Using internal network: monitoring_monitoring-net
   [INFO] Using ephemeral curl container for internal API testing.
----------------------------------------
🔍 [TEST] Prometheus API & Base Health
✅ [SUCCESS] Prometheus API is reachable and reports healthy.
----------------------------------------
🔍 [TEST] Prometheus Targets (Max 2 minutes wait)
   [INFO] Fetching Prometheus targets (Attempt 1/12)...
✅ [SUCCESS] All Prometheus targets are UP and successfully scraped.
----------------------------------------
🔍 [TEST] Grafana API
✅ [SUCCESS] Grafana is reachable and healthy.
----------------------------------------
🔍 [TEST] Alertmanager
✅ [SUCCESS] Alertmanager is reachable and healthy.
----------------------------------------
🔍 [TEST] Keep API
✅ [SUCCESS] Keep API is reachable and healthy.
----------------------------------------
🔍 [TEST] Traefik Routing (using Nginx)
✅ [SUCCESS] Traefik is routing requests correctly.
----------------------------------------
🔍 [TEST] Alloy
✅ [SUCCESS] Alloy is reachable and healthy.
----------------------------------------
🔍 [TEST] Blackbox Exporter
✅ [SUCCESS] Blackbox Exporter is reachable and healthy.
----------------------------------------
🔍 [TEST] Karma Dashboard
✅ [SUCCESS] Karma is reachable and healthy.
----------------------------------------
🔍 [TEST] Keep Frontend
✅ [SUCCESS] Keep Frontend is reachable and healthy.
----------------------------------------
🔍 [TEST] Loki
✅ [SUCCESS] Loki is reachable and healthy.
----------------------------------------
🔍 [TEST] MinIO
✅ [SUCCESS] MinIO is reachable and healthy.
----------------------------------------
🔍 [TEST] Nginx
✅ [SUCCESS] Nginx is reachable.
----------------------------------------
🔍 [TEST] Node Exporter
✅ [SUCCESS] Node Exporter is reachable.
----------------------------------------
🔍 [TEST] OpenTelemetry Collector
✅ [SUCCESS] OTel Collector is reachable.
----------------------------------------
🔍 [TEST] Podman Exporter
✅ [SUCCESS] Podman Exporter is reachable.
----------------------------------------
🔍 [TEST] Tempo
✅ [SUCCESS] Tempo is reachable and healthy.
----------------------------------------
🔍 [TEST] Webhook Tester
✅ [SUCCESS] Webhook Tester is reachable.
========================================
🎉 [COMPLETE] All tests completed successfully! Stack is stable.
```


## 3. Automation (Cron Setup)

To have this workflow operate autonomously, set up a cronjob. Running the poller every 15 minutes ensures you stay well within GitHub API rate limits while avoiding unnecessary server load. Open your crontab:
```bash
crontab -e
```
Add the following configuration (adjust the paths to match your actual environment):
```bash
# Export necessary variables for cron
GITHUB_COM_TOKEN="your_personal_access_token"
RENOVATE_GIT_AUTHOR="Your Name <your.email@example.com>"
REPO="tedsluis/monitoring"
# Run the poller every 15 minutes
*/15 * * * * cd /home/tedsluis/monitoring && ./poll-renovate-prs.sh >> /home/tedsluis/monitoring/logs/renovate-cron.log 2>&1

# Clean up old downloaded Podman images weekly on Sunday night at 03:00
0 3 * * 0 podman image prune -a -f
```

## 4. Reliability & Rollback Guarantees

* **Concurrency Locking:** The poller uses a lock file (`/tmp/renovate-poller.lock`). If a test cycle takes a long time, the lock prevents a new cron execution from interfering with the running process.
* **State Management:** `pr_state.json` tracks tested commits. If Renovate force-pushes a fix to a PR, the script detects the changed SHA and automatically re-tests the new commit.
* **Guaranteed Rollback:** Regardless of whether a test passes or fails, if the script encounters an error or finishes testing a failing PR, it executes a strict git checkout to your base branch (usually `main`) and forces a rebuild of the stable containers. Your production stack is therefore offline for only a brief period during the test cycle.