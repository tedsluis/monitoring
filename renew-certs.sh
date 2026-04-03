#!/bin/bash

# ==============================================================================
# Script: renew-certs.sh
# Purpose: Regenerates certificates, fixes permissions for containers and updates Trust Store.
# ==============================================================================

set -e

# Configuration
# Resolve repository root relative to this script so the script works
# regardless of where the repository is cloned.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && pwd)"
BASE_DIR="${REPO_ROOT}/traefik/certs"
CA_KEY="myCA.key"
CA_CERT="myCA.pem"
CA_CONF="ca.conf"
SERVER_KEY="localhost.key"
SERVER_CSR="localhost.csr"
SERVER_CERT="localhost.crt"
EXT_FILE="localhost.ext"

# Fedora paths
SYS_ANCHOR="/etc/pki/ca-trust/source/anchors/my-local-ca.pem"
SYS_BUNDLE="/etc/pki/tls/certs/ca-bundle.crt" 

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Start Certificate Renewal (Version 3.2) ===${NC}"

# Ensure the directory exists
mkdir -p "$BASE_DIR"
chmod 755 "$BASE_DIR"
cd "$BASE_DIR"

# 1. Cleanup
echo "Cleaning up old files..."
rm -f "$CA_KEY" "$CA_CERT" "myCA.srl" "$SERVER_KEY" "$SERVER_CSR" "$SERVER_CERT" "$CA_CONF" "$EXT_FILE"

# 2. Create localhost.ext (SAN configuration)
echo "Generating SAN configuration..."
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
DNS.5 = blackbox.localhost
DNS.6 = grafana.localhost
DNS.7 = minio.localhost
DNS.8 = loki.localhost
DNS.9 = karma.localhost
DNS.10 = keep.localhost
DNS.11 = keep-api.localhost
DNS.12 = node-exporter.localhost
DNS.13 = otel-collector.localhost
DNS.14 = podman-exporter.localhost
DNS.15 = prometheus.localhost
DNS.16 = s3.localhost
DNS.17 = tempo.localhost
DNS.18 = traefik.localhost
DNS.19 = traefik-metrics.localhost
DNS.20 = webhook-tester.localhost
IP.1 = 127.0.0.1
EOF

# 3. CA Config (Critical: CA:TRUE)
cat > "$CA_CONF" << EOF
[ req ]
prompt = no
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[ req_distinguished_name ]
C = NL
ST = Utrecht
L = Utrecht
O = Utrecht
OU = Utrecht
CN = Fedora Localhost Root CA

[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

# 4. Generate CA
echo "Generating Root CA..."
openssl req -x509 -new -nodes -keyout "$CA_KEY" -sha256 -days 3650 -out "$CA_CERT" -config "$CA_CONF" -extensions v3_ca

# Check validity
if ! openssl x509 -in "$CA_CERT" -text -noout | grep -q "CA:TRUE"; then
    echo -e "${RED}✗ ERROR: CA is not marked as CA!${NC}"
    exit 1
fi

# 5. Generate Server Certificate
echo "Generating Server Certificate..."
openssl genrsa -out "$SERVER_KEY" 2048
openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -subj "/C=NL/ST=Utrecht/L=Utrecht/O=Utrecht/OU=Utrecht/CN=*.localhost"
openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
-out "$SERVER_CERT" -days 3650 -sha256 -extfile "$EXT_FILE"

# 6. FIX: File permissions
# This is critical: Traefik (non-root in container) must be able to read these files!
echo -e "${YELLOW}Fixing permissions (chmod 644)...${NC}"
chmod 644 "$SERVER_KEY" "$SERVER_CERT" "$CA_CERT"

# 7. Trust Store Update
echo "Updating Fedora Trust Store..."

# Remove old anchors
sudo rm -f "/etc/pki/ca-trust/source/anchors/my-local-ca.crt"
sudo rm -f "$SYS_ANCHOR"

# Copy new, but CLEAN PEM (certificate only, no text header)
openssl x509 -in "$CA_CERT" -out "$CA_CERT.clean"
sudo cp "$CA_CERT.clean" "$SYS_ANCHOR"
rm "$CA_CERT.clean"

sudo chmod 644 "$SYS_ANCHOR"
sudo chown root:root "$SYS_ANCHOR"

# Force update
sudo update-ca-trust extract

# 8. Verification against System Bundle
echo "Checking if System Bundle trusts the certificate..."

if openssl verify -CAfile "$SYS_BUNDLE" "$SERVER_CERT" | grep -q "OK"; then
    echo -e "${GREEN}✓ SUCCESS: System bundle now trusts your certificate!${NC}"
else
    echo -e "${RED}⚠️  WARNING: System bundle validation failed.${NC}"
    echo -e "Trying fallback method: Directly append to user-trust..."
    echo "" | sudo tee -a "$SYS_BUNDLE" > /dev/null
    openssl x509 -in "$CA_CERT" | sudo tee -a "$SYS_BUNDLE" > /dev/null
    
    if openssl verify -CAfile "$SYS_BUNDLE" "$SERVER_CERT" | grep -q "OK"; then
         echo -e "${GREEN}✓ SUCCESS: CA manually added and validated.${NC}"
    else
         echo -e "${RED}✗ ERROR: Even manual addition failed.${NC}"
         exit 1
    fi
fi

# 9. Restart Traefik
# We use force-recreate to be sure the new files are picked up
echo "Restarting Traefik..."
if command -v podman-compose &> /dev/null; then
    # If podman-compose is available, use it for cleaner recreate
    cd "$REPO_ROOT"
    podman-compose up -d --force-recreate traefik
else
    # Fallback to regular podman restart
    podman restart traefik
fi

echo -e "${GREEN}=== Done! ===${NC}"
echo "Test now with: curl -v https://grafana.localhost"