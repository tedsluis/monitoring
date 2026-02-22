#!/bin/bash

# ==============================================================================
# Script: renew-certs.sh (Versie 3.2 - Permission Fix)
# Doel:   Regenereert certificaten, fixt rechten voor containers en update Trust Store.
# ==============================================================================

set -e

# Configuratie
BASE_DIR="/home/tedsluis/monitoring/traefik/certs"
CA_KEY="myCA.key"
CA_CERT="myCA.pem"
CA_CONF="ca.conf"
SERVER_KEY="localhost.key"
SERVER_CSR="localhost.csr"
SERVER_CERT="localhost.crt"
EXT_FILE="localhost.ext"

# Fedora paden
SYS_ANCHOR="/etc/pki/ca-trust/source/anchors/my-local-ca.pem"
SYS_BUNDLE="/etc/pki/tls/certs/ca-bundle.crt" 

# Kleurtjes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Start Certificaat Vernieuwing (Versie 3.2) ===${NC}"

# Zorg dat de map bestaat
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# 1. Schoonmaak
echo "Opruimen oude bestanden..."
rm -f "$CA_KEY" "$CA_CERT" "myCA.srl" "$SERVER_KEY" "$SERVER_CSR" "$SERVER_CERT" "$CA_CONF" "$EXT_FILE"

# 2. Maak localhost.ext (SAN configuratie)
echo "Genereren SAN configuratie..."
cat > "$EXT_FILE" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
DNS.3 = alertmanager.localhost
DNS.4 = alloy.localhost
DNS.5 = atlas.localhost
DNS.6 = blackbox.localhost
DNS.7 = grafana.localhost
DNS.8 = minio.localhost
DNS.9 = loki.localhost
DNS.10 = karma.localhost
DNS.11 = node-exporter.localhost
DNS.12 = otel-collector.localhost
DNS.13 = podman-exporter.localhost
DNS.14 = prometheus.localhost
DNS.15 = s3.localhost
DNS.16 = tempo.localhost
DNS.17 = traefik.localhost
DNS.18 = traefik-metrics.localhost
DNS.19 = webhook-tester.localhost
IP.1 = 127.0.0.1
EOF

# 3. CA Config (Cruciaal: CA:TRUE)
cat > "$CA_CONF" << EOF
[ req ]
prompt = no
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[ req_distinguished_name ]
C = NL
ST = Utrecht
L = Utrecht
O = Bachstraat
OU = Home
CN = Fedora Localhost Root CA

[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

# 4. Genereer CA
echo "Genereren Root CA..."
openssl req -x509 -new -nodes -keyout "$CA_KEY" -sha256 -days 3650 -out "$CA_CERT" -config "$CA_CONF" -extensions v3_ca

# Check validiteit
if ! openssl x509 -in "$CA_CERT" -text -noout | grep -q "CA:TRUE"; then
    echo -e "${RED}✗ FOUT: CA is niet gemarkeerd als CA!${NC}"
    exit 1
fi

# 5. Genereer Server Cert
echo "Genereren Server Certificaat..."
openssl genrsa -out "$SERVER_KEY" 2048
openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -subj "/C=NL/ST=Utrecht/L=Utrecht/O=Bachstraat/OU=Home/CN=*.localhost"
openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
-out "$SERVER_CERT" -days 3650 -sha256 -extfile "$EXT_FILE"

# 6. FIX: Bestandsrechten
# Dit is cruciaal: Traefik (non-root in container) moet deze files kunnen lezen!
echo -e "${YELLOW}Permissies corrigeren (chmod 644)...${NC}"
chmod 644 "$SERVER_KEY" "$SERVER_CERT" "$CA_CERT"

# 7. Trust Store Update
echo "Bijwerken Fedora Trust Store..."

# Verwijder oude ankers
sudo rm -f "/etc/pki/ca-trust/source/anchors/my-local-ca.crt"
sudo rm -f "$SYS_ANCHOR"

# Kopieer nieuwe, maar CLEAN PEM (alleen het certificaat, geen text header)
openssl x509 -in "$CA_CERT" -out "$CA_CERT.clean"
sudo cp "$CA_CERT.clean" "$SYS_ANCHOR"
rm "$CA_CERT.clean"

sudo chmod 644 "$SYS_ANCHOR"
sudo chown root:root "$SYS_ANCHOR"

# Forceer update
sudo update-ca-trust extract

# 8. Verificatie tegen System Bundle
echo "Controleren of System Bundle het certificaat vertrouwt..."

if openssl verify -CAfile "$SYS_BUNDLE" "$SERVER_CERT" | grep -q "OK"; then
    echo -e "${GREEN}✓ SUCCES: Systeem bundel vertrouwt nu je certificaat!${NC}"
else
    echo -e "${RED}⚠️  WAARSCHUWING: Systeem bundel validatie faalde.${NC}"
    echo -e "Probeer fallback methode: Direct appenden aan user-trust..."
    echo "" | sudo tee -a "$SYS_BUNDLE" > /dev/null
    openssl x509 -in "$CA_CERT" | sudo tee -a "$SYS_BUNDLE" > /dev/null
    
    if openssl verify -CAfile "$SYS_BUNDLE" "$SERVER_CERT" | grep -q "OK"; then
         echo -e "${GREEN}✓ SUCCES: CA handmatig toegevoegd en gevalideerd.${NC}"
    else
         echo -e "${RED}✗ FOUT: Zelfs handmatig toevoegen faalde.${NC}"
         exit 1
    fi
fi

# 9. Herstart Traefik
# We gebruiken force-recreate om zeker te zijn dat de nieuwe bestanden worden opgepikt
echo "Traefik herstarten..."
if command -v podman-compose &> /dev/null; then
    # Als podman-compose beschikbaar is, gebruik dat voor nettere recreate
    cd /home/tedsluis/monitoring
    podman-compose up -d --force-recreate traefik
else
    # Fallback naar gewone podman restart
    podman restart traefik
fi

echo -e "${GREEN}=== Klaar! ===${NC}"
echo "Test nu met: curl -v https://grafana.localhost"