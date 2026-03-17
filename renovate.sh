#!/bin/bash

# Zorg ervoor dat het script stopt bij fouten
set -e

# Controleer of de GitHub Token beschikbaar is
if [ -z "$GITHUB_COM_TOKEN" ]; then
    echo "Fout: GITHUB_COM_TOKEN is niet ingesteld."
    echo "Gebruik: export GITHUB_COM_TOKEN=jouw_token && ./run-renovate.sh"
    exit 1
fi

echo "🚀 Start Mend Renovate via Podman..."

# Draai de Renovate image lokaal. 
# De :Z vlag bij het volume is cruciaal voor Fedora/SELinux!
podman run --rm \
    -e GITHUB_COM_TOKEN="${GITHUB_COM_TOKEN}" \
    -e LOG_LEVEL="info" \
    -v "$(pwd)/renovate-config.js:/usr/src/app/config.js:Z" \
    ghcr.io/renovatebot/renovate:latest

echo "✅ Renovate run is voltooid. Check je GitHub repository voor mogelijke Pull Requests!"