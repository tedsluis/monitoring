#!/bin/bash
# install.sh - Full setup of the monitoring stack including dynamic domain configuration

set -e


echo "======================================================"
echo "🚀 Starting installation"
echo "======================================================"

# 1. Controleer of de .env file bestaat
if [ ! -f .env ]; then
    echo "⚠️ .env file not found."
    if [ -f .env.example ]; then
        echo "Copying .env.example to .env"
        cp .env.example .env
        echo "🛑 ACTION REQUIRED: Please fill in your passwords, domain, and API keys in the .env file."
        echo "Run this script (./install.sh) again after you have done so."
    else
        echo "❌ Error: .env.example does not exist. Please ensure it is in the repository."
    fi
    exit 1
fi

# Load environment variables from the .env file
export $(grep -v '^#' .env | xargs)
echo "✅ environment variables loaded from .env"
echo ""

# Fallback DOMAIN to localhost if not set in .env
export DOMAIN="${DOMAIN:-localhost}"
echo "✅ Installation is running for domain: ${DOMAIN}"
echo ""

# 2. Check and install prerequisites
echo "📦 Checking prerequisites..."
if ! command -v envsubst &> /dev/null; then
    echo "======================================================"
    echo "Installing gettext (for envsubst)..."
    echo "======================================================"
    sudo dnf install -y gettext
fi

if ! command -v podman &> /dev/null || ! command -v podman-compose &> /dev/null; then
    echo "======================================================"
    echo "Installing podman and podman-compose..."
    sudo dnf install -y podman podman-compose
    echo "======================================================"
    echo ""
fi

# Enable podman socket if not enabled
if [ ! -S "/run/user/$(id -u)/podman/podman.sock" ]; then
    echo "======================================================"
    echo "Activating rootless podman socket..."
    systemctl --user enable --now podman.socket
    echo "======================================================"
    echo ""
fi

# 3. Create necessary directories
mkdir -p traefik/dynamic traefik/certs landing-page alertmanager loki tempo pyroscope
 
# 4. Generate configuration from templates 
echo "======================================================" 
echo "📝 Generating configuration from templates..." 
# Define wich environment variables we want to inj ect into the configuration files
VARS='${DOMAIN} ${KEEP_API_KEY} ${WEBHOOK_TESTER_UUID} ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}'

envsubst "$VARS" < template/traefik.yaml > traefik/traefik.yaml
envsubst "$VARS" < template/traefik-dynamic.yaml > traefik/dynamic/traefik-dynamic.yaml
envsubst "$VARS" < template/index.html > landing-page/index.html
envsubst "$VARS" < template/alertmanager.yml > alertmanager/alertmanager.yml
envsubst "$VARS" < template/loki-config.yaml > loki/loki-config.yaml
envsubst "$VARS" < template/tempo.yaml > tempo/tempo.yaml
envsubst "$VARS" < template/pyroscope.yaml > pyroscope/pyroscope.yaml

echo "copy template/traefik.yaml > traefik/traefik.yaml"
echo "copy template/traefik-dynamic.yaml > traefik/dynamic/traefik-dynamic.yaml"
echo "copy template/index.html > landing-page/index.html"
echo "copy template/alertmanager.yml > alertmanager/alertmanager.yml"
echo "copy template/loki-config.yaml > loki/loki-config.yaml"
echo "copy template/tempo.yaml > tempo/tempo.yaml"
echo "copy template/pyroscope.yaml > pyroscope/pyroscope.yaml"

echo "✅ Templates successfully processed."
echo "======================================================"
echo ""

# 5. Make scripts executable
chmod +x renew-certs.sh prepare_no_proxy.sh run-tests.sh

# 6. Update /etc/hosts
if [ "$DOMAIN" != "localhost" ]; then
    echo "======================================================"
    echo "🌐 Updating /etc/hosts..."
    # List of all subdomains we use
    SUBDOMAINS="grafana prometheus loki tempo minio s3 alloy otel-collector alertmanager karma keep keep-api node-exporter podman-exporter blackbox traefik traefik-metrics pyroscope webhook-tester"
    
    HOSTS_ENTRY="127.0.0.1 ${DOMAIN}"
    for SUB in $SUBDOMAINS; do
        HOSTS_ENTRY="${HOSTS_ENTRY} ${SUB}.${DOMAIN}"
    done

    # Remove old entry if it exists (based on comment tag) and add new one
    sudo sed -i '/# MONITORING-STACK-DOMAINS/d' /etc/hosts
    echo "${HOSTS_ENTRY} # MONITORING-STACK-DOMAINS" | sudo tee -a /etc/hosts > /dev/null
    echo "✅ /etc/hosts updated."
    echo "======================================================"
    echo ""
fi

# 7. Renew certificates
echo "======================================================"
echo "🔐 Generating TLS certificates..."
./renew-certs.sh
echo "======================================================"
echo ""

# 8. Configure proxy settings
echo "======================================================"
echo "🔀 Configuring proxy settings..."
source ./prepare_no_proxy.sh
echo "======================================================"
echo ""

echo "======================================================"
echo "✅ Installation preparation complete!"
echo "You can now start the stack with: podman compose up -d"
echo "It will be accessible at: https://${DOMAIN}"
echo "======================================================"
