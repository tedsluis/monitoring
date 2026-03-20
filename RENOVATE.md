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
 INFO: Branch created (repository=tedsluis/monitoring, branch=renovate/minor-patch)
       "commitSha": "59d1762b5e73eb4e4161d2fc06adf3ddcb6e508c"
 INFO: PR created (repository=tedsluis/monitoring, branch=renovate/minor-patch)
       "pr": 11,
       "prTitle": "chore(deps): update minor & patch updates",
       "labels": []
 INFO: Repository finished (repository=tedsluis/monitoring)
       "cloned": true,
       "durationMs": 107365,
       "result": "done",
       "status": "activated",
       "enabled": true,
       "onboarded": true
 INFO: Renovate was run at log level "info". Set LOG_LEVEL=debug in environment variables to see extended debug logs.
✅ Renovate run is complete. Check your GitHub repository for possible Pull Requests!
```

Place run-tests.sh and poll-renovate-prs.sh in your /monitoring directory.

Step 5: Test the script manually

Before running the poller in the background, it is crucial to verify this manually once Renovate has created a PR:

```bash
./poll-renovate-prs.sh
```

The script will:

Fetch PRs.

Check out the PR branch and run podman-compose up -d.

Run run-tests.sh.

```bash
$ ./run-tests.sh 
========================================
🚀 Starting Automated Validation Suite
========================================
⏳ [WAIT] Allowing services to initialize (waiting 30 seconds)...
🔍 [CHECK] Smoketest: Are all defined containers running?
   [INFO] Expected container count from compose.yml: ~19
   [INFO] Currently running matched containers: 18
✅ [SUCCESS] All required containers are running.
🔍 [CHECK] Identifying internal Podman network...
🔌 [INFO] Using internal network: monitoring_monitoring-net
   [INFO] Using ephemeral curl container for internal API testing.
----------------------------------------
🔍 [TEST] Prometheus API & Base Health (Internal via prometheus:9090)
   [INFO] Executing HTTP GET http://prometheus:9090/-/healthy
✅ [SUCCESS] Prometheus API is reachable and reports healthy.
----------------------------------------
🔍 [TEST] Prometheus Targets (Max 2 minutes wait)
   [INFO] Fetching Prometheus targets (Attempt 1/12)...
✅ [SUCCESS] All Prometheus targets are UP and successfully scraped.
----------------------------------------
🔍 [TEST] Grafana API (Internal via grafana:3000)
   [INFO] Executing HTTP GET http://grafana:3000/api/health
✅ [SUCCESS] Grafana is reachable and healthy.
----------------------------------------
🔍 [TEST] Alertmanager (Internal via alertmanager:9093)
   [INFO] Executing HTTP GET http://alertmanager:9093/-/healthy
✅ [SUCCESS] Alertmanager is reachable and healthy.
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