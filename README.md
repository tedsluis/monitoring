# Full Stack Observability & Monitoring Platform
## An Educational Lab for Prometheus, Loki, Tempo, Grafana, and Alerting

This repository contains a complete, production-like observability stack optimized for Fedora Workstation with rootless Podman. It is designed as an educational environment to help Developers and DevOps Engineers understand how modern monitoring tools interlock to provide comprehensive metrics, logging, tracing, and alerting capabilities. The entire stack is automatically configured upon startup, including pre-provisioned Grafana dashboards, datasources, and alerting rules.

Diagram
![diagram](./images/overview-diagram.svg)

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

![metrics](./images/prometheus-metrics-diagram.svg)

- **Logging Flow**: System (journald) and Container logs -> Grafana Alloy collects them -> Pushed to Loki -> Stored in MinIO -> Visualized in Grafana.

![logging](./images/loki-logging-diagram.svg)

- **Tracing Flow**: Application traces -> OpenTelemetry Collector -> Pushed to Tempo -> Stored in MinIO -> Visualized in Grafana.

![tracing](./images/tempo-tracing-diagram.svg)

- **Alerting Flow**: Prometheus evaluates alert.rules.yml -> Fires to Alertmanager -> Alertmanager routes to Karma (UI), KeepHQ (AIOps), and Webhook-tester.

![alerting](./images/alerting-diagram.svg)

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

### 5.1 Overview

-   OS: Fedora Linux (tested on Fedora 43 and 44).
-   Tools: podman and podman-compose.
-   Podman Socket: The user socket must be active for the Podman Exporter and Alloy.
   
### 5.2 podman & podman-compose to run containers

This stack is using `podman` and `podman-compose` where you may be used to `docker` and `docker-compose`. While Docker is commonly used, there are good reasons to use Podman due to several key architectural and security advantages:

*   **Daemonless Architecture:** Unlike Docker, which requires a heavy, central background daemon (`dockerd`) running as root to manage containers, Podman is daemonless. It interacts directly with the container registry and runtime. This means no single point of failure—if the Docker daemon crashes, container management halts. With Podman, each container runs as an independent process.
*   **Rootless by Design (Enhanced Security):** Security is a primary focus for Podman. It allows you to run containers as a standard, non-root user out of the box. If a container is somehow compromised, the attacker is confined to the privileges of that standard user, preventing them from gaining root access to the host machine. 
*   **Fully Open Source & Unrestricted:** Podman is a fully open-source project driven by the community and Red Hat. Unlike Docker Desktop, which has introduced commercial licensing and subscription models for enterprise environments, Podman remains completely free and unrestricted for all use cases.
*   **Drop-in Replacement:** The transition is practically seamless. Podman's CLI is intentionally designed to be identical to Docker's. You can simply add `alias docker=podman` to your shell profile, and all your familiar commands (`build`, `run`, `ps`, `pull`) will work exactly as expected.
*   **Native Systemd Integration:** Podman integrates fully Linux environments. It can easily generate and manage `systemd` unit files from running containers, allowing you to treat containers as native system services that start automatically on boot.
*   **Kubernetes Readiness:** Podman introduces the concept of "pods" (groups of containers sharing the same network and namespaces) locally, mirroring how Kubernetes operates. It can even generate Kubernetes YAML from local containers or run existing Kubernetes YAML directly, making the transition from local development to production orchestration much smoother.


### 5.3 Install requirements
```bash
   # Install packages
   sudo dnf install podman podman-compose -y
   
   # Activate the Podman socket for your user (Rootless)\
   # run as a regular user, not as root!
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

### 6.2 Using an http internet proxy? Update your no_proxy

This step is optional in case you use a http proxy for your internet connection and you have configured environment variables like `http_proxy`, `https_proxy`, `no_proxy`, `HTTP_PROXY`, `HTTPS_PROXY` and `NO_PROXY`. In that case you need to add hostnames and IP addresses that are used inside this monitoring stack to your `no_proxy` and `NO_PROXY`. Source the script below to add the nessesary hostnames and IP addresses.

```bash
  source ./prepare_no_proxy.sh 
```

### 6.3 Start the stack
```bash
   # Important: only run this step after you have finshed all the steps in the Prerequisites!
   podman-compose up -d
```
The first time, the `minio-init` container will automatically create the required buckets (`loki-data` and `tempo-data`).

### 6.4 Generate Local TLS Certificates
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
**note:** Before you try `https://localhost` in your web browser, make sure you restart your browser first!

### 6.5 Check the status
```bash
podman ps -a
CONTAINER ID  IMAGE                                                                                                                    COMMAND               CREATED       STATUS                   PORTS                                                             NAMES
b8db045c2924  quay.io/prometheus/alertmanager@sha256:88b605de9aba0410775c1eb3438f951115054e0d307f23f274a4c705f51630c1                  --config.file=/et...  13 hours ago  Up 13 hours (healthy)    9093/tcp                                                          alertmanager
99746eba94b1  docker.io/grafana/alloy@sha256:8f5666aebb871ba43ee2d65159c5d1c26c903720efafaf2d9ed4e237afc3bc88                          run --server.http...  13 hours ago  Up 13 hours                                                                                alloy
2bbaf8abf010  quay.io/prometheus/blackbox-exporter@sha256:e753ff9f3fc458d02cca5eddab5a77e1c175eee484a8925ac7d524f04366c2fc             --config.file=/co...  13 hours ago  Up 13 hours              9115/tcp                                                          blackbox-exporter
a56668a969be  docker.io/library/postgres@sha256:4da1a4828be12604092fa55311276f08f9224a74a62dcb4708bd7439e2a03911                       postgres              13 hours ago  Up 13 hours (healthy)    5432/tcp                                                          keep-db
d3ef02cfc919  docker.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e                            server /data --co...  13 hours ago  Up 13 hours (healthy)    9000/tcp                                                          minio
5c7253e032a8  docker.io/library/nginx@sha256:e7257f1ef28ba17cf7c248cb8ccf6f0c6e0228ab9c315c152f9c203cd34cf6d1                          nginx -g daemon o...  13 hours ago  Up 13 hours (healthy)    80/tcp                                                            nginx
9faae1ccbe5e  quay.io/prometheus/node-exporter@sha256:337ff1d356b68d39cef853e8c6345de11ce7556bb34cda8bd205bcf2ed30b565                 --path.rootfs=/ho...  13 hours ago  Up 13 hours (healthy)    9100/tcp                                                          node-exporter
19627b6c8326  quay.io/navidys/prometheus-podman-exporter@sha256:2ebb9e09101d8cc1e28e3f306b56a722450918e628208435201ed39bd62403cb                             13 hours ago  Up 13 hours (healthy)    9882/tcp                                                          podman-exporter
f08df82fcea2  quay.io/prometheus/prometheus@sha256:7571a304e67fbd794be02422b13627dc7de822152f74e99e2bef95d29eceecde                    --config.file=/et...  13 hours ago  Up 13 hours (healthy)    9090/tcp                                                          prometheus
ca01ef826b99  docker.io/library/traefik@sha256:acfc80650104f0194a15f73dc1648f517561bc1645391a15705332a064cfc33c                        traefik               13 hours ago  Up 13 hours (healthy)    0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:4317->4317/tcp  traefik
e6cd2cf7e97a  docker.io/tarampampam/webhook-tester@sha256:7df929897b150aec5b60d77529ae863f69238cf74f0e47c161258fcc185f3e0c             start                 13 hours ago  Up 13 hours                                                                                webhook-tester
fe1fe0aafcec  ghcr.io/prymitive/karma@sha256:cae0afb8d083756a7a44413480847fa59c072659d909734924a10640e1de600d                                                13 hours ago  Up 13 hours              8080/tcp                                                          karma
4a832c4f2cdb  us-central1-docker.pkg.dev/keephq/keep/keep-api@sha256:0e95b90210f2caeaf6a654daec274cfe43101cf1c4cdbc9cd1fec1a99e791af6  gunicorn keep.api...  13 hours ago  Up 13 hours (healthy)                                                                      keep-backend
aa0d66edfc89  docker.io/minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727                                                     13 hours ago  Exited (0) 13 hours ago                                                                    minio-init
736a0b57ef1f  us-central1-docker.pkg.dev/keephq/keep/keep-ui@sha256:2041f65c7bbd64c2a800a4d11eedf0e99b89debfd6b88f0bbb109443eb6bcc23                         13 hours ago  Up 13 hours (healthy)    3000/tcp                                                          keep-frontend
af2575426baf  docker.io/grafana/loki@sha256:3c8fd3570dd9219951a60d3f919c7f31923d10baee578b77bc26c4a0b32d092d                           -config.file=/etc...  13 hours ago  Up 13 hours              3100/tcp                                                          loki
6f71a3bcc52d  docker.io/grafana/tempo@sha256:cac9de2ac9f6da8efca5b64b690a7cb8c786a0c49cac7b4517dd1b0089a6c703                          -config.file=/etc...  13 hours ago  Up 13 hours                                                                                tempo
ce958ef62c3e  docker.io/otel/opentelemetry-collector-contrib@sha256:8164eab2e6bca9c9b0837a8d2f118a6618489008a839db7f9d6510e66be3923c   --config=/etc/ote...  13 hours ago  Up 13 hours              4317-4318/tcp, 55679/tcp                                          otel-collector
66c8b0604c18  docker.io/grafana/grafana@sha256:e932bd6ed0e026595b08483cd0141e5103e1ab7ff8604839ff899b8dc54cabcb                                              13 hours ago  Up 13 hours (healthy)    3000/tcp                                                          grafana
```
note: The minio-init container only runs when starting minio.

### 6.6 Stop, start or restart with podman-compose

**podman-compose** is a utility designed to help you define and run multi-container applications seamlessly without relying on a central daemon.

*   **What it is:** `podman-compose` is a script that allows you to manage multi-container environments using Podman. It is fully compatible with the Compose specification, meaning you can often use your existing `docker-compose` projects without any modifications.
*   **How it works:** Under the hood, `podman-compose` reads your configuration file and translates the instructions into native Podman commands. Because Podman is daemonless and rootless, `podman-compose` executes these commands in the context of the user running it. It automatically handles the creation of networks (or Pods, depending on the configuration) so your containers can securely discover and communicate with each other locally.
*   **The Role of [compose.yml](./compose.yml):** The [compose.yml](./compose.yml) file serves as the definitive blueprint for your application stack. It is a declarative YAML file where you define your entire infrastructure as code: services, image versions, port mappings, persistent volumes, and environment variables. Instead of manually executing long strings of CLI commands, you simply run `podman-compose up -d`, and the tool reads this file to build, connect, and start your entire environment in a reproducible way.

```bash
   # Podman Help
   podman-compose --help

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

### 6.7 Generic podman commands

```bash
   # Podman Compose Help
   podman --help

   # check container log
   podman logs prometheus

   # keep following container log
   podman logs -f blackbox

   # list running containers
   podman ps

   # list all containers (including stopped containers)
   podman  ps -a

   # restart a container
   podman restart loki 

   # execute a query in a postgres container
   podman exec -it keep-db psql -U keep -d keep -c "\d tenant;"

   # Lookup health state log properties of a container
   podman inspect --format='{{json .State.Health}}' tempo | jq '.Log[-1]'

   # run a https request to docker.io in a temporary curl container
   podman run --rm docker.io/curlimages/curl:latest -sI "https://auth.docker.io/token?service=registry.docker.io"
```

Docs: https://podman.io/docs

## 7. Usage

### 7.1 NGINX landing page

Go to **https://localhost**

To make navigating this observability stack effortless, we use NGINX to serve a static landing page [index.html](./landing-page/index.html). This page acts as the central frontend portal for all the monitoring tools. 

Instead of memorizing various ports and subdomains, this portal provides a clean, unified interface with quick links to everything you need:
*   **Tools:** Direct access to all core applications like Grafana, Prometheus, Alertmanager, Karma, KeepHQ and MinIO.
*   **Metrics Exporters:** Quick links to the raw metric endpoints for all running services and exporters.
*   **Grafana Dashboards:** Direct links to instantly open the pre-provisioned dashboards.
*   **Drilldown & Explore:** Shortcuts to advanced Grafana Explore and Drilldown views for metrics, logs, and traces.

*See the screenshots below for an impression of the NGINX landing pages:*


![startpagina1](./images/startpagina1.png)


![startpagina2](./images/startpagina2.png)


![startpagina3](./images/startpagina3.png)


![startpagina4](./images/startpagina4.png)

### 7.2 Login credentials (Defaults)

In case you navigate to Grafana or Minio, you need to login with the user accounts below:

| Service | Username       | Password   | Note                                   |
|---------|----------------|------------|----------------------------------------|
| Grafana | admin          | admin      | You can change this after first login. |
| MinIO   | minio          | minio123   | Can be changed in compose.yml          |

### 7.3 Prometheus Metrics

Prometheus is a time-series database that records numeric data, such as CPU usage, network traffic, or application-specific. Prometheus operates on a pull-based model; it actively "scrapes" (fetches) metrics over HTTP from designated target endpoints at regular intervals (in our case every 15 seconds). Once the data is ingested, users can leverage its query language, PromQL, to slice, dice, and aggregate the metrics for visualization in tools like Grafana, or evaluate them against custom rules to trigger real-time notifications via Alertmanager when thresholds are breached.

Today Prometheus 3.x supports not only pull metrics, but also push metrics. In this monitoring stack we push Tempo metrics into Prometheus.

Go to https://prometheus.localhost

| Endpoint paths | Description                    |
|----------------|--------------------------------|
| `/query`       | metrics querier.               |
| `/alerts`      | alert rule overview.           |
| `/targets`     | status of the scrape targets.  |
| `/config`      | full prometheus configuration. |


*See the screenshot below for an impression of the Prometheus UI - alert rules overview:*
![prometheus](images/prometheus.png)


| configuration        | configuration file                                           |
|----------------------|--------------------------------------------------------------|
| scrape target        | [./prometheus/prometheus.yml](./prometheus/prometheus.yml)   |
| alert rules          | [./prometheus/alert.rules.yml](./prometheus/alert.rules.yml) |

Prometheus exposes and scrapes its own metrics. Using these metrics you can monitor prometheus, see below:

*See the screenshot below for an impression of the Prometheus metrics dashboard:*
![prometheus-dashboard](./images/prometheus-dashboard.png)

**Docs:**

* https://prometheus.io/docs/introduction/overview/
* https://prometheus.io/docs/instrumenting/exporters/
* https://github.com/prometheus/prometheus

### 7.4 Loki

Grafana Loki is a log aggregation system inspired by Prometheus. Unlike traditional logging systems (such as the Elastic Search) that index the full text of every log line, Loki only indexes the metadata (labels) attached to each log stream. This unique design choice makes it exceptionally lightweight, cost-effective, and fast to operate. 

In a typical workflow, a collector like Grafana Alloy gathers logs from your containers or system journals and pushes them to Loki. Loki then compresses this data into chunks and stores it efficiently in an object storage backend like MinIO. Users can seamlessly search and analyze these logs in Grafana using LogQL (Loki Query Language), leveraging the exact same labels used in Prometheus to instantly correlate metrics spikes with their underlying log events.

Loki does not include a built-in user interface. Instead, it relies entirely on Grafana to serve as the unified dashboard for exploring and analyzing your logs, for example:

*See the screenshot below for an impression of the Loki logging dashboard:*
![loki-logs-dashboard](./images/loki-logs-dashboards.png)


| configuration        | configuration file                                                                 |
|----------------------|------------------------------------------------------------------------------------|
| Loki config          | [./loki/loki-config.yaml](./loki/loki-config.yaml)                                 |
| Loki alert rules     | [./loki/rules/fake/loki-alert-rules.yaml](./loki/rules/fake/loki-alert-rules.yaml) |

Like most modern container, Loki exposes prometheus metrics too, which are used to monitor Loki using the dashboard below:

*See the screenshot below for an impression of the Loki metrics dashboard:*
![loki-metrics-dashboard](/images/loki-metrics-dashboard.png)

**Docs:**

* https://grafana.com/docs/loki/latest/
* https://github.com/grafana/loki

### 7.5 Tempo

Grafana Tempo is a tracing backend designed to track the flow of requests as they travel through complex architectures and microservices. It helps developers and operators pinpoint exactly where latency, bottlenecks, or errors are occurring in a system. Unlike older tracing tools that require heavy, complex databases for indexing, Tempo is exceptionally cost-effective because it only requires a basic object storage backend (like MinIO or S3) to store the raw trace data. 

In a typical setup, an OpenTelemetry Collector gathers traces from your applications and pushes them to Tempo. Within Grafana, users can visualize these request lifecycles using TraceQL, and seamlessly jump directly from a log line in Loki to the exact corresponding trace span in Tempo for rapid root cause analysis.

Loki does not include a built-in user interface. Instead, it relies entirely on Grafana to serve as the unified dashboard for exploring and analyzing your logs, for example:

*See the screenshot below for an impression of the Tempo Tracing dashboard:*
![tempo-dashboard](./images/)

| configuration        | configuration file                         |
|----------------------|--------------------------------------------|
| Tempo config         | [./tempo/tempo.yaml](./tempo/tempo.yaml)   |

*Tempo exposes prometheus metrics too, which are used to monitor Loki using the dashboard below:*
![Tempo-dashboard](./images/tempo-dashboard.png)

**Docs:**

* https://grafana.com/docs/tempo/latest/
* https://github.com/grafana/tempo

### 7.6 Alertmanager

Alertmanager is a alert routing and management component that works hand-in-hand with both Prometheus and Loki. While Prometheus and Loki are responsible for evaluating metric and logging thresholds and firing raw alerts, Alertmanager takes over to handle the complex logistics of notifications. It deduplicates and intelligently groups related alerts together, preventing engineers from being overwhelmed by "alert fatigue" during major system outages. Once grouped, it routes these notifications to the appropriate downstream receivers, such as Karma for visualization, KeepHQ for AIOps, or webhook-tester for debugging. 

Alertmanager also supports advanced operational features like silencing (temporarily muting specific alerts) and inhibition (suppressing lower-priority alerts if a related high-priority alert is already active), ensuring that teams only receive the most actionable signals.

Go to https://alertmanager.localhost

| Path        | Description                                    |
|-------------|------------------------------------------------|
| /#/alerts   | Overview of current alerts                     |
| /#/silences | Ability to silence alerts                      |
| /#/status   | Alertmanager status and configuration overview |
| /#/settings | Alertmanager UI settings                       |


*See the screenshot below for an impression of the Alertmanager UI:*
![alertmanager](/images/alertmanager.png)

| configuration        | configuration file                                                  |
|----------------------|---------------------------------------------------------------------|
| Alertmanager config  | [./alertmanager/alertmanager.yml](./alertmanager/alertmanager.yml) |

Alertmanager exposes prometheus metrics too, which are used to monitor Alertmanager using the dashboard below:

*See the screenshot below for an impression of the Alertmanager metrics dashboard:*
![alertmanager-dashboard](./images/alertmanager-metrics-dashboard.png)

**Docs:**

* https://prometheus.io/docs/alerting/latest/alertmanager/
* https://github.com/prometheus/alertmanager


### 7.7 Grafana

Go to https://grafana.localhost

Grafana is the central visual heart of this stack and functions as a 'single pane of glass' for all data. The open-source platform connects to Prometheus (metrics), Loki (logs) and Tempo (traces), enabling deep system insight through dashboards and the Explore mode. Thanks to automated provisioning, datasources and dashboards are loaded at startup, so everything works without manual configuration.

**Docs:**

* https://grafana.com/docs/grafana/latest/
* https://github.com/grafana/grafana

#### 7.7.1 Dashboards

This repo contains a number of Grafana dashboards stored in [./grafana-provisioning/dashboards/json/](./grafana-provisioning/dashboards/json/) in JSON format.

*See the screenshot below for an overview of the Grafana Dashboards:*
![grafana-dashboarden](./images/grafana-dashboards.png)

#### 7.7.2 Explore

The Explore mode provides an advanced interface for ad-hoc analysis and troubleshooting, where users can execute queries directly. Explore thus facilitates rapid incident diagnosis and root-cause analysis, without the need to configure predefined dashboards in advance.

**Loki logs explore**

 The Loki datasource combined with LogQL makes it possible to efficiently filter log streams by labels, search for specific text patterns or regular expressions, and visualize log volumes alongside raw log lines.

 *See the screenshot below for an impression of the Explore logs:*
![Loki-explore](/images/explore-logs.png)

**Prometheus metrics explore**

The Prometheus datasource, combined with PromQL queries, enables iterative exploration of time-series data, trend visualization, and comparison of metrics using split-view functionality.

*See the screenshot below for an impression of the Explore metrics:*
![prometheus-explore](/images/explore-metrics.png)

**Tempo tracing explore**

The Tempo datasource combined with TraceQL provides a detailed visualization of the lifecycle of requests through the distributed architecture. Using the waterfall view, users can analyze latency per component, isolating performance bottlenecks and errors within specific spans. Integration with TraceQL enables targeted filtering of traces, which, combined with correlated logs and metrics, allows efficient root-cause analysis during incidents. For example, it can be interesting to filter for requests that do not have an HTTP status code of 4xx or 5xx, or requests that take longer than 500ms.

*See the screenshot below for an impression of the Explore traces:*
![tempo-explore](/images/explore-traces.png)


To manually test the proxy path by sending a traceparent header, run this command in your terminal:
```bash
   curl -k -H "traceparent: 00-11112222333344445555666677778888-1111222233334444-01" https://grafana.localhost/api/health
```
Next, in Grafana, go to Tempo Explore and search for the exact Trace ID: 11112222333344445555666677778888.
If propagation works, you'll see a beautiful trace tree with the Traefik span at the top and the Grafana span below.

*See the screenshot below for an impression of the Explore traces - service graph:*
![traces-explore](/images/explore-traces-service-graph.png)

#### 7.7.3 Drilldown

The drill-down functionality within Grafana offers the ability to connect in-depth error analysis through metrics, logs and traces contextually with each other. From an anomaly in a metrics dashboard, you can directly navigate to the correlated log lines in Loki, and then use automatically detected trace IDs to switch to detailed request spans in Tempo. This integration eliminates the need to manually synchronize timestamps and identifiers between different datasources, significantly increasing the efficiency of root cause analysis and performance optimization.

*See the screenshot below for an impression of the Metrics drilldown:*
![Metrics-drilldown](/images/drilldown-metrics-dashboard.png)

*See the screenshot below for an impression of the Logs drilldown:*
![loki-drilldown](/images/drill-down-logs-dashboard.png)

*See the screenshot below for an impression of the Traces drilldown:*
![traces-drilldown](/images/drilldown-breakdown.png)

#### 7.7.4 Grafana alerts

Grafana Alerting provides a central interface for monitoring alerts. This module aggregates alert rules from both Prometheus (for metrics) and Loki (for log data), creating an overview of the operational status. Through this dashboard you can analyze the real-time status of alerts (‘Pending’ or ‘Firing’), examine the underlying query definitions, and gain insight into the evaluation criteria that safeguard the platform’s stability and availability.

*See the screenshot below for an impression of the Grafana Alerting:*
![grafana-alerting](/images/grafana-alerts.png)

#### 7.7.5 Grafana datasources

Datasources in Grafana serve as the technical interface to the underlying data storage systems, allowing the application to retrieve data without persisting it itself. In this configuration, Prometheus, Loki and Tempo are defined as the primary sources for exposing metrics, log files and distributed traces, respectively.

*See the screenshot below for an impression of the Grafana Datasources:*
![grafana-datasources](./images/grafana-datasource.png)

The datasources for Prometheus, Loki and Tempo are configured in [./grafana-provisioning/dashboards/dashboard.yaml](./grafana-provisioning/datasources/datasources.yaml)

### 7.8 Karma Alert Dashboard

Karma is a specialized, highly visual dashboard designed specifically for Alertmanager. While Alertmanager excels at routing and grouping alerts, its default UI is quite basic. Karma fills this gap by providing an intuitive, color-coded, and auto-refreshing interface that gives Operations and DevOps teams a consolidated overview of the platform's health at a glance.

Go to https://karma.localhost

**How it works in this stack:**

* **Direct Alertmanager Integration:** Karma continuously polls Alertmanager to display active alerts in organized, collapsible groups based on their severity and source.
* **Prometheus History:** It connects directly to Prometheus to enrich the current alerts with historical context, allowing you to see if an alert has been flapping.
* **Custom Color Coding:** As defined in karma.yaml, alerts are customized with distinct colors based on their severity (e.g., Red for Critical, Orange for Warning) and the specific job that triggered them (e.g., node-exporter, loki, alloy). This makes visual identification instantaneous.
* **Noise Reduction:** It automatically filters out constant background alerts like the 'Watchdog' (dead man's switch) and strips redundant receiver labels to keep the dashboard clean and actionable.
* **Live Auto-Refresh:** The dashboard automatically refreshes every 20 seconds so you never miss a critical state change.


| configuration        | configuration file                         |
|----------------------|--------------------------------------------|
| Karma config         | [./karma/karma.yaml](./karma/karma.yaml)   |

**See the screenshot below for an impression of the Karma UI:*
![karma](images/karma.png)
An overview of all active warnings (e.g., "Disk almost full", "Container down" or "Health Check Failed").

**Docs:**

* https://github.com/prymitive/karma

### 7.9 webhook-tester

Webhook-tester is a lightweight and incredibly useful utility for debugging and inspecting incoming HTTP requests. In this observability stack, it acts as a "dummy" or "catch-all" receiver for Alertmanager.

Go to https://webhook-tester.localhost

**How it works in this stack:** When Prometheus fires an alert, Alertmanager processes and routes it based on its configuration. By configuring Alertmanager to send a webhook to this tester, you can inspect the exact, raw JSON payloads that Alertmanager generates in real-time. This is highly beneficial for:

* **Debugging Alert Payloads:** Understanding the exact data structure, labels, and annotations that get sent out when an alert triggers.
* **Template Development:** Testing custom notification templates before connecting them to real-world communication channels (like Slack, Microsoft Teams, or PagerDuty).
* **Integration Testing:** Verifying that the alert routing rules in Alertmanager are working correctly and actually triggering the appropriate webhooks.

*See the screenshot below for an impression of the Webhook-tester UI:*
![webhook-tester-ui](/images/webhook-tester.png)

**Docs:**

* https://github.com/tarampampam/webhook-tester

### 7.10 KeepHQ

KeepHQ is an open-source AIOps and alert management platform. While Alertmanager handles the initial routing and deduplication of alerts, KeepHQ takes alert management a step further by providing advanced correlation, noise reduction, and automated workflow execution (auto-remediation). It acts as a single pane of glass for all your alerts, enriching them with context from various tools.

https://keep.localhost

KeepHQ is an open-source AIOps and alert management platform. While Alertmanager handles the initial routing and deduplication of alerts, KeepHQ takes alert management a step further by providing advanced correlation, noise reduction, and automated workflow execution (auto-remediation). It acts as a single pane of glass for all your alerts, enriching them with context from various tools.

**How it works in this stack:** KeepHQ is deployed using three containers: a PostgreSQL database (`keep-db`), the core API and AIOps engine (`keep-backend`), and the web interface (`keep-frontend`).

**Automatic Provider Configuration (IaC):** For KeepHQ to intelligently correlate alerts and execute workflows, it needs access to your metrics and logs. Instead of manually configuring these connections in the Keep UI, this stack automatically provisions them on startup using provider configuration files located in `/home/tedsluis/monitoring/keep/providers/`:

| provider config                                   | description                                                                                                                                                                                                   |
|---------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [prometheus.yml](./keep/providers/prometheus.yml) | Automatically configures the local Prometheus instance as a data source (`http://prometheus:9090`). This allows KeepHQ to dynamically query time-series metrics to gather deeper context when an alert fires. |
| [loki.yml](./keep/providers/loki.yml)             | Automatically configures the local Grafana Loki instance as a data source (`http://loki:3100`). This enables KeepHQ to directly fetch relevant log lines and event streams associated with an incident.       |

By injecting these configurations via Infrastructure as Code, KeepHQ is instantly ready to query both metrics and logs the moment the stack boots up, significantly accelerating troubleshooting and providing a seamless AIOps experience.

**Docs:**

* https://docs.keephq.dev/overview/introduction
* https://github.com/keephq/keep

### 7.11 Storage (MinIO)

MinIO is a high-performance, S3-compatible object storage server. In this observability stack, it serves as the persistent, long-term storage backend for both Grafana Loki (logs) and Grafana Tempo (traces).

Go to https://minio.localhost

**Why use MinIO?** Modern observability tools like Loki and Tempo have deliberately moved away from requiring heavy, complex databases (like Elasticsearch or Cassandra) for storage. Instead, they maintain a lightweight local index and push the bulk of their compressed log chunks and trace data into cheap, scalable object storage. MinIO provides this exact S3-like API locally, mimicking what you would use in the cloud (like AWS S3 or Google Cloud Storage).

**How it works in this stack:** 

* **Automatic Bucket Provisioning:** When you start the stack, a temporary helper container named minio-init runs alongside the main MinIO server. It automatically connects to the server and creates the necessary storage buckets (loki-data and tempo-data). Once done, the helper container gracefully exits.
* **Storage Flow:** Loki and Tempo are configured to treat MinIO just like AWS S3. As they collect logs and traces, they bundle them into chunks and push them to their respective buckets in MinIO.
* **Console & Management:** Through the MinIO UI (link above), you can browse these objects, inspect bucket policies, and see exactly how much storage your logs and traces are consuming.

*See the screenshot below for an impression of the Minio UI - login:*
![minio](images/minio-login.png)

*See the screenshot below for an impression of the Minio UI - object browser:*
![minio-object-browser](./images/minio-object-browser.png)

*See the screenshot below for an impression of the Minio overview dashboard:*
![minio](./images/minio-dashboard.png)

*See the screenshot below for an impression of the Minio bucket dashboard:*
![minio-bucket](./images/minio-bucket-dashboard.png)

*See the screenshot below for an impression of the Minio node dashboard:*
![minio-node](./images/minio-node-dashboard.png)

**Docs:**

* https://github.com/minio/minio
* https://docs.min.io/enterprise/aistor-object-store/

### 7.12 Alloy exporter

Grafana Alloy is a highly configurable, vendor-neutral observability data pipeline. In this monitoring stack, Alloy acts as the primary log collector and processor, bridging the gap between your raw logs (both container and host-level) and Grafana Loki.

Go to https://alloy.localhost

**How it works in this stack (config.alloy):** The configuration file located at [alloy/config.alloy](./alloy/config.alloy) defines two main data streams that converge into a single output pushed to Loki:

* **Stream 1:** Container Logs (`Podman Socket`): Alloy discovers all running containers via the local Podman socket (/var/run/docker.sock). Instead of just grabbing raw logs, it enriches them with highly useful metadata. It extracts the container_name, shortens the container_id to 12 characters for precision, and tags the image, pod_name, and compose project. This enrichment is what allows you to effortlessly filter logs in Grafana based on specific containers or pods.
* **Stream 2:** Host System Logs (`Journald`): Alloy also reads the host machine's system logs directly from /var/log/journal. It extracts the systemd unit (e.g., sshd.service), syslog_identifier, and the log level (e.g., info, warning, err) so you can quickly filter for host-level errors.
* **Smart Deduplication:** Because rootless Podman automatically writes container logs to the host's system journal as well, simply collecting both streams would result in duplicate logs in Loki. The config.alloy explicitly prevents this by applying a loki.relabel rule that drops any journald log containing a container ID. This ensures your logs remain clean and accurate.

Through the Alloy web UI, you can view the health of these components and visually inspect the data flow pipeline using the Graph tab.

*See the screenshot below for an impression of the Alloy UI:*
![alloy](./images/alloy.png)

*See the screenshot below for an impression of the Alloy Graph:*
![alloy-graph](./images/alloy-graph.png)

**Docs:**

* https://grafana.com/docs/alloy/latest
* https://github.com/grafana/alloy

### 7.13 Blackbox exporter

The Prometheus Blackbox Exporter is a probing tool that allows you to monitor the external health, availability, and response times of your endpoints. Instead of relying on internal application metrics (white-box monitoring), the Blackbox Exporter performs active "black-box" testing by making HTTP requests, TCP connections, or ICMP pings over the network just like a real user or client would.

https://blackbox.localhost

**How it works in this stack:** The Blackbox Exporter acts as a proxy. Prometheus asks the Blackbox Exporter to probe a specific target using a specific module, and the Exporter returns metrics based on the result of that probe (e.g., probe_success, probe_duration_seconds).

* **Configuration (blackbox.yml):** The configuration file located at [blackbox/blackbox.yml](./blackbox/blackbox.yml) defines the modules (the "how"). For instance, it configures an `http_2xx` module which dictates that a probe is only successful if the target returns an HTTP 200 OK status. It also defines modules like tcp_connect to verify if a raw network port is open.
* **Prometheus Scrape Jobs** (`prometheus.yaml`): While blackbox.yml defines the methods, prometheus.yaml defines the targets (the "what"). This stack includes several dedicated scrape jobs to ensure critical services are running:

| prometheus scrape Job | description                                                                                                                                                                                                                                                  |
|-----------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| blackbox-http         | A general-purpose job that probes standard web endpoints to verify if HTTP services are responding correctly.                                                                                                                                                |
| blackbox-keep-api     | A targeted probe specifically monitoring the backend API of KeepHQ to ensure the AIOps engine is healthy and accepting requests.                                                                                                                             |
| blackbox-keep-ui      | A targeted probe verifying that the KeepHQ frontend interface is accessible to users.                                                                                                                                                                        |
| blackbox-tcp          | This job uses the TCP module to probe non-HTTP services. It checks if specific ports (like database ports or internal communication sockets) are open and successfully accepting TCP handshakes.                                                             |
| blackbox_exporter     | This job doesn't probe external targets. Instead, it scrapes the internal metrics of the Blackbox Exporter container itself, allowing you to monitor how many probes have been executed, how long they took, and if the exporter is experiencing any errors. |

*See the screenshot below for an impression of the Blackbox dashboard:*
![blackbox-dashboard](/images/blackbox-dashboard.png)

**Docs:**

* https://github.com/prometheus/blackbox_exporter

### 7.14 node-exporter

The Prometheus Node Exporter is a fundamental component for infrastructure monitoring. While other exporters focus on specific applications, databases, or container engines, the Node Exporter focuses entirely on the host machine itself (in this case, your underlying Fedora Workstation).

**How it works in this stack:** It exposes a wide variety of hardware and OS-level metrics, such as CPU utilization, memory consumption, disk space, disk I/O, network bandwidth, and system load. Prometheus scrapes these metrics, allowing you to trigger alerts (e.g., "Disk almost full") and visualize the overall health of your host hardware.

**Bypassing Container Isolation (compose.yml):** By design, containers are isolated from the host. To accurately measure the host's hardware, the Node Exporter container requires special configuration. In the compose.yml, it is explicitly set to use network_mode: host and pid: host. Additionally, it mounts the host's entire root filesystem (/) to a /host directory inside the container. This deliberately breaks the container's isolation, allowing the exporter to read the actual /proc and /sys files of the underlying host operating system.

*See the screenshot below for an impression of the nodes-exporter-full dashboard:*
![nodes-exporter-full-dashboard](/images/node-exporter-dashbaord.png)

**Docs:**

* https://prometheus.io/docs/guides/node-exporter/
* https://github.com/prometheus/node_exporter

### 7.15 podman-exporter

The Prometheus Podman Exporter is designed to extract metrics specifically from a Podman environment. Since this observability stack intentionally uses daemonless, rootless Podman instead of Docker, traditional Docker exporters will not work. This exporter bridges that gap by providing deep visibility into your container runtime.

**How it works in this stack:** It exposes comprehensive metrics about running containers, pods, images, and volumes (e.g., container CPU/memory usage, network I/O, and container state). Prometheus scrapes these metrics, which power the dedicated Podman Grafana dashboards, allowing you to track the exact resource footprint of each service in the stack.

**Rootless Socket Connection (compose.yml):** To gather these metrics securely, the exporter needs to talk to the Podman API. In the compose.yml, this is achieved by mapping the host user's specific rootless Podman socket (`/run/user/1000/podman/podman.sock`) directly into the container. Furthermore, an environment variable `CONTAINER_HOST=unix:///run/podman/podman.sock` directs the exporter to listen to this specific socket, allowing it to monitor the containers without requiring root privileges on the host machine.

*See the screenshot below for an impression of the podman-exporter dashboard:*
![podman-exporter-dashboard](/images/podman-exporter-dashboard.png)

**Docs:**

* https://github.com/containers/prometheus-podman-exporter

### 7.16 OpenTelemetry-collector

The OpenTelemetry (OTel) Collector is a vendor-agnostic proxy, router, and processor for telemetry data. While it has the capability to handle metrics and logs, in this observability stack it is primarily dedicated to handling distributed traces.

**How it works in this stack:** Instead of applications sending trace data directly to the storage backend (Tempo), they send them to the OTel Collector. This architectural pattern decouples your applications from the storage backend, allowing you to easily switch backends, filter sensitive data, or batch requests without needing to change any application code.

* **Trace Ingestion (OTLP):** The collector listens for incoming traces via the standard OpenTelemetry Protocol (OTLP) over gRPC on port `4317`. For instance, Grafana itself is configured in the compose.yml to send its internal traces to this exact port (`GF_TRACING_OPENTELEMETRY_OTLP_ADDRESS=otel-collector:4317`).
* **Forwarding to Tempo:** Once the collector receives and processes the incoming trace spans, it exports them directly to the local Grafana Tempo container, which subsequently stores them persistently in MinIO.
* **Traefik gRPC Routing (compose.yml):** To allow external applications or microservices to securely send traces to the collector, Traefik is configured with a dedicated TCP router using Server Name Indication (SNI). The rule `HostSNI('otel-collector.localhost')` routes incoming gRPC traffic directly to the collector. Additionally, the collector exposes its own internal health and performance metrics via an HTTP endpoint on port `8888`.

*See the screenshot below for an impression of the OpenTelemetry-collector dashboard:*
![opentelemetry-collector-dashboard](/images/opentelemetry-collector-dashboard.png)

**Docs:**

* https://opentelemetry.io/docs/collector/
* https://github.com/open-telemetry/opentelemetry-collector

### 7.17 Traefik

Traefik acts as the Edge Router and Reverse Proxy for this entire observability stack. It is the single entry point that intercepts all incoming requests (like when you visit `https://grafana.localhost`) and dynamically routes them to the correct backend container. Furthermore, it handles all TLS/SSL termination, ensuring your local connections are secure and free of browser warnings.

Go to: https://traefik.localhost

**How it works in this stack:** Traefik uses a combination of auto-discovery and file-based configurations to manage routing:

* **Container Auto-Discovery** ([compose.yml](./compose.yml)): By mounting the rootless Podman socket, Traefik automatically discovers running containers. The routing rules are defined directly on the containers using Docker labels (e.g., `traefik.http.routers.grafana.rule=Host('grafana.localhost'`)).
* **Static Configuration** ([traefik/traefik.yaml](./traefik/traefik.yaml)): This is the main startup configuration. It defines the global "EntryPoints" (port 80 for HTTP, 443 for HTTPS, and 4317 for OTLP). It enforces an automatic redirect from HTTP to HTTPS for all traffic. Additionally, it configures Traefik to send its own internal distributed traces to the OpenTelemetry Collector and exposes its metrics for Prometheus to scrape.
* **Dynamic Certificates** ([traefik/dynamic/tls.yaml](./traefik/dynamic/tls.yaml)): Traefik continuously watches the dynamic directory. This specific file instructs Traefik where to find the custom wildcard certificates (`localhost.crt` and `localhost.key`) generated by the `renew-certs.sh` script, applying them automatically to all `.localhost` routes.
* **Dynamic Routing** ([traefik/dynamic/traefik-dynamic.yaml](./traefik/dynamic/traefik-dynamic.yaml)): While most routing is handled automatically via labels, some services require manual rules. Because the Node Exporter runs on the host network (network_mode: host) to collect accurate hardware data, it lives outside the standard container bridge network. This file explicitly tells Traefik to route requests for node-exporter.localhost out of the container network and into the host machine via `http://host.containers.internal:9100`.

*See the screenshot below for an impression of the Treafik UI:*
![traefik](/images/traefik.png)

*See the screenshot below for an impression of the Treafik dashboard:*
![traefik](/images/traefik.dashboard.png)

**Docs:**

* https://doc.traefik.io/traefik/getting-started/
* https://github.com/traefik/traefik

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
