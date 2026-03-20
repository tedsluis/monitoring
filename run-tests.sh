#!/bin/bash
# run-tests.sh - Runs validations on the monitoring stack via an internal ephemeral container
set -e

echo "========================================"
echo "🚀 Starting Automated Validation Suite"
echo "========================================"

echo "⏳ [WAIT] Allowing services to initialize (waiting 30 seconds)..."
sleep 30

echo "🔍 [CHECK] Smoketest: Are all defined containers running?"
# Get the expected number of services from compose.yml
EXPECTED_COUNT=$(grep -c 'container_name:' compose.yml || echo 19)
echo "   [INFO] Expected container count from compose.yml: ~${EXPECTED_COUNT}"

RUNNING_CONTAINERS=$(podman ps --format "{{.Names}}" | grep -E 'alertmanager|alloy|blackbox-exporter|grafana|karma|keep-db|keep-backend|keep-frontend|loki|minio|nginx|node-exporter|otel-collector|podman-exporter|prometheus|tempo|traefik|webhook-tester')
RUNNING_COUNT=$(echo "$RUNNING_CONTAINERS" | wc -l)
echo "   [INFO] Currently running matched containers: ${RUNNING_COUNT}"

if [ "$RUNNING_COUNT" -lt 18 ]; then
    echo "❌ [ERROR] Not all containers are running. Expected ~18+, found $RUNNING_COUNT"
    echo "   [DEBUG] Dumping 'podman ps -a' for troubleshooting:"
    podman ps -a
    exit 1
fi
echo "✅ [SUCCESS] All required containers are running."

# Find the actual name of the internal Podman network (usually monitoring_monitoring-net)
echo "🔍 [CHECK] Identifying internal Podman network..."
NETWORK=$(podman network ls --format "{{.Name}}" | grep "monitoring-net" | head -n 1)
if [ -z "$NETWORK" ]; then
    echo "❌ [ERROR] Could not find the podman network 'monitoring-net'."
    exit 1
fi
echo "🔌 [INFO] Using internal network: $NETWORK"

# Base curl command with the ephemeral container
CURL_CMD="podman run --rm --network $NETWORK docker.io/curlimages/curl:latest"
echo "   [INFO] Using ephemeral curl container for internal API testing."

echo "----------------------------------------"
echo "🔍 [TEST] Prometheus API & Base Health (Internal via prometheus:9090)"
echo "   [INFO] Executing HTTP GET http://prometheus:9090/-/healthy"
$CURL_CMD -sSf -o /dev/null http://prometheus:9090/-/healthy || { echo "❌ [ERROR] Prometheus is not healthy"; exit 1; }
echo "✅ [SUCCESS] Prometheus API is reachable and reports healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Prometheus Targets (Max 2 minutes wait)"
MAX_RETRIES=12
RETRY_COUNT=0
FAILED_TARGETS=1

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "   [INFO] Fetching Prometheus targets (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
    # Query the targets. If the call fails, return an error JSON.
    TARGET_JSON=$($CURL_CMD -s http://prometheus:9090/api/v1/targets || echo '{"status":"error"}')
    
    # Use jq to check if the API is successful AND if there are targets that are not 'up'.
    # If there are no activeTargets yet or the API returns an error, this results in 1 (fail).
    FAILED_TARGETS=$(echo "$TARGET_JSON" | jq -e 'if .status == "success" and (.data.activeTargets | length) > 0 then [.data.activeTargets[] | select(.health != "up")] | length else 1 end' 2>/dev/null || echo "1")
    
    if [ "$FAILED_TARGETS" == "0" ]; then
        echo "✅ [SUCCESS] All Prometheus targets are UP and successfully scraped."
        break
    else
        echo "⚠️  [WARN] Still $FAILED_TARGETS target(s) DOWN or not scraped yet. Retrying in 10s..."
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ "$FAILED_TARGETS" != "0" ]; then
    echo "❌ [ERROR] After 2 minutes, there are still targets DOWN or inaccessible."
    echo "   [DEBUG] Dumping failed target details for GitHub Issue:"
    # Print exactly WHICH targets are failing
    echo "$TARGET_JSON" | jq '.data.activeTargets[]? | select(.health != "up") | {job: .labels.job, instance: .labels.instance, health: .health, error: .lastError}'
    exit 1
fi

echo "----------------------------------------"
echo "🔍 [TEST] Grafana API (Internal via grafana:3000)"
echo "   [INFO] Executing HTTP GET http://grafana:3000/api/health"
$CURL_CMD -sSf -o /dev/null http://grafana:3000/api/health || { echo "❌ [ERROR] Grafana API unreachable"; exit 1; }
echo "✅ [SUCCESS] Grafana is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Alertmanager (Internal via alertmanager:9093)"
echo "   [INFO] Executing HTTP GET http://alertmanager:9093/-/healthy"
$CURL_CMD -sSf -o /dev/null http://alertmanager:9093/-/healthy || { echo "❌ [ERROR] Alertmanager is not healthy"; exit 1; }
echo "✅ [SUCCESS] Alertmanager is reachable and healthy."

echo "========================================"
echo "🎉 [COMPLETE] All tests completed successfully! Stack is stable."
exit 0