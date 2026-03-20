#!/bin/bash
# run-tests.sh - Runs validations on the monitoring stack via an internal ephemeral container
set -e

echo "⏳ Waiting for services to start (30s)..."
sleep 30

echo "🔍 Smoketest: Are all defined containers running?"
# Get the expected number of services from compose.yml (simple check)
EXPECTED_COUNT=$(grep -c 'container_name:' compose.yml || echo 19)
RUNNING_COUNT=$(podman ps --format "{{.Names}}" | grep -E 'alertmanager|alloy|blackbox-exporter|grafana|karma|keep-db|keep-backend|keep-frontend|loki|minio|nginx|node-exporter|otel-collector|podman-exporter|prometheus|tempo|traefik|webhook-tester' | wc -l)

if [ "$RUNNING_COUNT" -lt 18 ]; then
    echo "❌ Error: Not all containers are running. Expected ~18+, found $RUNNING_COUNT"
    podman ps -a
    exit 1
fi
echo "✅ All containers are running."

# Find the actual name of the internal Podman network (usually monitoring_monitoring-net)
NETWORK=$(podman network ls --format "{{.Name}}" | grep "monitoring-net" | head -n 1)
if [ -z "$NETWORK" ]; then
    echo "❌ Error: Could not find the podman network 'monitoring-net'."
    exit 1
fi

echo "🔌 Using internal network: $NETWORK"
# Base curl command with the ephemeral container
CURL_CMD="podman run --rm --network $NETWORK docker.io/curlimages/curl:latest"

echo "🔍 Test: Prometheus API & Targets (Internal via container:9090)"
$CURL_CMD -sSf -o /dev/null http://prometheus:9090/-/healthy || { echo "❌ Prometheus is not healthy"; exit 1; }

# Fetch JSON locally via curl and parse it with local 'jq'
FAILED_TARGETS=$($CURL_CMD -s http://prometheus:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health == "down")] | length')

if [ "$FAILED_TARGETS" != "0" ]; then
    echo "❌ Error: $FAILED_TARGETS Prometheus targets are DOWN (or fetch failed)."
    exit 1
fi
echo "✅ Prometheus targets are UP."

echo "🔍 Test: Grafana API (Internal via container:3000)"
$CURL_CMD -sSf -o /dev/null http://grafana:3000/api/health || { echo "❌ Grafana API unreachable"; exit 1; }
echo "✅ Grafana is reachable."

echo "🔍 Test: Alertmanager (Internal via container:9093)"
$CURL_CMD -sSf -o /dev/null http://alertmanager:9093/-/healthy || { echo "❌ Alertmanager is not healthy"; exit 1; }
echo "✅ Alertmanager is reachable."

echo "🎉 All tests completed successfully!"
exit 0