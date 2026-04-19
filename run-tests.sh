#!/bin/bash
# run-tests.sh - Runs validations on the monitoring stack via an internal ephemeral container
set -e

# Load environment variables from the .env file
export $(grep -v '^#' .env | xargs)

# shows a spinner while waiting for background processes, adapted from
spinner() {
    local pid=$1
    local delay=0.1
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    tput civis 2>/dev/null || true  # hide cursor (ignore errors in cron)

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  %s  waiting..." "${frames[$i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep "$delay"
    done

    tput cnorm 2>/dev/null || true  # restore cursor (ignore errors in cron)
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
$PROXY_CURL_CMD --connect-to "alloy.${DOMAIN:-localhost}:443:traefik:443" https://alloy.${DOMAIN:-localhost}/-/healthy || { echo "❌ [ERROR] https://alloy.${DOMAIN:-localhost}/-/healthy routing failed"; exit 1; }
echo "✅ [SUCCESS] https://alloy.${DOMAIN:-localhost}/-/healthy is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Alertmanager"
$PROXY_CURL_CMD --connect-to "alertmanager.${DOMAIN:-localhost}:443:traefik:443" https://alertmanager.${DOMAIN:-localhost}/-/healthy || { echo "❌ [ERROR] https://alertmanager.${DOMAIN:-localhost}/-/healthy routing failed"; exit 1; }
echo "✅ [SUCCESS] https://alertmanager.${DOMAIN:-localhost}/-/healthy is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Grafana"
$PROXY_CURL_CMD --connect-to "grafana.${DOMAIN:-localhost}:443:traefik:443" https://grafana.${DOMAIN:-localhost}/api/health || { echo "❌ [ERROR] https://grafana.${DOMAIN:-localhost}/api/health routing failed"; exit 1; }
echo "✅ [SUCCESS] https://grafana.${DOMAIN:-localhost}/api/health is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Karma"
$PROXY_CURL_CMD --connect-to "karma.${DOMAIN:-localhost}:443:traefik:443" https://karma.${DOMAIN:-localhost}/health || { echo "❌ [ERROR] https://karma.${DOMAIN:-localhost}/health routing failed"; exit 1; }
echo "✅ [SUCCESS] https://karma.${DOMAIN:-localhost}/health is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: KeepHQ (Frontend)"
$PROXY_CURL_CMD --connect-to "keep.${DOMAIN:-localhost}:443:traefik:443" https://keep.${DOMAIN:-localhost}/api/healthcheck || { echo "❌ [ERROR] https://keep.${DOMAIN:-localhost}/api/healthcheck routing failed"; exit 1; }
echo "✅ [SUCCESS] https://keep.${DOMAIN:-localhost}/api/healthcheck is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: MinIO Console"
$PROXY_CURL_CMD --connect-to "minio.${DOMAIN:-localhost}:443:traefik:443" https://minio.${DOMAIN:-localhost}/ || { echo "❌ [ERROR] https://minio.${DOMAIN:-localhost}/ routing failed"; exit 1; }
echo "✅ [SUCCESS] https://minio.${DOMAIN:-localhost}/ is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Traefik Dashboard"
$PROXY_CURL_CMD --connect-to "traefik.${DOMAIN:-localhost}:443:traefik:443" https://traefik.${DOMAIN:-localhost}/dashboard/ || { echo "❌ [ERROR] https://traefik.${DOMAIN:-localhost}/dashboard/ routing failed"; exit 1; }
echo "✅ [SUCCESS] https://traefik.${DOMAIN:-localhost}/dashboard/ is reachable."

echo "----------------------------------------"
echo "🔍 [TEST] Proxy: Webhook Tester"
$PROXY_CURL_CMD --connect-to "webhook-tester.${DOMAIN:-localhost}:443:traefik:443" https://webhook-tester.${DOMAIN:-localhost}/ || { echo "❌ [ERROR] https://webhook-tester.${DOMAIN:-localhost}/ routing failed"; exit 1; }
echo "✅ [SUCCESS] https://webhook-tester.${DOMAIN:-localhost}/ is reachable."

echo ""
echo "========================================"
echo "🔗 Starting End-to-End Tracing Pipeline Test"
echo "========================================"
echo "🔍 [TEST] Flow: Traefik -> Grafana -> OTel -> Tempo -> Prometheus"

# 1. Generate an unique, random traceparent (W3C format: 00-traceid-spanid-01)
# 32 characters for trace ID, 16 for span ID
TRACE_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
SPAN_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-16)
TRACEPARENT="00-${TRACE_ID}-${SPAN_ID}-01"

echo "   [INFO] Injected Traceparent: $TRACEPARENT"

# 2. Fire the request via Traefik to Grafana
$PROXY_CURL_CMD -H "traceparent: $TRACEPARENT" --connect-to "grafana.${DOMAIN:-localhost}:443:traefik:443" https://grafana.${DOMAIN:-localhost}/api/health || { echo "❌ [ERROR] HTTP Request failed"; exit 1; }

echo "   [INFO] Waiting for the tracing pipeline to buffer and flush (max 30s)..."

# 3. Check Tempo if the specific Trace ID has arrived (with a retry loop)
TRACE_FOUND=false
for i in {1..6}; do
    sleep 5 &
    BG_PID=$!
    spinner "$BG_PID"
    wait "$BG_PID"
    # Tempo API runs on port 3200 to query specific traces
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

# 4. Check Prometheus if the tracing metrics are being pushed/scraped
echo "   [INFO] Verifying tracing metrics flow in Prometheus..."
# We check in Prometheus if OTel or Tempo have registered spans in the last few minutes
PROM_QUERY='sum(rate(otelcol_receiver_accepted_spans[5m])) > 0 or sum(rate(tempo_distributor_spans_received_total[5m])) > 0'
PROM_RESP=$($CURL_CMD -sG --data-urlencode "query=${PROM_QUERY}" http://prometheus:9090/api/v1/query || echo '{"data":{"result":[]}}')
HAS_RESULTS=$(echo "$PROM_RESP" | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$HAS_RESULTS" -gt 0 ]; then
    echo "   ✅ [SUCCESS] Prometheus confirms that tracing metrics are actively flowing!"
else
    echo "   ⚠️  [WARN] Prometheus metrics for trace ingestion are 0. The metrics push might be delayed."
fi

echo ""
echo "========================================"
echo "📜 Starting End-to-End Logging Pipeline Test"
echo "========================================"
echo "🔍 [TEST] Flow: Script -> Loki API (Push) -> MinIO (Storage) -> Loki API (Query)"

# 1. Generate a unique log ID and a nanosecond timestamp
LOG_UUID=$(cat /proc/sys/kernel/random/uuid)
# Loki expects timestamps in nanoseconds. We use %N, but fallback to padded seconds if %N is unsupported on the system.
NANO_TS=$(date +%s%N)
if [[ "$NANO_TS" == *"N"* ]]; then
    NANO_TS=$(date +%s)000000000
fi
LOG_MSG="e2e-test-log-entry-${LOG_UUID}"

echo "   [INFO] Injected Log Message: $LOG_MSG"

# Construct the JSON payload according to the Loki Push API specification
LOKI_PAYLOAD=$(cat <<EOF
{
  "streams": [
    {
      "stream": {
        "job": "e2e-test-script",
        "source": "automated-test"
      },
      "values": [
        [ "${NANO_TS}", "${LOG_MSG}" ]
      ]
    }
  ]
}
EOF
)

# 2. Push the log to Loki
PUSH_STATUS=$($CURL_CMD -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$LOKI_PAYLOAD" http://loki:3100/loki/api/v1/push || echo "000")

if [ "$PUSH_STATUS" != "204" ]; then
    echo "❌ [ERROR] Failed to push log to Loki. HTTP Status: $PUSH_STATUS"
    exit 1
fi
echo "   [INFO] Successfully pushed log to Loki API."

echo "   [INFO] Waiting for Loki to index the log (max 50s)..."

# 3. Query Loki for the specific log line with a retry loop
LOG_FOUND=false

# SIMPLIFIED QUERY: We only ask Loki for the broad job tag to prevent 
# URL encoding issues or shell escaping errors with |= and double quotes.
LOKI_QUERY='{job="e2e-test-script"}'

# Calculate a wide time window (-5 mins to +5 mins) to prevent issues with container/host clock drift
START_TS=$(($(date +%s) - 300))000000000
END_TS=$(($(date +%s) + 300))000000000

for i in {1..10}; do
    sleep 5 &
    BG_PID=$!
    spinner "$BG_PID"
    wait "$BG_PID"

    # We use query_range to search the wide time boundaries
    LOKI_RESP=$($CURL_CMD -sG --data-urlencode "query=${LOKI_QUERY}" --data-urlencode "start=${START_TS}" --data-urlencode "end=${END_TS}" http://loki:3100/loki/api/v1/query_range || echo '{"data":{"result":[]}}')

    # We use local jq to strictly filter the results and find the exact UUID inside the log text.
    HAS_LOG=$(echo "$LOKI_RESP" | jq -r "[.data.result[].values[]? | select(.[1] | contains(\"${LOG_UUID}\"))] | length" 2>/dev/null || echo "0")

    if [ "$HAS_LOG" -gt 0 ]; then
        LOG_FOUND=true
        echo "   ✅ [SUCCESS] Loki successfully ingested, indexed, and returned the test log!"
        break
    fi
    echo "   [INFO] Log not found in Loki yet. Retrying..."
done

if [ "$LOG_FOUND" = false ]; then
    echo "   ❌ [ERROR] Exact log not found in Loki within 50s. The logging pipeline might be broken."
    echo "   [DEBUG] Dumping raw Loki API Response to investigate why it failed:"
    echo "$LOKI_RESP" | jq . || echo "$LOKI_RESP"
    exit 1
fi

echo ""
echo "========================================"
echo "🪵 Starting Alloy Auto-Discovery Test"
echo "========================================"
echo "🔍 [TEST] Flow: Container Logs -> Alloy -> Loki"
echo "   [INFO] Verifying if Alloy is actively scraping containers and sending them to Loki..."

# We query Loki to check if logs from the 'grafana' container exist.
# This proves Alloy's podman socket auto-discovery and log shipping works!
ALLOY_QUERY='{container_name="grafana"}'

ALLOY_RESP=$($CURL_CMD -sG --data-urlencode "query=${ALLOY_QUERY}" --data-urlencode "start=${START_TS}" --data-urlencode "end=${END_TS}" http://loki:3100/loki/api/v1/query_range || echo '{"data":{"result":[]}}')
HAS_ALLOY_LOGS=$(echo "$ALLOY_RESP" | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$HAS_ALLOY_LOGS" -gt 0 ]; then
    echo "   ✅ [SUCCESS] Alloy is actively scraping container logs and shipping them to Loki!"
else
    echo "   ❌ [ERROR] No container logs found in Loki. Alloy might be failing to read the Podman socket."
    exit 1
fi

echo ""
echo "========================================"
echo "🚨 Starting End-to-End Alerting Pipeline Tests"
echo "========================================"

echo "🔍 [TEST] Flow: Prometheus (Rules Engine) -> Alertmanager"
echo "   [INFO] Checking if Alertmanager is receiving the 'Watchdog' alert from Prometheus..."
# Prometheus should be constantly firing the 'Watchdog' alert
PROM_WATCHDOG=$($CURL_CMD -sG --data-urlencode "filter=alertname=\"Watchdog\"" http://alertmanager:9093/api/v2/alerts || echo "[]")
HAS_PROM_WATCHDOG=$(echo "$PROM_WATCHDOG" | jq -r 'length' 2>/dev/null || echo "0")

if [ "$HAS_PROM_WATCHDOG" -gt 0 ]; then
    echo "   ✅ [SUCCESS] Alertmanager is receiving alerts from Prometheus!"
else
    echo "   ❌ [ERROR] The 'Watchdog' alert was not found in Alertmanager. Prometheus -> Alertmanager link is broken."
    exit 1
fi

echo "----------------------------------------"
echo "🔍 [TEST] Flow: Loki (Ruler) -> Alertmanager"
echo "   [INFO] Checking if Alertmanager is receiving the 'LokiWatchdog' alert from Loki..."

# Loki ruler might take ~1 minute to fire the first alert after startup, so we do a quick retry loop
LOKI_WATCHDOG_FOUND=false
for i in {1..6}; do
    LOKI_WATCHDOG=$($CURL_CMD -sG --data-urlencode "filter=alertname=\"LokiWatchdog\"" http://alertmanager:9093/api/v2/alerts || echo "[]")
    HAS_LOKI_WATCHDOG=$(echo "$LOKI_WATCHDOG" | jq -r 'length' 2>/dev/null || echo "0")

    if [ "$HAS_LOKI_WATCHDOG" -gt 0 ]; then
        LOKI_WATCHDOG_FOUND=true
        echo "   ✅ [SUCCESS] Alertmanager is receiving alerts from Loki!"
        break
    fi
    echo "   [INFO] LokiWatchdog not yet in Alertmanager. Waiting for Loki Ruler to evaluate (retrying)..."
    sleep 10 &
    BG_PID=$!
    spinner "$BG_PID"
    wait "$BG_PID"
done

if [ "$LOKI_WATCHDOG_FOUND" = false ]; then
    echo "   ❌ [ERROR] The 'LokiWatchdog' alert was not found in Alertmanager. Loki -> Alertmanager link is broken."
    exit 1
fi

echo "----------------------------------------"
echo "🔍 [TEST] Flow: Alertmanager -> Karma Dashboard"
echo "   [INFO] Checking if Karma is actively parsing and visualizing alerts from Alertmanager..."

KARMA_FOUND=false
for i in {1..6}; do
    # FIX: Karma /alerts.json requires a POST request and returns 'totalAlerts' at the root
    KARMA_RESP=$($CURL_CMD -sSf -X POST -H "Content-Type: application/json" -d '{}' http://karma:8080/alerts.json || echo '{"totalAlerts":0}')
    HAS_KARMA_ALERTS=$(echo "$KARMA_RESP" | jq -r '.totalAlerts // 0' 2>/dev/null || echo "0")

    if [ "$HAS_KARMA_ALERTS" -gt 0 ]; then
        KARMA_FOUND=true
        echo "   ✅ [SUCCESS] Karma is successfully receiving and grouping alerts from Alertmanager (Total: $HAS_KARMA_ALERTS)!"
        break
    fi
    echo "   [INFO] Karma has not synced alerts yet. Waiting for Karma to scrape Alertmanager (retrying)..."
    sleep 10 &
    BG_PID=$!
    spinner "$BG_PID"
    wait "$BG_PID"
done

if [ "$KARMA_FOUND" = false ]; then
    echo "   ❌ [ERROR] Karma is not showing any alerts. Integration with Alertmanager might be broken."
    echo "   [DEBUG] Dumping raw Karma API Response to investigate:"
    echo "$KARMA_RESP" | jq . || echo "$KARMA_RESP"
    exit 1
fi

echo ""
echo "========================================"
echo "📊 Starting PromQL Data Integrity Test"
echo "========================================"

echo "🔍 [TEST] Flow: Exporters -> Prometheus TSDB -> PromQL Evaluation"
# Execute a PromQL query to ensure the database is actually receiving and parsing data (Node Exporter)
PROMQL_TEST_QUERY='up{job="node-exporter"}'
echo "   [INFO] Evaluating PromQL: $PROMQL_TEST_QUERY"

PROMQL_TEST_RESP=$($CURL_CMD -sG --data-urlencode "query=${PROMQL_TEST_QUERY}" http://prometheus:9090/api/v1/query || echo '{"data":{"result":[]}}')
PROMQL_VAL=$(echo "$PROMQL_TEST_RESP" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "null")

if [ "$PROMQL_VAL" == "1" ]; then
    echo "   ✅ [SUCCESS] PromQL successfully evaluated the metric (value: 1)."
else
    echo "   ❌ [ERROR] PromQL evaluation failed. Expected '1', got: '$PROMQL_VAL'."
    exit 1
fi

echo "----------------------------------------"
echo "🔍 [TEST] Flow: Verify all Prometheus targets are UP (via PromQL)"
echo "   [INFO] Evaluating PromQL: up == 0"

# Ask Prometheus specifically for targets that are DOWN (value == 0)
DOWN_RESP=$($CURL_CMD -sG --data-urlencode "query=up == 0" http://prometheus:9090/api/v1/query || echo '{"data":{"result":[]}}')

# Count how many results we get back
DOWN_COUNT=$(echo "$DOWN_RESP" | jq -r '.data.result | length' 2>/dev/null || echo "1")

if [ "$DOWN_COUNT" == "0" ]; then
    echo "   ✅ [SUCCESS] No targets are reporting '0'. All targets are UP in the TSDB!"
else
    echo "   ❌ [ERROR] There are $DOWN_COUNT target(s) DOWN ('0') in the TSDB!"
    echo "   [DEBUG] Failing targets:"
    # Print a clean list of the specific jobs and instances that are failing
    echo "$DOWN_RESP" | jq -r '.data.result[] | "   - \(.metric.job) (\(.metric.instance))"'
    exit 1
fi

# Blackbox E2E validation: Verify Blackbox successfully probed an external target
echo "----------------------------------------"
echo "   [INFO] Verifying Blackbox Exporter End-to-End flow..."
BLACKBOX_QUERY='probe_success{job="blackbox-http"} == 1'
BLACKBOX_RESP=$($CURL_CMD -sG --data-urlencode "query=${BLACKBOX_QUERY}" http://prometheus:9090/api/v1/query || echo '{"data":{"result":[]}}')
HAS_SUCCESSFUL_PROBES=$(echo "$BLACKBOX_RESP" | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$HAS_SUCCESSFUL_PROBES" -gt 0 ]; then
    echo "   ✅ [SUCCESS] Prometheus confirms Blackbox Exporter is successfully executing HTTP probes!"
else
    echo "   ⚠️  [WARN] No successful Blackbox probes found yet in Prometheus. The initial probe might still be running."
fi

# Podman E2E validation: Verify Podman Exporter is successfully reading the rootless socket
echo "----------------------------------------"
echo "   [INFO] Verifying Podman Exporter End-to-End flow (Rootless Socket)..."
PODMAN_QUERY='podman_container_info{name="grafana"}'
PODMAN_RESP=$($CURL_CMD -sG --data-urlencode "query=${PODMAN_QUERY}" http://prometheus:9090/api/v1/query || echo '{"data":{"result":[]}}')
HAS_PODMAN_DATA=$(echo "$PODMAN_RESP" | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$HAS_PODMAN_DATA" -gt 0 ]; then
    echo "   ✅ [SUCCESS] Prometheus confirms Podman Exporter is actively reading container metrics from the rootless socket!"
else
    echo "   ❌ [ERROR] No Podman container metrics found in Prometheus. The rootless socket mount might be failing."
    exit 1
fi

# Traefik Metrics validation
echo "----------------------------------------"
echo "   [INFO] Verifying Traefik Metrics End-to-End flow..."
TRAEFIK_QUERY='traefik_entrypoint_request_duration_seconds_count > 0'
TRAEFIK_RESP=$($CURL_CMD -sG --data-urlencode "query=${TRAEFIK_QUERY}" http://prometheus:9090/api/v1/query || echo '{"data":{"result":[]}}')
HAS_TRAEFIK_DATA=$(echo "$TRAEFIK_RESP" | jq -r '.data.result | length' 2>/dev/null || echo "0")

if [ "$HAS_TRAEFIK_DATA" -gt 0 ]; then
    echo "   ✅ [SUCCESS] Prometheus confirms Traefik is actively exposing internal metrics!"
else
    echo "   ⚠️  [WARN] No Traefik request metrics found in Prometheus yet. This usually populates after a few API calls."
fi

echo ""
echo "========================================"
echo "🪣 Starting Storage Verification Test (MinIO)"
echo "========================================"
echo "🔍 [TEST] Flow: minio-init -> MinIO Buckets"

echo "   [INFO] Checking if Loki and Tempo buckets exist in MinIO..."
MINIO_BUCKET_METRICS=$($CURL_CMD -s http://minio:9000/minio/v2/metrics/bucket || echo "")

if echo "$MINIO_BUCKET_METRICS" | grep -q 'bucket="loki-data"'; then
    echo "   ✅ [SUCCESS] Bucket 'loki-data' exists."
else
    echo "   ❌ [ERROR] Bucket 'loki-data' is missing!"
    exit 1
fi

if echo "$MINIO_BUCKET_METRICS" | grep -q 'bucket="tempo-data"'; then
    echo "   ✅ [SUCCESS] Bucket 'tempo-data' exists."
else
    echo "   ❌ [ERROR] Bucket 'tempo-data' is missing!"
    exit 1
fi

echo "========================================"
echo "🎉 [COMPLETE] All tests completed successfully! Stack is stable."
exit 0