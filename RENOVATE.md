# Automated Testing of Renovate PRs

This guide describes how to convert your local Fedora server into an automated test environment. A poller checks out pending Renovate Pull Requests, starts them, validates them, and reports back to GitHub with labels, comments, and (on failure) issues.

Step 1: Preparations on Fedora

Make sure the required command-line tools are installed:
```bash
sudo dnf install jq gh -y
```

Step 2: GitHub Authentication

The GitHub CLI (gh) requires a token with permissions for repos and issues.
Since this is an automated process, we authenticate gh securely in a session:

Create a (classic) Personal Access Token in GitHub with the repo scope and add it in environment variable `export GITHUB_COM_TOKEN='pat_*****************************************'`.

```bash
echo "$GITHUB_COM_TOKEN" | gh auth login --with-token
```

Step 3: Add labels

Create the labels once in your GitHub repository:
```bash
gh label create "test-passed" --color "0E8A16" --description "Automated smoke test passed"
gh label create "test-failed" --color "D93F0B" --description "Automated smoke test failed"
✓ Label "test-passed" created in tedsluis/monitoring
✓ Label "test-failed" created in tedsluis/monitoring

```

Step 4: Run scripts

run tests:
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

Run renovate:
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

Check pull requests:
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
🔬 Running tests... (Output will be heavily logged in /home/tedsluis/monitoring/test-logs/pr-16-1774245969.log)
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

Run tests:
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

Update GitHub depending on the result.

Always roll back cleanly (git checkout main) and start the stable stack.

Step 6: Automation (Cron / Systemd)

To have this work autonomously, set up a cronjob. We choose every 15 minutes (to stay well within API rate limits and avoid unnecessary server load).

Open your crontab:
```bash
crontab -e
```

Add the following lines (adjust the paths to your actual locations):
```bash
# Run the poller every 15 minutes
*/15 * * * * cd /home/tedsluis/monitoring && ./poll-renovate-prs.sh >> /tmp/renovate-poller.log 2>&1

# Clean up old downloaded podman images weekly on Sunday night at 03:00
0 3 * * 0 podman image prune -a -f
```

Operation & Rollback Guarantee

Locking: If tests take long, the /tmp/renovate-poller.lock file prevents a new cronjob from running through the old one.

State Management: The pr_state.json file keeps track of which commit SHA was tested. Does Renovate push a fix to the PR? Then the script sees a changed SHA and runs the test again.

Rollback: Regardless of whether a test passes or fails, the script always ends with a git checkout to your base branch (usually main) and forces a rebuild of your stable containers. Your production stack is therefore offline for at most a few minutes per PR test.