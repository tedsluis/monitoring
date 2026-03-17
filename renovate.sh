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
# We geven GITHUB_COM_TOKEN door als RENOVATE_TOKEN, wat de image verwacht.
# De :Z vlag bij het volume is cruciaal voor Fedora/SELinux!
podman run --rm \
    -e RENOVATE_TOKEN="${GITHUB_COM_TOKEN}" \
    -e GITHUB_COM_TOKEN="${GITHUB_COM_TOKEN}" \
    -e RENOVATE_GIT_AUTHOR="Ted Sluis ted.sluis@gmail.com" \
    -e LOG_LEVEL="info" \
    -v "$(pwd)/renovate-config.js:/usr/src/app/config.js:Z" \
    ghcr.io/renovatebot/renovate:latest

echo "✅ Renovate run is voltooid. Check je GitHub repository voor mogelijke Pull Requests!"