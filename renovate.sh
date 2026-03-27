#!/bin/bash

# Ensure the script stops on errors
set -e

# Check if the GitHub Token is available
if [ -z "$GITHUB_COM_TOKEN" ]; then
    echo "Error: GITHUB_COM_TOKEN is not set."
    echo "Usage: export GITHUB_COM_TOKEN=your_token && ./run-renovate.sh"
    exit 1
fi

WORKDIR="$(pwd)"
LOG_DIR="$WORKDIR/logs"

echo "🚀 Starting Mend Renovate via Podman..."

# Run the Renovate image locally.
# We pass GITHUB_COM_TOKEN through as RENOVATE_TOKEN, which the image expects.
# The :Z flag on the volume is crucial for Fedora/SELinux!
podman run --rm \
    -e RENOVATE_TOKEN="${GITHUB_COM_TOKEN}" \
    -e GITHUB_COM_TOKEN="${GITHUB_COM_TOKEN}" \
    -e RENOVATE_GIT_AUTHOR="Ted Sluis <ted.sluis@gmail.com>" \
    -e LOG_LEVEL="info" \
    -e NODE_OPTIONS="--dns-result-order=ipv4first" \
    -v "${WORKDIR}/renovate-config.js:/usr/src/app/config.js:Z" \
    ghcr.io/renovatebot/renovate:latest 2>&1 | tee "${LOG_DIR}/renovate-$(date +%Y%m%d-%H%M%S).log"

echo "✅ Renovate run is complete. Check your GitHub repository for possible Pull Requests!"