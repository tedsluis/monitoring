Monitoring Stack (Fedora Workstation & Podman Rootless)
=======================================================

Deze repository bevat een complete, Cloud Native Observability Stack die speciaal is geoptimaliseerd voor Fedora Workstation met Rootless Podman. De stack combineert metrics, logs en traces in één geïntegreerde omgeving met Grafana.

## Features
-----------

-   Metrics: Prometheus (v3.9) met Node Exporter & Podman Exporter.
-   Logs: Grafana Loki (v3.3) met opslag op MinIO (S3).
-   Traces: Grafana Tempo (v2.6) met OpenTelemetry ondersteuning.
-   Collection: Grafana Alloy (vervangt Promtail/Agent) voor het verzamelen van journald logs en traces.
-   Storage: MinIO (S3 compatible) voor langdurige, efficiënte opslag van logs en traces.
-   Alerting: Prometheus Alertmanager gekoppeld aan Karma (dashboard) en Blackbox Exporter (health checks).
-   Security: Volledig compatible met SELinux en draait Rootless (met specifieke fixes voor socket-toegang).

## Architectuur
---------------

De stack bestaat uit de volgende services:

| Service         | Poort | Beschrijving                                     | 
|-----------------|-------|--------------------------------------------------|
| Grafana         | 3000  | Dashboard en visualisatie.                       |
| Prometheus      | 9090  | Time-series database voor metrics.               |
| Alertmanager    | 9093  | Verwerkt en routeert alerts.                     |
| Karma           | 8080  | UI Dashboard voor Alertmanager meldingen.        |
| Loki            | 3100  | Log aggregatie (via MinIO S3).                   |
| Tempo           | 3200  | Distributed Tracing backend (via MinIO S3).      |
| MinIO           | 9000  | S3 Object Storage API.                           |
| MinIO Console   | 9001  | Webinterface voor storage beheer.                |
| Alloy           | 12345 | Collector voor logs (journald) en traces (OTEL). |
| Blackbox        | 9115  | Uitvoeren van HTTP/TCP health probes.            |
| Node-exporter   | 9100  | Host metrics collector.                          |
| podman-exporter | 9882  | podman metrics collector.                        |
| OpenTelemetry   | 8888  | Open Telemetry Collector.                        |

## Prerequisites

-   OS: Fedora Linux (getest op Fedora 43+).
-   Tools: podman en podman-compose.
-   Podman Socket: De user-socket moet actief zijn voor de Podman Exporter en Alloy.

```bash
# Installeer benodigdheden\
sudo dnf install podman podman-compose -y

# Activeer de Podman socket voor je gebruiker (Rootless)\
systemctl --user enable --now podman.socket
```

## Installatie & Starten

1.  Clone de repository:
```bash
    git clone https://github.com/tedsluis/monitoring.git\
    cd monitoring
```
2.  Start de stack:
```bash
    podman-compose up -d
```
    
De eerste keer zal de `minio-init` container automatisch de benodigde buckets (`loki-data` en `tempo-data`) aanmaken.

3.  Controleer de status:
```bash
    podman ps
```

## Configuratie

De configuratie is opgedeeld in mappen per component. Dankzij Grafana Provisioning worden datasources automatisch ingeladen.

### Mappenstructuur

-   `prometheus/`: prometheus.yml en alert.rules.yml.
-   `grafana-provisioning/`: Koppelt Prometheus, Loki en Tempo automatisch aan Grafana.
-   `loki/`: Configuratie voor Loki (S3 backend) en recording rules.
-   `tempo/`: Configuratie voor Tempo (S3 backend).
-   `alloy/`: Pipeline configuratie voor het lezen van journald en de podman.socket.
-   `blackbox/`: Definities voor HTTP health checks.
-   `alertmanager/`: Routing van notificaties.

### Inloggegevens (Defaults)

| Service | Gebruikersnaam | Wachtwoord | Opmerking                   |
|---------|----------------|------------|-----------------------------|
| Grafana | admin          | admin      | Wijzig dit na eerste login! |
| MinIO   | minio          | minio123   | Beheer via poort 9001.      |

## Gebruik


### 1. Dashboards (Grafana)

Ga naar [http://localhost:3000](https://www.google.com/search?q=http://localhost:3000).

-   Metrics: Importeer dashboard ID 1860 (Node Exporter Full) voor systeeminformatie.
-   Logs: Ga naar Explore, kies Loki en zoek op {job="fedora-journal"} om systeemlogs te zien.
-   Traces: Ga naar Explore, kies Tempo om traces te analyseren (indien je apps dit sturen).

### 2. Alerts (Karma)

Ga naar http://localhost:8080.

Hier zie je een overzicht van alle actieve waarschuwingen (bijv. "Disk bijna vol", "Container down" of "Health Check Failed").

### 3. Storage (MinIO)

Ga naar http://localhost:9001.

Hier kun je zien hoeveel data Loki en Tempo verbruiken in hun buckets.

## Troubleshooting

-   Permission Denied op volumes?\
    De containers (o.a. MinIO, Loki, Tempo) draaien met user: "0:0". In Rootless Podman wordt dit gemapt naar jouw eigen user ID (1000). Dit is noodzakelijk voor schrijfrechten.\
    Fix: Voer podman unshare chown -R 1000:1000 . uit in de map als rechten corrupt zijn geraakt.

-   Geen logs in Loki?\
    Check of Alloy draait en of de journald mounts correct zijn. Alloy vereist security_opt: label=disable om /var/log/journal van de host te kunnen lezen.

-   MinIO start niet?\
    Als je wisselt tussen rootful/rootless kan het volume gelocked zijn. Verwijder het volume met podman volume rm monitoring_minio-data en herstart.

