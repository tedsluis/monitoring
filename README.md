# Full Stack monitoring met Prometheus, Loki, Tempo en Grafana
## Fedora Workstation & Podman Rootless

Deze repository bevat een complete observability stack, geoptimaliseerd voor Fedora Workstation met rootless Podman. De stack combineert metrics, logs en traces in één geïntegreerde omgeving met Grafana als frontend.

## Features

-   Metrics: Prometheus (v3.9) met Node Exporter & Podman Exporter.
-   Logs: Grafana Loki (v3.3) met opslag op MinIO (S3).
-   Traces: Grafana Tempo (v2.10) in combinatie met OpenTelemetry.
-   Grafana: (v12.3) als frontend voor metrics, logging en tracing. 
-   Grafana Dashboards en Datasources worden automatisch geladen (IaC).
-   Collection: Alloy en Opentelemetry collector voor het verzamelen van container en journald logs.
-   Storage: MinIO (S3 compatible) voor langdurige, efficiënte opslag van logs en traces.
-   Alerting: Prometheus Alertmanager gekoppeld aan Karma (alert dashboard) en Blackbox Exporter (health checks).
-   Karma: Dashboard voor alerts.
-   Reverse proxy met TSL encryptie: Treafik proxy met self signed certificaat.
-   Static webpage: NGINX.
-   Security: Volledig compatible met SELinux en draait Rootless (met specifieke fixes voor socket-toegang).
-   webhook-tester: ontvangt alerts van alertmanager voor inspectie.

## Architectuur

De stack bestaat uit de volgende services:

| Service           | Poort | Beschrijving                                     | 
|-------------------|-------|--------------------------------------------------|
| Alertmanager      |  9093 | Verwerkt en routeert alerts.                     |
| Alloy             | 12345 | Collector voor logs (journald en podman logs).   |
| Blackbox          |  9115 | Uitvoeren van HTTP/TCP health probes.            |
| Grafana           |  3000 | Dashboards en visualisatie.                      |
| Karma             |  8080 | UI Dashboard voor Alertmanager meldingen.        |
| Loki              |  3100 | Log aggregatie (via MinIO S3).                   |
| MinIO             |  9000 | S3 Object Storage API.                           |
| MinIO Console     |  9001 | Webinterface voor storage beheer.                |
| NGINX             |    80 | Startpagina.                                     |
| Node-exporter     |  9100 | Host metrics collector.                          |
| OpenTelemetry     |  8888 | Open Telemetry Collector.                        |
| podman-exporter   |  9882 | podman metrics collector.                        |
| Prometheus        |  9090 | Time-series database voor metrics.               |
| Tempo             |  3200 | Distributed Tracing backend (via MinIO S3).      |
| Traefik           |   443 | Reverse proxy.                                   |
| webhook-tester    |  5001 | Webhooks inspectie.                              |

Diagram
![diagram](./images/diagram.png)

## Prerequisites

-   OS: Fedora Linux (getest op Fedora 43+).
-   Tools: podman en podman-compose.
-   Podman Socket: De user-socket moet actief zijn voor de Podman Exporter en Alloy.

```bash
# Installeer benodigdheden\
sudo dnf install podman podman-compose -y

# Activeer de Podman socket voor je gebruiker (Rootless)\
systemctl --user enable --now podman.socket

# Check of de socket werkt
ls -l /run/user/$(id -u)/podman/podman.sock

# Maak het gebruik van port 80 mogelijk
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80
net.ipv4.ip_unprivileged_port_start = 80
echo "net.ipv4.ip_unprivileged_port_start=80" | sudo tee /etc/sysctl.d/99-rootless-ports.conf
net.ipv4.ip_unprivileged_port_start=80
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

3. Certificaat maken en CA trusten:
```bash
$ ./renew-certs.sh 
=== Start Certificaat Vernieuwing (Versie 3.2) ===
Opruimen oude bestanden...
Genereren SAN configuratie...
Genereren Root CA...
.........+........+.+...+...+...+...........+.+++++++++++++++++++++++++++++++++++++++*................+.....+.+.....+...+....+...+.....+++++++++++++++++++++++++++++++++++++++*.....+.....+...+.............+.....++++++
.........+++++++++++++++++++++++++++++++++++++++*....+...+..+++++++++++++++++++++++++++++++++++++++*..+..................+..+...+.........+...+...+...+.......+........+......+....+.........+.....+.............+........+.+......+.........+..............+.+.....+................+...+.....+....+..+...++++++
-----
Genereren Server Certificaat...
Certificate request self-signature ok
subject=C=NL, ST=Utrecht, L=Utrecht, O=Bachstraat, OU=Home, CN=*.localhost
Permissies corrigeren (chmod 644)...
Bijwerken Fedora Trust Store...
Controleren of System Bundle het certificaat vertrouwt...
✓ SUCCES: Systeem bundel vertrouwt nu je certificaat!
Traefik herstarten...
traefik
traefik
f440114ea928262e964b7dddeded7e2dbbcc3f5cb2047c5c5f71033a51d3a2d3
traefik
=== Klaar! ===
Test nu met: curl -v https://grafana.localhost
```
    
4.  Controleer de status:
```bash
$ podman ps -a
CONTAINER ID  IMAGE                                                   COMMAND               CREATED            STATUS                        PORTS                                                             NAMES
411ab6d1f4f7  docker.io/minio/minio:latest                            server /data --co...  About an hour ago  Up About an hour (healthy)    9000/tcp                                                          minio
59245bcf1e80  quay.io/prometheus/node-exporter:v1.10.0                --path.rootfs=/ho...  About an hour ago  Up About an hour              9100/tcp                                                          node-exporter
2cc393300009  quay.io/navidys/prometheus-podman-exporter:latest                             About an hour ago  Up About an hour              9882/tcp                                                          podman-exporter
475d18b9a8be  quay.io/prometheus/prometheus:v3.9.0                    --config.file=/et...  About an hour ago  Up About an hour              9090/tcp                                                          prometheus
12261d191511  quay.io/prometheus/alertmanager:v0.28.0                 --config.file=/et...  About an hour ago  Up About an hour              9093/tcp                                                          alertmanager
1e64f1268d9f  docker.io/grafana/alloy:latest                          run --server.http...  About an hour ago  Up About an hour                                                                                alloy
390b37cb9743  quay.io/prometheus/blackbox-exporter:latest             --config.file=/co...  About an hour ago  Up About an hour              9115/tcp                                                          blackbox-exporter
497bbec4217b  docker.io/tarampampam/webhook-tester:latest             start                 About an hour ago  Up About an hour                                                                                webhook-tester
80f9359c878a  docker.io/library/nginx:alpine                          nginx -g daemon o...  About an hour ago  Up About an hour              80/tcp                                                            nginx
e5f5b6b8b678  docker.io/keinstien/atlas:latest                        /config/scripts/a...  About an hour ago  Up About an hour              8888-8889/tcp                                                     atlas
f6b48cc5b314  docker.io/minio/mc:latest                                                     About an hour ago  Exited (0) About an hour ago                                                                    minio-init
261032e096aa  ghcr.io/prymitive/karma:latest                                                About an hour ago  Up About an hour              8080/tcp                                                          karma
5912702e7961  docker.io/grafana/loki:3.3.2                            -config.file=/etc...  About an hour ago  Up About an hour              3100/tcp                                                          loki
5715a625d745  docker.io/grafana/tempo:2.10.1                          -config.file=/etc...  About an hour ago  Up About an hour                                                                                tempo
3897dfef2e21  docker.io/otel/opentelemetry-collector-contrib:0.119.0  --config=/etc/ote...  About an hour ago  Up About an hour              4317-4318/tcp, 55678-55679/tcp                                    otel-collector
5993dbcb16b1  docker.io/grafana/grafana:12.3.0                                              About an hour ago  Up About an hour              3000/tcp                                                          grafana
f440114ea928  docker.io/library/traefik:v3.6.8                        traefik               26 minutes ago     Up 26 minutes                 0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:4317->4317/tcp  traefik
```
note: De minio-init container draait alleen bij het starten van minio.

## Stoppen, starten of herstart

```bash
# alle containers stoppen
podman-compose down

# alle containers starten
podman-compose up -d

# alle containers herstarten
podman-compose down && podman-compose up -d

# een specifieke container herstarten en de wijzigingen van compose.yaml meenemen
podman-compose up -d --force-recreate webhook-tester

# een specifieke container herstarten zonder wijziging van compose.yaml mee te nemen
podman restart webhook-tester
```

## Configuratie

De configuratie is opgedeeld in mappen per component. Dankzij Grafana Provisioning worden datasources automatisch ingeladen.

### Mappenstructuur

-   `alertmanager/`: Routing van notificaties.
-   `alloy/`: Pipeline configuratie voor het lezen van journald en de podman.socket.
-   `blackbox/`: Definities voor HTTP health checks.
-   `grafana-provisioning/`: Koppelt Prometheus, Loki en Tempo automatisch aan Grafana.
-   `grafana-provisioning/dashboards/json`: grafana dashboarden.
-   `grafana-provisioning/datasources`: automatisch datasource configiratie.
-   `landing-page/`: index.html en nginx config.
-   `loki/`: Configuratie voor Loki (S3 backend) en recording rules.
-   `otel`: opentelemetry configuratie.
-   `prometheus/`: prometheus.yml en alert.rules.yml.
-   `tempo/`: Configuratie voor Tempo (S3 backend).
-   `traefik/`: traefik.yaml
-   `traefik/certs`: certificaten.
-   `traefik/dynamic`: dynamische traefik configuratie.

### Inloggegevens (Defaults)

| Service | Gebruikersnaam | Wachtwoord | Opmerking                             |
|---------|----------------|------------|---------------------------------------|
| Grafana | admin          | admin      | Deze kun je wijzigen na eerste login! |
| MinIO   | minio          | minio123   | Wijzige kan in compose.yml            |

## Gebruik

### 1. NGINX start pagina

Ga naar https://localhost


![startpagina1](./images/startpagina1.png)


![startpagina2](./images/startpagina2.png)


![startpagina3](./images/startpagina3.png)


![startpagina4](./images/startpagina4.png)

### 2. Dashboards (Grafana)

Ga naar https://grafana.localhost

Grafana vormt het centrale, visuele hart van deze stack en fungeert als 'single pane of glass' voor alle data. Het open-source platform verbindt met Prometheus (metrics), Loki (logs) en Tempo (traces), waardoor via dashboards en de Explore-modus diepgaand inzicht van het systeem onstaat. Dankzij de geautomatiseerde provisioning worden de datasources en dashboards direct bij het opstarten ingeladen, zodat alles werkt zonder handmatige configuratie.

#### Dashboards

Deze repo bevat een aantal grafana dashboarden die opgeslagen zijn in [./grafana-provisioning/dashboards/json/](./grafana-provisioning/dashboards/json/) in json formaat.

Grafana Dashboards
![grafana-dashboarden](./images/grafana-dashboards.png)

#### Explore

De Explore-modus biedt een geavanceerde interface voor ad-hoc analyse en troubleshooting, waarbij gebruikers direct query's kunnen uitvoeren. Hiermee faciliteert Explore snelle incidentdiagnose en root-cause analyse, zonder de noodzaak om vooraf gedefinieerde dashboards te configureren.

**Loki logs explore**

 De Loki-datasource in combinatie met LogQ maakt het mogelijk om logstromen efficiënt te filteren op labels, specifieke tekstpatronen of reguliere expressies te doorzoeken en logvolumes visueel weer te geven naast de ruwe logregels. 
![Loki-explore](/images/explore-logs.png)

**Prometheus metrics explore**

De Prometheus-datasource biedt in combinatie met PromQL-queries de mogelijk om het iteratief onderzoeken van time-series data, het visualiseren van trends en het vergelijken van metrieken via split-view functionaliteit.
![prometheus-explore](/images/explore-metrics.png)

**Tempo tracing explore**

De Tempo-datasource in combinatie TraceQL biedt een gedetailleerde visualisatie van de levenscyclus van requests door de gedistribueerde architectuur. Via de waterfall-weergave kunnen gebruikers de latency per component analyseren, waardoor performance-bottlenecks en fouten binnen specifieke spans nauwkeurig kunnen worden geïsoleerd. De integratie met TraceQL maakt gerichte filtering van traces mogelijk, wat in combinatie met gecorreleerde logs en metrics zorgt voor een efficiënte analyse van de hoofdoorzaak bij incidenten. Het kan bijvoorbeeld interesant zijn om te filteren op request niet een http status code van 4xx of 5xx hebben. Of request die langer duren dan 500ms.
![tempo-explore](/images/explore-traces.png)

Explore trace - service graph
![traces-explore](/images/explore-traces-service-graph.png)

#### Drilldown

De drill-down functionaliteit binnen Grafana biedt de mogelijkheid om diepgaande foutanalyse door metrics, logs en traces contextueel met elkaar te verbinden. Vanuit een anomalie in een metrics-dashboard kan je direct navigeren naar de gecorreleerde logregels in Loki, om vervolgens via automatisch gedetecteerde trace-ID's door te schakelen naar gedetailleerde request-spans in Tempo. Deze integratie elimineert de noodzaak om handmatig tijdstippen en identifiers te synchroniseren tussen verschillende datasources, wat de efficiëntie van root cause analysis en performance-optimalisatie aanzienlijk verhoogt.

Metrics drilldown
![Metrics-drilldown](/images/drilldown-metrics-dashboard.png)

Logs drilldown
![loki-drilldown](/images/drill-down-logs-dashboard.png)

Traces drilldown
![traces-drilldown](/images/drilldown-breakdown.png)

#### Grafana alerts

Grafana Alerting biedt een centrale interface voor het monitoren van alerts. Deze module aggregeert alert rules vanuit zowel Prometheus (voor metrics) als Loki (voor logdata), waardoor een overzicht ontstaat van de operationele status. Je kunt via dit dashboard de realtime status van alerts (‘Pending’ of ‘Firing’) analyseren, de onderliggende query-definities bekijken en inzicht verkrijgen in de evaluatiecriteria die de stabiliteit en beschikbaarheid van het platform bewaken.

Grafana Alerting
![grafana-alerting](/images/grafana-alerts.png)

#### Grafana datasources

Datasources vormen binnen Grafana de technische interface naar de onderliggende data-opslagsystemen, waardoor de applicatie in staat is gegevens op te halen zonder deze zelf te persisteren. In deze configuratie zijn Prometheus, Loki en Tempo gedefinieerd als primaire bronnen voor het ontsluiten van respectievelijk metrics, logbestanden en distributed traces. 
![grafana-datasources](./images/grafana-datasource.png)

De datasources voor Prometheus, Loki en Tempo zijn geconfigureerd in [./grafana-provisioning/dashboards/dashboard.yaml](./grafana-provisioning/datasources/datasources.yaml)


### 3. Prometheus Metrics

Ga naar https://prometheus.localhost

- `/query`:  metrics querier.
- `/alerts`: alert rule overzicht
- `/targets`: status van de scrape targets.
- `/config`: volledige prometheus configuratie.

Prometheus UI - alert rules overzich
![prometheus](images/prometheus.png)

Prometheus dashboard
![prometheus-dashboard](./images/prometheus-dashboard.png)

### 4. Alertmanager

Ga naar https://alertmanager.localhost

Alertmanager UI
![alertmanager](/images/alertmanager.png)

Alertmanager dashboard
![alertmanager-dashboard](./images/alertmanager-metrics-dashboard.png)

- Overzicht van actuele alerts
- Mogelijkheid om alerts te dempen.

### 5. Karma Alert Dashboard

Ga naar https://karma.localhost

Hier zie je een overzicht van alle actieve waarschuwingen (bijv. "Disk bijna vol", "Container down" of "Health Check Failed").

Karma UI
![karma](images/karma.png)

### 6. Storage (MinIO)

Ga naar https://minio.localhost

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

Hier kun je zien hoeveel data Loki en Tempo verbruiken in hun buckets.

### 7. webhook-tester

Ga naar https://webhook-tester.localhost

Alertmanager stuurt de alerts door naar de webhook-tester

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

Ga naar: https://traefik.localhost

Treafik
![traefik](/images/traefik.png)

Treafik dashboard
![traefik](/images/traefik.dashboard.png)

## Alles verwijderen

```bash
# alle containers stoppen
$ podman-compose down

# toon volumes
$ podman volume ls | grep monitoring
local       monitoring_prometheus-data
local       monitoring_loki-wal
local       monitoring_tempo-wal
local       monitoring_minio-data
local       monitoring_grafana-data

# verwijder volumes
$ podman volume rm monitoring_prometheus-data monitoring_loki-wal monitoring_tempo-wal monitoring_minio-data monitoring_grafana-data

# verwijder certificaten
$ rm /etc/pki/ca-trust/source/anchors/my-local-ca.pem
$ rm /etc/pki/ca-trust/source/anchors/my-local-ca.crt
$ sudo update-ca-trust extract

# disable podman socket
$ systemctl --user disable --now podman.socket

# verwijder rootless ports
sudo rm /etc/sysctl.d/99-rootless-ports.conf

# verwijder monitoring repo
$ rm -rf REPONAAM
```