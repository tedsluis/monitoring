#!/bin/bash
# install.sh - Full setup of the monitoring stack including dynamic domain configuration

set -e

# 1. Define the domain (default: localhost)
export DOMAIN="${DOMAIN:-localhost}"
echo "======================================================"
echo "🚀 Starting installation for domain: ${DOMAIN}"
echo "======================================================"

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
mkdir -p traefik/dynamic traefik/certs landing-page

# 4. Save the DOMAIN to an .env file for podman-compose
echo "======================================================"
echo "📝 Saving domain to .env file for podman-compose..."
echo "DOMAIN=${DOMAIN}" > .env
echo "======================================================"
echo ""

# 5. Generate configuration from templates (only for static files that don't support env vars natively)
echo "======================================================"
echo "📝 Generating static configuration files from templates..."
# Note: single quotes around '${DOMAIN}' prevent replacing other $ variables in the files
envsubst '${DOMAIN}' < template/traefik.yaml > traefik/traefik.yaml
envsubst '${DOMAIN}' < template/traefik-dynamic.yaml > traefik/dynamic/traefik-dynamic.yaml
envsubst '${DOMAIN}' < template/index.html > landing-page/index.html
echo "======================================================"
echo ""

# 6. Make scripts executable
chmod +x renew-certs.sh prepare_no_proxy.sh run-tests.sh

# 7. Update /etc/hosts
if [ "$DOMAIN" != "localhost" ]; then
    echo "======================================================"
    echo "🌐 Updating /etc/hosts..."
    # List of all subdomains we use
    SUBDOMAINS="grafana prometheus loki tempo minio s3 alloy otel-collector alertmanager karma keep keep-api node-exporter podman-exporter blackbox traefik traefik-metrics webhook-tester"
    
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

# 8. Renew certificates
echo "======================================================"
echo "🔐 Generating TLS certificates..."
./renew-certs.sh
echo "======================================================"
echo ""

# 9. Configure proxy settings
echo "======================================================"
echo "🔀 Configuring proxy settings..."
source ./prepare_no_proxy.sh
echo "======================================================"
echo ""

echo "======================================================"
echo "✅ Installation preparation complete!"
echo "You can now start the stack with: podman-compose up -d"
echo "It will be accessible at: https://${DOMAIN}"
echo "======================================================"