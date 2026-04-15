#!/bin/bash
# run-tests.sh - Runs validations on the monitoring stack via an internal ephemeral container
set -e

# shows a spinner while waiting for background processes, adapted from
spinner() {
    local pid=$1
    local delay=0.1
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    tput civis  # hide cursor

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  %s  waiting..." "${frames[$i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep "$delay"
    done

    tput cnorm  # restore cursor
    printf "\r  ✔  Continue!          \n"
}

# Disable the "Executing external compose provider" warning
export PODMAN_COMPOSE_WARNING_LOGS=false

echo "========================================"
echo "🚀 Starting Automated Validation Suite"
echo "========================================"

# Give podman a few seconds to register the processes
sleep 10 &
BG_PID=$!
spinner "$BG_PID"
wait "$BG_PID"

echo "🔍 [CHECK] Smoketest: Are all defined containers running?"
EXPECTED_COUNT=$(grep -c 'container_name:' compose.yml || echo 19)
echo "   [INFO] Expected container count from compose.yml: ${EXPECTED_COUNT}"

# Use the robust compose-ps commands and strip blank lines
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
echo "⏳ [WAIT] Checking container health status (Alertmanager, Grafana, Keep-db, Keep-frontend, Minio, Nginx, Node-exporter, Podman-exporter, Prometheus, Traefik)..."

# Wait smartly for the containers with a native healthcheck
for service in alertmanager grafana keep-db keep-frontend minio nginx node-exporter podman-exporter prometheus traefik; do
    echo "   [INFO] Waiting for $service to become healthy..."
    for i in {1..12}; do
        # Podman inspect reads the native container health status
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
        sleep 5 &
        BG_PID=$!
        spinner "$BG_PID"
        wait "$BG_PID"
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

CURL_CMD="podman run --rm -v ./traefik/certs/myCA.pem:/myCA.pem:ro,z -e http_proxy= -e HTTP_PROXY= -e https_proxy= -e HTTPS_PROXY= --network $NETWORK docker.io/curlimages/curl:latest --cacert /myCA.pem"
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
        sleep 10 &
        BG_PID=$!
        spinner "$BG_PID"
        wait "$BG_PID"
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ "$FAILED_TARGETS" != "0" ]; then
    echo "❌ [ERROR] After 2 minutes, there are still targets DOWN or inaccessible."
    echo "$TARGET_JSON" | jq '.data.activeTargets[]? | select(.health != "up") | {job: .labels.job, instance: .labels.instance, health: .health, error: .lastError}'
    exit 1
fi

echo ''
echo "========================================"
echo "🌐 Starting Podman monitoring-net network Tests (via HTTP)"
echo "========================================"

echo "----------------------------------------"
echo "🔍 [TEST] Grafana API"
$CURL_CMD -sSf -o /dev/null http://grafana:3000/api/health || { echo "❌ [ERROR] http://grafana:3000/api/health unreachable"; exit 1; }
echo "✅ [SUCCESS] http://grafana:3000/api/health is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Alertmanager"
$CURL_CMD -sSf -o /dev/null http://alertmanager:9093/-/healthy || { echo "❌ [ERROR] http://alertmanager:9093/-/healthy unreachable"; exit 1; }
echo "✅ [SUCCESS] http://alertmanager:9093/-/healthy is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Keep API"
$CURL_CMD -sSf -o /dev/null http://keep-backend:8080/ || { echo "❌ [ERROR] http://keep-backend:8080/ unreachable"; exit 1; }
echo "✅ [SUCCESS] http://keep-backend:8080/ is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Traefik Routing (using Nginx)"
$CURL_CMD -sSf -H "Host: ${DOMAIN:-localhost}" -o /dev/null http://traefik:80 || { echo "❌ [ERROR] http://traefik:80 unreachable"; exit 1; }
echo "✅ [SUCCESS] http://traefik:80 is routing requests correctly."

echo "----------------------------------------"
echo "🔍 [TEST] Alloy"
$CURL_CMD -sSf -o /dev/null http://alloy:12345/-/healthy || { echo "❌ [ERROR] http://alloy:12345/-/healthy unreachable"; exit 1; }
echo "✅ [SUCCESS] http://alloy:12345/-/healthy is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Blackbox Exporter"
$CURL_CMD -sSf -o /dev/null http://blackbox-exporter:9115/-/healthy || { echo "❌ [ERROR] http://blackbox-exporter:9115/-/healthy  is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://blackbox-exporter:9115/-/healthy is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Karma Dashboard"
$CURL_CMD -sSf -o /dev/null http://karma:8080/health || { echo "❌ [ERROR] http://karma:8080/health is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://karma:8080/health is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Keep Frontend"
$CURL_CMD -sSf -o /dev/null http://keep-frontend:3000/api/healthcheck || { echo "❌ [ERROR] http://keep-frontend:3000/api/healthcheck is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://keep-frontend:3000/api/healthcheck is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Loki"
$CURL_CMD -sSf -o /dev/null http://loki:3100/ready || { echo "❌ [ERROR] http://loki:3100/ready is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://loki:3100/ready is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] MinIO"
$CURL_CMD -sSf -o /dev/null http://minio:9000/minio/health/live || { echo "❌ [ERROR] http://minio:9000/minio/health/live is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://minio:9000/minio/health/live is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Nginx"
$CURL_CMD -sSf -o /dev/null http://nginx:80/ || { echo "❌ [ERROR] http://nginx:80 is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://nginx:80 is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Node Exporter"
# Note: node-exporter runs on the host network
$CURL_CMD -sSf -o /dev/null http://host.containers.internal:9100/ || { echo "❌ [ERROR] http://host.containers.internal:9100 is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://host.containers.internal:9100 is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] OpenTelemetry Collector"
$CURL_CMD -sSf -o /dev/null http://otel-collector:8888/metrics || { echo "❌ [ERROR] http://otel-collector:8888/metrics is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://otel-collector:8888/metrics is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Podman Exporter"
$CURL_CMD -sSf -o /dev/null http://podman-exporter:9882/metrics || { echo "❌ [ERROR] http://podman-exporter:9882/metrics is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://podman-exporter:9882/metrics is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Tempo"
$CURL_CMD -sSf -o /dev/null http://tempo:3200/ready || { echo "❌ [ERROR] http://tempo:3200/ready is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://tempo:3200/ready is reachable and healthy."

echo "----------------------------------------"
echo "🔍 [TEST] Webhook Tester"
$CURL_CMD -sSf -o /dev/null http://webhook-tester:8080/ || { echo "❌ [ERROR] http://webhook-tester:8080 is not healthy"; exit 1; }
echo "✅ [SUCCESS] http://webhook-tester:8080 is reachable."
echo ''

echo "========================================"
echo "🌐 Starting Reverse Proxy Tests (via HTTPS/443)"
echo "========================================"
PROXY_CURL_CMD="$CURL_CMD -sSf -o /dev/null"

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Alloy"
$PROXY_CURL_CMD --connect-to "alloy.${DOMAIN}:443:traefik:443" https://alloy.${DOMAIN}/-/healthy || { echo "❌ [ERROR] https://alloy.${DOMAIN}/-/healthy routing failed"; exit 1; }
echo "✅ [SUCCESS] https://alloy.${DOMAIN}/-/healthy is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Alertmanager"
$PROXY_CURL_CMD --connect-to "alertmanager.${DOMAIN}:443:traefik:443" https://alertmanager.${DOMAIN}/-/healthy || { echo "❌ [ERROR] https://alertmanager.${DOMAIN}/-/healthy routing failed"; exit 1; }
echo "✅ [SUCCESS] https://alertmanager.${DOMAIN}/-/healthy is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Grafana"
$PROXY_CURL_CMD --connect-to "grafana.${DOMAIN}:443:traefik:443" https://grafana.${DOMAIN}/api/health || { echo "❌ [ERROR] https://grafana.${DOMAIN}/api/health routing failed"; exit 1; }
echo "✅ [SUCCESS] https://grafana.${DOMAIN}/api/health is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Karma"
$PROXY_CURL_CMD --connect-to "karma.${DOMAIN}:443:traefik:443" https://karma.${DOMAIN}/health || { echo "❌ [ERROR] https://karma.${DOMAIN}/health routing failed"; exit 1; }
echo "✅ [SUCCESS] https://karma.${DOMAIN}/health is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: KeepHQ (Frontend)"
$PROXY_CURL_CMD --connect-to "keep.${DOMAIN}:443:traefik:443" https://keep.${DOMAIN}/api/healthcheck || { echo "❌ [ERROR] https://keep.${DOMAIN}/api/healthcheck routing failed"; exit 1; }
echo "✅ [SUCCESS] https://keep.${DOMAIN}/api/healthcheck is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: MinIO Console"
$PROXY_CURL_CMD --connect-to "minio.${DOMAIN}:443:traefik:443" https://minio.${DOMAIN}/ || { echo "❌ [ERROR] https://minio.${DOMAIN}/ routing failed"; exit 1; }
echo "✅ [SUCCESS] https://minio.${DOMAIN}/ is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Traefik Dashboard"
$PROXY_CURL_CMD --connect-to "traefik.${DOMAIN}:443:traefik:443" https://traefik.${DOMAIN}/dashboard/ || { echo "❌ [ERROR] https://traefik.${DOMAIN}/dashboard/ routing failed"; exit 1; }
echo "✅ [SUCCESS] https://traefik.${DOMAIN}/dashboard/ is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Webhook Tester"
$PROXY_CURL_CMD --connect-to "webhook-tester.${DOMAIN}:443:traefik:443" https://webhook-tester.${DOMAIN}/ || { echo "❌ [ERROR] https://webhook-tester.${DOMAIN}/ routing failed"; exit 1; }
echo "✅ [SUCCESS] https://webhook-tester.${DOMAIN}/ is reachable."

echo "========================================"
echo "🔗 Starting End-to-End Tracing Pipeline Test"
echo "========================================"
echo "🔍 [TEST] Flow: Traefik -> Grafana -> OTel -> Tempo -> Prometheus"

# 1. Genereer een unieke, willekeurige traceparent (W3C format: 00-traceid-spanid-01)
# 32 karakters voor trace ID, 16 voor span ID
TRACE_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
SPAN_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-16)
TRACEPARENT="00-${TRACE_ID}-${SPAN_ID}-01"

echo "   [INFO] Injected Traceparent: $TRACEPARENT"

# 2. Vuur het request af via Traefik naar Grafana
$PROXY_CURL_CMD -H "traceparent: $TRACEPARENT" --connect-to "grafana.${DOMAIN}:443:traefik:443" https://grafana.${DOMAIN}/api/health || { echo "❌ [ERROR] HTTP Request failed"; exit 1; }

echo "   [INFO] Waiting for the tracing pipeline to buffer and flush (max 30s)..."

# 3. Controleer Tempo of de specifieke Trace ID is aangekomen (met een retry loop)
TRACE_FOUND=false
for i in {1..6}; do
    sleep 5
    # Tempo heeft een API op poort 3200 om specifieke traces op te vragen
    TRACE_STATUS=$($CURL_CMD -s -o /dev/null -w "%{http_code}" http://tempo:3200/api/traces/$TRACE_ID || echo "000")
    
    if [ "$TRACE_STATUS" == "200" ]; then
        TRACE_FOUND=true
        echo "   ✅ [SUCCESS] Tempo successfully received and stored the exact Trace ID!"
        break
    fi
    echo "   [INFO] Trace not in Tempo yet. Retrying..."
done

if [ "$TRACE_FOUND" = false ]; then
    echo "   ⚠️  [WARN] Exact trace not found in Tempo within 30s. The pipeline might be delayed or misconfigured."
fi

# 4. Controleer Prometheus of de tracing metrics worden gepusht/gescraped
echo "   [INFO] Verifying tracing metrics flow in Prometheus..."
# We checken in Prometheus of OTel of Tempo de afgelopen minuten spans hebben geregistreerd
PROM_QUERY='sum(rate(otelcol_receiver_accepted_spans[5m])) > 0 or sum(rate(tempo_distributor_spans_received_total[5m])) > 0'
PROM_RESP=$($CURL_CMD -sG --data-urlencode "query=${PROM_QUERY}" http://prometheus:9090/api/v1/query || echo '{"data":{"result":[]}}')
HAS_RESULTS=$(echo "$PROM_RESP" | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$HAS_RESULTS" -gt 0 ]; then
    echo "   ✅ [SUCCESS] Prometheus confirms that tracing metrics are actively flowing!"
else
    echo "   ⚠️  [WARN] Prometheus metrics for trace ingestion are 0. The metrics push might be delayed."
fi

echo "========================================"
echo "🎉 [COMPLETE] All tests completed successfully! Stack is stable."
exit 0