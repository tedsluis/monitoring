# Full Stack Observability & Monitoring Platform
## An Educational Lab for Prometheus, Loki, Tempo, Grafana, and Alerting

This repository contains a complete, production-like observability stack optimized for Fedora Workstation with rootless Podman. It is designed as an educational environment to help Developers and DevOps Engineers understand how modern monitoring tools interlock to provide comprehensive metrics, logging, tracing, and alerting capabilities. The entire stack is automatically configured upon startup, including pre-provisioned Grafana dashboards, datasources, and alerting rules.

Diagram
![diagram](./images/diagram.png)

## Table of Contents

1. Educational Benefits
2. Architecture & Data Flow
3. Service Port Map
4. Tooling & Functionality
5. Prerequisites
6. Installation & Startup
7. Usage & Exploration (Screenshots)
8. Teardown & Cleanup

## 1. Educational Benefits

Why use this stack? This environment is built to teach you:

- **The Three Pillars of Observability**: How to seamlessly connect Metrics (Prometheus), Logs (Loki), and Traces (Tempo).
- **Contextual Drill-down**: How to configure Grafana datasources so you can jump directly from a spike in a metric to the specific log line, and then to the exact application trace.
- **Modern Collection**: Using Grafana Alloy and OpenTelemetry Collector as modern, vendor-neutral data pipelines.
- **S3-Compatible Storage**: How Loki and Tempo use MinIO object storage for scalable, long-term data retention instead of local disks.
- **Advanced Alerting Routing**: The flow of an alert from Prometheus -> Alertmanager -> KeepHQ / Karma / Webhook-tester.
- **Secure Local Networking**: Running a complex stack via Traefik Reverse Proxy with TLS/SSL on local `.localhost` domains using rootless Podman.

## 2. Architecture & Data Flow

The stack is designed around specific data flows:
- **Metrics Flow**: Node-exporter, Podman-exporter, and Blackbox-exporter expose metrics -> Prometheus scrapes them -> Grafana visualizes them.
- **Logging Flow**: System (journald) and Container logs -> Grafana Alloy collects them -> Pushed to Loki -> Stored in MinIO -> Visualized in Grafana.
- **Tracing Flow**: Application traces -> OpenTelemetry Collector -> Pushed to Tempo -> Stored in MinIO -> Visualized in Grafana.
- **Alerting Flow**: Prometheus evaluates alert.rules.yml -> Fires to Alertmanager -> Alertmanager routes to Karma (UI), KeepHQ (AIOps), and Webhook-tester.

## 3. Service Port Map

| Service         | Internal Port | Public URL                          | Description                              |
|-----------------|---------------|-------------------------------------|------------------------------------------|
| Nginx           | 80            | https://localhost                   | Landing page portal                      |
| Traefik         | 443 / 8082    | https://traefik.localhost           | Reverse proxy & Ingress routing          |
| Grafana         | 3000          | https://grafana.localhost           | Main visualization & Dashboard UI        |
| Prometheus      | 9090          | https://prometheus.localhost        | Time-series database                     |
| Loki            | 3100          | https://loki.localhost              | Log aggregation engine                   |
| Tempo           | 3200          | https://tempo.localhost             | Distributed Tracing backend              |
| MinIO           | 9000 / 9001   | https://minio.localhost             | S3 Object Storage for Loki & Tempo       |
| Alloy           | 12345         | https://alloy.localhost             | Log collection pipeline                  |
| OTel Collector  | 4317 / 8888   | https://otel-collector.localhost    | Trace collection pipeline                |
| Alertmanager    | 9093          | https://alertmanager.localhost      | Alert routing and deduplication          |
| Karma           | 8080          | https://karma.localhost             | Alert visualization dashboard            |
| KeepHQ          | 3000 / 8080   | https://keep.localhost              | Open-source AIOps and alert management   |
| Webhook Tester  | 8080          | https://webhook-tester.localhost    | Endpoint for inspecting webhook payloads |
| node-exporter   | 9100          | https://node-exporter.localhost     | Host metrics                             |
| podman-exporter | 9882          | https://podman-exporter.localhost   | Container metrics                        |
| Blackbox        | 9115          | https://blackbox-exporter.localhost | HTTP/TCP endpoint probe                  |


## 4. Tooling & Functionality

**1. Visualization & Portal**
   * Nginx (Portal): Serves as a static, central hub linking to all services and endpoints.
   * Grafana (v12.3): The 'single pane of glass'. Dashboards and Datasources are loaded automatically via Infrastructure as Code (IaC).

**2. Metrics (The "What is happening?")**
   * Prometheus: Scrapes targets, stores time-series data, and evaluates alert rules.
   * Exporters:
     * Node Exporter: Collects host hardware and OS metrics.
     * Podman Exporter: Collects metrics from rootless Podman containers.
     * Blackbox Exporter: Probes endpoints over HTTP/TCP to monitor uptime.

**3. Logging (The "Why is it happening?")**
   * Grafana Loki: Highly efficient log aggregation system. Uses MinIO for storage.
   * Grafana Alloy: The collector that reads journald and /var/run/podman.sock (Podman) and pushes logs to Loki.

**4. Tracing (The "Where is it happening?")**
   * Grafana Tempo: High-scale distributed tracing backend. Uses MinIO for storage.
   * OpenTelemetry (OTel) Collector: Receives OTLP traces and forwards them to Tempo.

**5. Storage & Infrastructure**
   * MinIO: S3-compatible storage providing scalable object storage for Tempo and Loki data.
   * PostgreSQL: Relational database backend for KeepHQ.
   * Traefik: Reverse proxy that acts as the entry point, handling routing and TLS termination for all .localhost domains.

**6. Alerting & AIOps**
   * Alertmanager: Groups, routes, and throttles alerts from Prometheus and Loki.
   * Karma: A clean, concise dashboard for viewing Alertmanager alerts.
   * KeepHQ: Centralized alert management and AIOps platform.
   * Webhook Tester: A simple tool to view the raw JSON payloads Alertmanager sends out.

## 5. Prerequisites

-   OS: Fedora Linux (tested on Fedora 43+).
-   Tools: podman and podman-compose.
-   Podman Socket: The user socket must be active for the Podman Exporter and Alloy.

Install requirements:
```bash
   # Install packages
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

## 6. Installation & Startup

### 6.1 Clone the repository
```bash
    git clone https://github.com/tedsluis/monitoring.git
    cd monitoring
```

### 6.2 Start the stack
```bash
    podman-compose up -d
```
The first time, the `minio-init` container will automatically create the required buckets (`loki-data` and `tempo-data`).

### 6.3 Generate Local TLS Certificates
To ensure secure connections (https://*.localhost) without browser warnings, run the certificate script. This generates a local CA and adds it to your Fedora Trust Store.
```bash
   ./renew-certs.sh
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
**note:** If you try `https://localhost` in your web browser, make sure you restart your browser first!

### 6.4 Check the status
```bash
podman ps -a
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

### 6.5 Stop, start or restart

```bash
   # stop all containers
   podman-compose down
   
   # start all containers
   podman-compose up -d
   
   # restart all containers
   podman-compose down && podman-compose up -d
   
   # restart a specific container and include changes from compose.yaml
   podman-compose down webhook-tester && podman-compose up -d --force-recreate webhook-tester
   
   # restart a specific container without applying compose.yaml changes
   podman restart webhook-tester
```

## 7. Usage

### 7.1 NGINX start page

Go to https://localhost


![startpagina1](./images/startpagina1.png)


![startpagina2](./images/startpagina2.png)


![startpagina3](./images/startpagina3.png)


![startpagina4](./images/startpagina4.png)

### 7.2 Login credentials (Defaults)

| Service | Username       | Password   | Note                                   |
|---------|----------------|------------|----------------------------------------|
| Grafana | admin          | admin      | You can change this after first login. |
| MinIO   | minio          | minio123   | Can be changed in compose.yml          |

### 7.3 Prometheus Metrics

Prometheus is a time-series database that records numeric data, such as CPU usage, network traffic, or application-specific. Prometheus operates on a pull-based model; it actively "scrapes" (fetches) metrics over HTTP from designated target endpoints at regular intervals (in our case every 15 seconds). Once the data is ingested, users can leverage its query language, PromQL, to slice, dice, and aggregate the metrics for visualization in tools like Grafana, or evaluate them against custom rules to trigger real-time notifications via Alertmanager when thresholds are breached.

Go to https://prometheus.localhost

| Endpoint paths | Description                    |
|----------------|--------------------------------|
| `/query`       | metrics querier.               |
| `/alerts`      | alert rule overview.           |
| `/targets`     | status of the scrape targets.  |
| `/config`      | full prometheus configuration. |


Example Prometheus UI - alert rules overview
![prometheus](images/prometheus.png)


| configuration        | configuration file                                           |
|----------------------|--------------------------------------------------------------|
| scrape target        | [./prometheus/prometheus.yml](./prometheus/prometheus.yml)   |
| alert rules          | [./prometheus/alert.rules.yml](./prometheus/alert.rules.yml) |

Prometheus exposes and scrapes its own metrics. Using these metrics you can monitor prometheus, see below:

Prometheus dashboard
![prometheus-dashboard](./images/prometheus-dashboard.png)

### 7.4 Loki

Grafana Loki is a log aggregation system inspired by Prometheus. Unlike traditional logging systems (such as the Elastic Search) that index the full text of every log line, Loki only indexes the metadata (labels) attached to each log stream. This unique design choice makes it exceptionally lightweight, cost-effective, and fast to operate. 

In a typical workflow, a collector like Grafana Alloy gathers logs from your containers or system journals and pushes them to Loki. Loki then compresses this data into chunks and stores it efficiently in an object storage backend like MinIO. Users can seamlessly search and analyze these logs in Grafana using LogQL (Loki Query Language), leveraging the exact same labels used in Prometheus to instantly correlate metrics spikes with their underlying log events.

Loki does not include a built-in user interface. Instead, it relies entirely on Grafana to serve as the unified dashboard for exploring and analyzing your logs, for example:

Loki logging dashboard
![loki-logs-dashboard](./images/loki-logs-dashboards.png)


| configuration        | configuration file                                                                 |
|----------------------|------------------------------------------------------------------------------------|
| Loki config          | [./loki/loki-config.yaml](./loki/loki-config.yaml)                                 |
| Loki alert rules     | [./loki/rules/fake/loki-alert-rules.yaml](./loki/rules/fake/loki-alert-rules.yaml) |

Like most modern container, Loki exposes prometheus metrics too, which are used to monitor Loki using the dashboard below:

Loki dashboard
![loki-metrics-dashboard](/images/loki-metrics-dashboard.png)

### 7.5 Tempo

Grafana Tempo is a tracing backend designed to track the flow of requests as they travel through complex architectures and microservices. It helps developers and operators pinpoint exactly where latency, bottlenecks, or errors are occurring in a system. Unlike older tracing tools that require heavy, complex databases for indexing, Tempo is exceptionally cost-effective because it only requires a basic object storage backend (like MinIO or S3) to store the raw trace data. 

In a typical setup, an OpenTelemetry Collector gathers traces from your applications and pushes them to Tempo. Within Grafana, users can visualize these request lifecycles using TraceQL, and seamlessly jump directly from a log line in Loki to the exact corresponding trace span in Tempo for rapid root cause analysis.

Loki does not include a built-in user interface. Instead, it relies entirely on Grafana to serve as the unified dashboard for exploring and analyzing your logs, for example:

Tempo Tracing dashboard
![tempo-dashboard](./images/)

| configuration        | configuration file                         |
|----------------------|--------------------------------------------|
| Tempo config         | [./tempo/tempo.yaml](./tempo/tempo.yaml)   |

Tempo exposes prometheus metrics too, which are used to monitor Loki using the dashboard below:

![Tempo-dashboard](./images/tempo-dashboard.png)

### 7.6 Alertmanager

Alertmanager is a alert routing and management component that works hand-in-hand with Prometheus and Loki. While Prometheus and Loki are responsible for evaluating metric and logging thresholds and firing raw alerts, Alertmanager takes over to handle the complex logistics of notifications. It deduplicates and intelligently groups related alerts together, preventing engineers from being overwhelmed by "alert fatigue" during major system outages. Once grouped, it routes these notifications to the appropriate downstream receivers, such as Karma for visualization, KeepHQ for AIOps, or webhook-tester for debugging. 

Alertmanager also supports advanced operational features like silencing (temporarily muting specific alerts) and inhibition (suppressing lower-priority alerts if a related high-priority alert is already active), ensuring that teams only receive the most actionable signals.

Go to https://alertmanager.localhost

| Path        | Description                                    |
|-------------|------------------------------------------------|
| /#/alerts   | Overview of current alerts                     |
| /#/silences | Ability to silence alerts                      |
| /#/status   | Alertmanager status and configuration overview |
| /#/settings | Alertmanager UI settings                       |


Alertmanager UI
![alertmanager](/images/alertmanager.png)

| configuration        | configuration file                                                  |
|----------------------|---------------------------------------------------------------------|
| Alertmanager config  | [./alertmanager/alertmanager.yml](./alertmanager/alertmanager.yml) |

Alertmanager exposes prometheus metrics too, which are used to monitor Alertmanager using the dashboard below:

Alertmanager dashboard
![alertmanager-dashboard](./images/alertmanager-metrics-dashboard.png)


### 7.7 Dashboards (Grafana)

Go to https://grafana.localhost

Grafana is the central visual heart of this stack and functions as a 'single pane of glass' for all data. The open-source platform connects to Prometheus (metrics), Loki (logs) and Tempo (traces), enabling deep system insight through dashboards and the Explore mode. Thanks to automated provisioning, datasources and dashboards are loaded at startup, so everything works without manual configuration.

#### 7.7.1 Dashboards

This repo contains a number of Grafana dashboards stored in [./grafana-provisioning/dashboards/json/](./grafana-provisioning/dashboards/json/) in JSON format.

Grafana Dashboards
![grafana-dashboarden](./images/grafana-dashboards.png)

#### 7.7.2 Explore

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

#### 7.7.3 Drilldown

The drill-down functionality within Grafana offers the ability to connect in-depth error analysis through metrics, logs and traces contextually with each other. From an anomaly in a metrics dashboard, you can directly navigate to the correlated log lines in Loki, and then use automatically detected trace IDs to switch to detailed request spans in Tempo. This integration eliminates the need to manually synchronize timestamps and identifiers between different datasources, significantly increasing the efficiency of root cause analysis and performance optimization.

Metrics drilldown
![Metrics-drilldown](/images/drilldown-metrics-dashboard.png)

Logs drilldown
![loki-drilldown](/images/drill-down-logs-dashboard.png)

Traces drilldown
![traces-drilldown](/images/drilldown-breakdown.png)

#### 7.7.4 Grafana alerts

Grafana Alerting provides a central interface for monitoring alerts. This module aggregates alert rules from both Prometheus (for metrics) and Loki (for log data), creating an overview of the operational status. Through this dashboard you can analyze the real-time status of alerts (‘Pending’ or ‘Firing’), examine the underlying query definitions, and gain insight into the evaluation criteria that safeguard the platform’s stability and availability.

Grafana Alerting
![grafana-alerting](/images/grafana-alerts.png)

#### 7.7.5 Grafana datasources

Datasources in Grafana serve as the technical interface to the underlying data storage systems, allowing the application to retrieve data without persisting it itself. In this configuration, Prometheus, Loki and Tempo are defined as the primary sources for exposing metrics, log files and distributed traces, respectively.
![grafana-datasources](./images/grafana-datasource.png)

The datasources for Prometheus, Loki and Tempo are configured in [./grafana-provisioning/dashboards/dashboard.yaml](./grafana-provisioning/datasources/datasources.yaml)


### 7.8 Karma Alert Dashboard

Go to https://karma.localhost

Here you see an overview of all active warnings (e.g., "Disk almost full", "Container down" or "Health Check Failed").

Karma UI
![karma](images/karma.png)

### 7.9 webhook-tester

Go to https://webhook-tester.localhost

Alertmanager sends the alerts to the webhook-tester

Webhook-tester UI
![webhook-tester-ui](/images/webhook-tester.png)

### 7.10 KeepHQ

### 7.11 Storage (MinIO)

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

### 7.12 Alloy exporter

https://alloy.localhost

Alloy
![alloy](./images/alloy.png)

Alloy Graph
![alloy-graph](./images/alloy-graph.png)

### 7.13 Blackbox exporter

https://blackbox.localhost

Blackbox dashboard
![blackbox-dashboard](/images/blackbox-dashboard.png)

### 7.14 node-exporter

nodes-exporter-full
![nodes-exporter-full-dashboard](/images/node-exporter-dashbaord.png)

### 7.15 podman-exporter

podman-exporter
![podman-exporter-dashboard](/images/podman-exporter-dashboard.png)

### 7.16 OpenTelemetry-collector

OpenTelemetry-collector
![opentelemetry-collector-dashboard](/images/opentelemetry-collector-dashboard.png)

### 7.17 Traefik

Go to: https://traefik.localhost

Treafik
![traefik](/images/traefik.png)

Treafik dashboard
![traefik](/images/traefik.dashboard.png)

## 8. Teardown & Cleanup

This sections explains how to remove everthing.

```bash
   # stop all containers
   podman-compose down
   
   # show volumes
   podman volume ls | grep monitoring
   local       monitoring_prometheus-data
   local       monitoring_loki-wal
   local       monitoring_tempo-wal
   local       monitoring_minio-data
   local       monitoring_grafana-data
   local       monitoring_keep-db-data
   local       monitoring_keep-state
   
   # remove volumes
   podman volume rm monitoring_prometheus-data monitoring_loki-wal monitoring_tempo-wal monitoring_minio-data monitoring_grafana-data monitoring_keep-db-data monitoring_keep-state
   
   # remove certificates
   sudo rm /etc/pki/ca-trust/source/anchors/my-local-ca.pem
   sudo rm /etc/pki/ca-trust/source/anchors/my-local-ca.crt
   sudo update-ca-trust extract
   
   # disable podman socket
   systemctl --user disable --now podman.socket
   
   # remove rootless ports
   sudo rm /etc/sysctl.d/99-rootless-ports.conf
   
   # remove monitoring repo
   rm -rf path-to-your-repo/monitoring
```