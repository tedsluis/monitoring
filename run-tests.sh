#!/bin/bash
# run-tests.sh - Runs validations on the monitoring stack via an internal ephemeral container
set -e

echo "========================================"
echo "🚀 Starting Automated Validation Suite"
echo "========================================"

# Geef podman een paar seconden om de processen te registreren
sleep 5 

echo "🔍 [CHECK] Smoketest: Are all defined containers running?"
EXPECTED_COUNT=$(grep -c 'container_name:' compose.yml || echo 19)
echo "   [INFO] Expected container count from compose.yml: ${EXPECTED_COUNT}"

# Gebruik de robuuste compose-ps commando's en strip witregels
RUNNING_COUNT=$(podman compose ps -q | wc -l | tr -d ' ')
echo "   [INFO] Currently running containers: ${RUNNING_COUNT}"

if [ "$RUNNING_COUNT" -lt "$EXPECTED_COUNT" ]; then
    echo "❌ [ERROR] Not all containers are running. Expected $EXPECTED_COUNT, found $RUNNING_COUNT"
    echo "   [DEBUG] Dumping 'podman compose ps' for troubleshooting:"
    podman compose ps
    exit 1
fi
echo "✅ [SUCCESS] All required containers are running."

echo "----------------------------------------"
echo "⏳ [WAIT] Checking container health status (Minio, Loki, Tempo)..."

# Wacht slim op de containers met een native healthcheck
for service in minio loki tempo keep-db; do
    echo "   [INFO] Waiting for $service to become healthy..."
    for i in {1..12}; do
        # Podman inspect leest de native container health status uit
        STATUS=$(podman inspect -f '{{.State.Health.Status}}' $service 2>/dev/null || echo "unknown")
        
        if [ "$STATUS" == "healthy" ]; then
            echo "   [SUCCESS] $service is healthy!"
            break
        fi
        
        if [ "$i" -eq 12 ]; then
            echo "❌ [ERROR] $service failed to become healthy within 60 seconds. Final status: $STATUS"
            podman logs --tail 20 $service
            exit 1
        fi
        sleep 5
    done
done

# Find the actual name of the internal Podman network
echo "🔍 [CHECK] Identifying internal Podman network..."
NETWORK=$(podman network ls --format "{{.Name}}" | grep "monitoring-net" | head -n 1)
if [ -z "$NETWORK" ]; then
    echo "❌ [ERROR] Could not find the podman network 'monitoring-net'."
    exit 1
fi
echo "🔌 [INFO] Using internal network: $NETWORK"

CURL_CMD="podman run --rm --network $NETWORK docker.io/curlimages/curl:latest"
echo "   [INFO] Using ephemeral curl container for internal API testing."

echo "----------------------------------------"
echo "🔍 [TEST] Prometheus API & Base Health"
$CURL_CMD -sSf -o /dev/null http://prometheus:9090/-/healthy || { echo "❌ [ERROR] Prometheus is not healthy"; exit 1; }
echo "✅ [SUCCESS] Prometheus API is reachable and reports healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Prometheus Targets (Max 2 minutes wait)"
MAX_RETRIES=12
RETRY_COUNT=0
FAILED_TARGETS=1

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "   [INFO] Fetching Prometheus targets (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)..."
    TARGET_JSON=$($CURL_CMD -s http://prometheus:9090/api/v1/targets || echo '{"status":"error"}')
    
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
    echo "$TARGET_JSON" | jq '.data.activeTargets[]? | select(.health != "up") | {job: .labels.job, instance: .labels.instance, health: .health, error: .lastError}'
    exit 1
fi

echo "----------------------------------------"
echo "🔍 [TEST] Grafana API"
$CURL_CMD -sSf -o /dev/null http://grafana:3000/api/health || { echo "❌ [ERROR] Grafana API unreachable"; exit 1; }
echo "✅ [SUCCESS] Grafana is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Alertmanager"
$CURL_CMD -sSf -o /dev/null http://alertmanager:9093/-/healthy || { echo "❌ [ERROR] Alertmanager is not healthy"; exit 1; }
echo "✅ [SUCCESS] Alertmanager is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Keep API"
$CURL_CMD -sSf -o /dev/null http://keep-backend:8080/health || { echo "❌ [ERROR] Keep API is not healthy"; exit 1; }
echo "✅ [SUCCESS] Keep API is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Traefik Routing (using Nginx)"
$CURL_CMD -sSf -H "Host: localhost" -o /dev/null http://traefik:80 || { echo "❌ [ERROR] Traefik routing is failing"; exit 1; }
echo "✅ [SUCCESS] Traefik is routing requests correctly."

echo "========================================"
echo "🎉 [COMPLETE] All tests completed successfully! Stack is stable."
exit 0