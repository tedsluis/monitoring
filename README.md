# Full Stack monitoring with Prometheus, Loki, Tempo and Grafana
## Fedora Workstation & Podman Rootless

This repository contains a complete observability stack, optimized for Fedora Workstation with rootless Podman. The stack combines metrics, logs and traces into one integrated environment with Grafana as the frontend.

## Features

-   Metrics: Prometheus (v3.9) with Node Exporter & Podman Exporter.
-   Logs: Grafana Loki (v3.3) with storage on MinIO (S3).
-   Traces: Grafana Tempo (v2.10) with OpenTelemetry.
-   Grafana: (v12.3) as frontend for metrics, logging and tracing.
-   Grafana Dashboards and Datasources are automatically loaded (IaC).
-   Collection: Alloy and OpenTelemetry collector for collecting container and journald logs.
-   Storage: MinIO (S3 compatible) for long-term, efficient storage of logs and traces.
-   Alerting: Prometheus Alertmanager connected to Karma (alert dashboard) and Blackbox Exporter (health checks).
-   Karma: Dashboard for alerts.
-   Reverse proxy with TLS encryption: Traefik proxy with self-signed certificate.
-   Static webpage: NGINX.
-   Security: Fully compatible with SELinux and runs rootless (with specific fixes for socket access).
-   webhook-tester: receives alerts from alertmanager for inspection.

## Architecture

The stack consists of the following services:

| Service           | Poort | Beschrijving                                     |
|-------------------|-------|--------------------------------------------------|
| Alertmanager      |  9093 | Processes and routes alerts.                     |
| Alloy             | 12345 | Collector for logs (journald and podman logs).   |
| Blackbox          |  9115 | Performs HTTP/TCP health probes.                 |
| Grafana           |  3000 | Dashboards and visualization.                    |
| Karma             |  8080 | UI dashboard for Alertmanager notifications.     |
| Loki              |  3100 | Log aggregation (via MinIO S3).                  |
| MinIO             |  9000 | S3 Object Storage API.                           |
| MinIO Console     |  9001 | Web interface for storage management.            |
| NGINX             |    80 | Start page.                                      |
| Node-exporter     |  9100 | Host metrics collector.                          |
| OpenTelemetry     |  8888 | Open Telemetry Collector.                        |
| podman-exporter   |  9882 | podman metrics collector.                        |
| Prometheus        |  9090 | Time-series database for metrics.                |
| Tempo             |  3200 | Distributed Tracing backend (via MinIO S3).      |
| Traefik           |   443 | Reverse proxy.                                   |
| webhook-tester    |  5001 | Webhooks inspectie.                              |

Diagram
![diagram](./images/diagram.png)

## Prerequisites

-   OS: Fedora Linux (tested on Fedora 43+).
-   Tools: podman and podman-compose.
-   Podman Socket: The user socket must be active for the Podman Exporter and Alloy.

```bash
# Install requirements\
sudo dnf install podman podman-compose -y

# Activate the Podman socket for your user (Rootless)\
systemctl --user enable --now podman.socket

# Check if the socket works
ls -l /run/user/$(id -u)/podman/podman.sock

# Enable using port 80
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
net.ipv4.ip_unprivileged_port_start = 80
echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee /etc/sysctl.d/99-rootless-ports.conf
net.ipv4.ip_unprivileged_port_start=80
```

## Installation & Startup

1.  Clone the repository:
```bash
    git clone https://github.com/tedsluis/monitoring.git\
    cd monitoring
```

2.  Start the stack:
```bash
    podman-compose up -d
```
The first time, the `minio-init` container will automatically create the required buckets (`loki-data` and `tempo-data`).

3. Create certificate and trust CA:
```bash
$ ./renew-certs.sh
=== Start Certificate Renewal (Version 3.2) ===
Cleaning up old files...
Generating SAN configuration...
Generating Root CA...
...+++++++++++++++++++++++++++++++++++++++*.....+....+...+..+.+....................+.......+...+++++++++++++++++++++++++++++++++++++++*.....+.......+.........+........++++++
...+.....+++++++++++++++++++++++++++++++++++++++*...+......+...+..+....+......+......+..+.............+..+.+......+++++++++++++++++++++++++++++++++++++++*....+.........+......+.+..................+..+...................+.........+.....+....+..+.+.........+........+.+..+....+......+.........+......+...+.........+..+.............+.....+.......+........+......+.........+.......+......+..+.......+...+............+......+........+.........+...+....+........+.+..+...+.......+.....+....+...+..+..........+......+..+.+.........+..+........................+.......+...+..+.......+..+...+...+............+.+......+...+............+.....+.+.....+....+........+......+....+........+...+..........+......+...........+..........+.................++++++
-----
Generating Server Certificate...
Certificate request self-signature ok
subject=C=NL, ST=Utrecht, L=Utrecht, O=Bachstraat, OU=Home, CN=*.localhost
Fixing permissions (chmod 644)...
Updating Fedora Trust Store...
Checking if System Bundle trusts the certificate...
✓ SUCCESS: System bundle now trusts your certificate!
Restarting Traefik...
WARN[0010] StopSignal SIGTERM failed to stop container traefik in 10 seconds, resorting to SIGKILL
traefik
traefik
7ca33df28db75aec091abf01850c21eca9b226f27e430ece68c43300772c0e48
traefik
=== Done! ===
Test now with: curl -v https://grafana.localhost
```

4.  Check the status:
```bash
$ podman ps -a
CONTAINER ID  IMAGE                                                   COMMAND               CREATED             STATUS                         PORTS                                                             NAMES
81c55c7b7b20  docker.io/keinstien/atlas:latest                        /config/scripts/a...  About an hour ago   Up About an hour               8888-8889/tcp                                                     atlas
b5536a098b7e  quay.io/prometheus/alertmanager:v0.28.0                 --config.file=/et...  2 minutes ago       Up About a minute              9093/tcp                                                          alertmanager
b478ebb079ff  docker.io/grafana/alloy:latest                          run --server.http...  About a minute ago  Up About a minute                                                                                alloy
2db9b9c31c50  quay.io/prometheus/blackbox-exporter:latest             --config.file=/co...  About a minute ago  Up About a minute              9115/tcp                                                          blackbox-exporter
61f157adda08  docker.io/library/postgres:15-alpine                    postgres              About a minute ago  Up About a minute              5432/tcp                                                          keep-db
b90a191fdb53  docker.io/minio/minio:latest                            server /data --co...  About a minute ago  Up About a minute (healthy)    9000/tcp                                                          minio
6ce421121e8c  docker.io/library/nginx:alpine                          nginx -g daemon o...  About a minute ago  Up About a minute              80/tcp                                                            nginx
b40b4061707b  quay.io/prometheus/node-exporter:v1.10.0                --path.rootfs=/ho...  About a minute ago  Up About a minute              9100/tcp                                                          node-exporter
9cb5fe5819be  quay.io/navidys/prometheus-podman-exporter:latest                             About a minute ago  Up About a minute              9882/tcp                                                          podman-exporter
47af223a3811  quay.io/prometheus/prometheus:v3.9.0                    --config.file=/et...  About a minute ago  Up About a minute              9090/tcp                                                          prometheus
ff3e519deb50  docker.io/library/traefik:v3.6.8                        traefik               About a minute ago  Up About a minute              0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:4317->4317/tcp  traefik
d92ba13741a4  docker.io/tarampampam/webhook-tester:latest             start                 About a minute ago  Up About a minute                                                                                webhook-tester
0c397453f09d  ghcr.io/prymitive/karma:latest                                                About a minute ago  Up About a minute              8080/tcp                                                          karma
e9e57fd6811a  us-central1-docker.pkg.dev/keephq/keep/keep-api:latest  gunicorn keep.api...  About a minute ago  Up About a minute                                                                                keep-backend
1ba34c8c09a9  docker.io/minio/mc:latest                                                     About a minute ago  Exited (0) About a minute ago                                                                    minio-init
e6a565f95207  us-central1-docker.pkg.dev/keephq/keep/keep-ui:latest                         About a minute ago  Up About a minute              3000/tcp                                                          keep-frontend
4c90e80ed34d  docker.io/grafana/loki:3.3.2                            -config.file=/etc...  About a minute ago  Up About a minute              3100/tcp                                                          loki
d534e21614ab  docker.io/grafana/tempo:2.10.1                          -config.file=/etc...  About a minute ago  Up About a minute                                                                                tempo
c86d4f4e183f  docker.io/otel/opentelemetry-collector-contrib:0.119.0  --config=/etc/ote...  About a minute ago  Up About a minute              4317-4318/tcp, 55678-55679/tcp                                    otel-collector
7ae579e9db9e  docker.io/grafana/grafana:12.3.0                                              About a minute ago  Up About a minute              3000/tcp                                                          grafana

```
note: The minio-init container only runs when starting minio.

## Stop, start or restart

```bash
# stop all containers
podman-compose down

# start all containers
podman-compose up -d

# restart all containers
podman-compose down && podman-compose up -d

# restart a specific container and include changes from compose.yaml
podman-compose up -d --force-recreate webhook-tester

# restart a specific container without applying compose.yaml changes
podman restart webhook-tester
```

## Configuration

The configuration is divided into folders per component. Thanks to Grafana Provisioning, datasources are automatically loaded.

### Directory structure

-   `alertmanager/`: Routing of notifications.
-   `alloy/`: Pipeline configuration for reading journald and the podman.socket.
-   `blackbox/`: Definitions for HTTP health checks.
-   `grafana-provisioning/`: Automatically links Prometheus, Loki, and Tempo to Grafana.
-   `grafana-provisioning/dashboards/json`: Grafana dashboards.
-   `grafana-provisioning/datasources`: automatic datasource configuration.
-   `landing-page/`: index.html and nginx config.
-   `loki/`: Configuration for Loki (S3 backend) and recording rules.
-   `otel`: OpenTelemetry configuration.
-   `prometheus/`: prometheus.yml and alert.rules.yml.
-   `tempo/`: Configuration for Tempo (S3 backend).
-   `traefik/`: traefik.yaml
-   `traefik/certs`: certificates.
-   `traefik/dynamic`: dynamic Traefik configuration.

### Login credentials (Defaults)

| Service | Username | Password | Note                             |
|---------|----------------|------------|----------------------------------------|
| Grafana | admin          | admin      | You can change this after first login! |
| MinIO   | minio          | minio123   | Can be changed in compose.yml          |

## Usage

### 1. NGINX start page

Go to https://localhost


![startpagina1](./images/startpagina1.png)


![startpagina2](./images/startpagina2.png)


![startpagina3](./images/startpagina3.png)


![startpagina4](./images/startpagina4.png)

### 2. Dashboards (Grafana)

Go to https://grafana.localhost

Grafana is the central visual heart of this stack and functions as a 'single pane of glass' for all data. The open-source platform connects to Prometheus (metrics), Loki (logs) and Tempo (traces), enabling deep system insight through dashboards and the Explore mode. Thanks to automated provisioning, datasources and dashboards are loaded at startup, so everything works without manual configuration.

#### Dashboards

This repo contains a number of Grafana dashboards stored in [./grafana-provisioning/dashboards/json/](./grafana-provisioning/dashboards/json/) in JSON format.

Grafana Dashboards
![grafana-dashboarden](./images/grafana-dashboards.png)

#### Explore

The Explore mode provides an advanced interface for ad-hoc analysis and troubleshooting, where users can execute queries directly. Explore thus facilitates rapid incident diagnosis and root-cause analysis, without the need to configure predefined dashboards in advance.

**Loki logs explore**

 The Loki datasource combined with LogQL makes it possible to efficiently filter log streams by labels, search for specific text patterns or regular expressions, and visualize log volumes alongside raw log lines.
![Loki-explore](/images/explore-logs.png)

**Prometheus metrics explore**

The Prometheus datasource, combined with PromQL queries, enables iterative exploration of time-series data, trend visualization, and comparison of metrics using split-view functionality.
![prometheus-explore](/images/explore-metrics.png)

**Tempo tracing explore**

The Tempo datasource combined with TraceQL provides a detailed visualization of the lifecycle of requests through the distributed architecture. Using the waterfall view, users can analyze latency per component, isolating performance bottlenecks and errors within specific spans. Integration with TraceQL enables targeted filtering of traces, which, combined with correlated logs and metrics, allows efficient root-cause analysis during incidents. For example, it can be interesting to filter for requests that do not have an HTTP status code of 4xx or 5xx, or requests that take longer than 500ms.
![tempo-explore](/images/explore-traces.png)


To manually test the proxy path by sending a traceparent header, run this command in your terminal:
```bash
 curl -k -H "traceparent: 00-11112222333344445555666677778888-1111222233334444-01" https://grafana.localhost/api/health
```
Next, in Grafana, go to Tempo Explore and search for the exact Trace ID: 11112222333344445555666677778888.
If propagation works, you'll see a beautiful trace tree with the Traefik span at the top and the Grafana span below.

Explore trace - service graph
![traces-explore](/images/explore-traces-service-graph.png)

#### Drilldown

The drill-down functionality within Grafana offers the ability to connect in-depth error analysis through metrics, logs and traces contextually with each other. From an anomaly in a metrics dashboard, you can directly navigate to the correlated log lines in Loki, and then use automatically detected trace IDs to switch to detailed request spans in Tempo. This integration eliminates the need to manually synchronize timestamps and identifiers between different datasources, significantly increasing the efficiency of root cause analysis and performance optimization.

Metrics drilldown
![Metrics-drilldown](/images/drilldown-metrics-dashboard.png)

Logs drilldown
![loki-drilldown](/images/drill-down-logs-dashboard.png)

Traces drilldown
![traces-drilldown](/images/drilldown-breakdown.png)

#### Grafana alerts

Grafana Alerting provides a central interface for monitoring alerts. This module aggregates alert rules from both Prometheus (for metrics) and Loki (for log data), creating an overview of the operational status. Through this dashboard you can analyze the real-time status of alerts (‘Pending’ or ‘Firing’), examine the underlying query definitions, and gain insight into the evaluation criteria that safeguard the platform’s stability and availability.

Grafana Alerting
![grafana-alerting](/images/grafana-alerts.png)

#### Grafana datasources

Datasources in Grafana serve as the technical interface to the underlying data storage systems, allowing the application to retrieve data without persisting it itself. In this configuration, Prometheus, Loki and Tempo are defined as the primary sources for exposing metrics, log files and distributed traces, respectively.
![grafana-datasources](./images/grafana-datasource.png)

The datasources for Prometheus, Loki and Tempo are configured in [./grafana-provisioning/dashboards/dashboard.yaml](./grafana-provisioning/datasources/datasources.yaml)


### 3. Prometheus Metrics

Go to https://prometheus.localhost

- `/query`:  metrics querier.
- `/alerts`: alert rule overview
- `/targets`: status of the scrape targets.
- `/config`: full prometheus configuration.

Prometheus UI - alert rules overview
![prometheus](images/prometheus.png)

Prometheus dashboard
![prometheus-dashboard](./images/prometheus-dashboard.png)

### 4. Alertmanager

Go to https://alertmanager.localhost

Alertmanager UI
![alertmanager](/images/alertmanager.png)

Alertmanager dashboard
![alertmanager-dashboard](./images/alertmanager-metrics-dashboard.png)

- Overview of current alerts
- Ability to silence alerts.

### 5. Karma Alert Dashboard

Go to https://karma.localhost

Here you see an overview of all active warnings (e.g., "Disk almost full", "Container down" or "Health Check Failed").

Karma UI
![karma](images/karma.png)

### 6. Storage (MinIO)

Go to https://minio.localhost

Minio UI - login
![minio](images/minio-login.png)

Minio UI - object browser
![minio-object-browser](./images/minio-object-browser.png)

Minio overview dashboard
![minio](./images/minio-dashboard.png)

Minio bucket dashboard
![minio-bucket](./images/minio-bucket-dashboard.png)

Minio node dashboard
![minio-node](./images/minio-node-dashboard.png)

Here you can see how much data Loki and Tempo are using in their buckets.

### 7. webhook-tester

Go to https://webhook-tester.localhost

Alertmanager sends the alerts to the webhook-tester

Webhook-tester UI
![webhook-tester-ui](/images/webhook-tester.png)

### 8. Alloy exporter

https://alloy.localhost

Alloy
![alloy](./images/alloy.png)

Alloy Graph
![alloy-graph](./images/alloy-graph.png)

### 9. Blackbox exporter

https://blackbox.localhost

Blackbox dashboard
![blackbox-dashboard](/images/blackbox-dashboard.png)

### 10. Loki

Loki dashboard
![loki-metrics-dashboard](/images/loki-metrics-dashboard.png)

Loki logging dashboard
![loki-logs-dashboard](./images/loki-logs-dashboards.png)

### 11. Tempo



### 12. Otel-collector


### 13. node-exporter

nodes-exporter-full
![nodes-exporter-full-dashboard](/images/node-exporter-dashbaord.png)

### 14. podman-exporter

podman-exporter
![podman-exporter-dashboard](/images/podman-exporter-dashboard.png)

### 15. Traefik

Go to: https://traefik.localhost

Treafik
![traefik](/images/traefik.png)

Treafik dashboard
![traefik](/images/traefik.dashboard.png)

## Remove everything

```bash
# stop all containers
$ podman-compose down

# show volumes
$ podman volume ls | grep monitoring
local       monitoring_prometheus-data
local       monitoring_loki-wal
local       monitoring_tempo-wal
local       monitoring_minio-data
local       monitoring_grafana-data

# remove volumes
$ podman volume rm monitoring_prometheus-data monitoring_loki-wal monitoring_tempo-wal monitoring_minio-data monitoring_grafana-data

# remove certificates
$ rm /etc/pki/ca-trust/source/anchors/my-local-ca.pem
$ rm /etc/pki/ca-trust/source/anchors/my-local-ca.crt
$ sudo update-ca-trust extract

# disable podman socket
$ systemctl --user disable --now podman.socket

# remove rootless ports
sudo rm /etc/sysctl.d/99-rootless-ports.conf

# remove monitoring repo
$ rm -rf REPONAME
```