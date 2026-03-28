#!/bin/bash

# prepare_no_proxy.sh - Dynamically generates a comprehensive no_proxy variable based on the compose.yml services and common local addresses.

# 1. Ensure http_proxy and https_proxy are set, otherwise no_proxy is irrelevant
if [ -z "$http_proxy" ] && [ -z "$https_proxy" ] && [ -z "$HTTP_PROXY" ] && [ -z "$HTTPS_PROXY" ]; then
    echo "Are you sure you are using a http proxy?"
    echo "Neither http_proxy, https_proxy, HTTP_PROXY nor HTTPS_PROXY is set. The no_proxy variable will not have any effect."
    echo "Please set http_proxy, https_proxy, HTTP_PROXY and HTTPS_PROXY environment variables if you intend to use a proxy."
    exit 0
fi

# 2. Define standard hostnames, catch all IPs (like 0.0.0.0) 
BASE_NO_PROXY="localhost,127.0.0.1,127.0.1.1,0.0.0.0,::1,::,${no_proxy}"

# 3. Extract services from compose file
COMPOSE_SERVICES=$(grep -E '^  [a-zA-Z0-9_-]+:$' compose.yml | tr -d ' :\r' | paste -sd "," -)

# 4. Create services with sub domain (dot prefix)
# Check if COMPOSE_SERVICES is not empty to avoid adding just a dot
if [ -n "$COMPOSE_SERVICES" ]; then
    COMPOSE_SERVICES_DOTS=$(echo "$COMPOSE_SERVICES" | sed 's/,/,./g' | sed 's/^/./')
else
    COMPOSE_SERVICES_DOTS=""
fi

# 5. Add CIDR to catch 10.x.x.x IPs 
CIDR_BLOCKS="10.0.0.0/8"

# 6. Combine everything into a raw string
RAW_NO_PROXY="${BASE_NO_PROXY},${COMPOSE_SERVICES},${COMPOSE_SERVICES_DOTS},.dns.podman,${CIDR_BLOCKS}"

# 7. Filter duplicates:
# - tr ',' '\n'      : replaces commas with newlines
# - awk 'NF'         : removes empty lines (in case of double commas)
# - sort -u          : sorts alphabetically and removes duplicate entries
# - paste -sd "," -  : joins the lines back together with commas
UNIQUE_NO_PROXY=$(echo "$RAW_NO_PROXY" | tr ',' '\n' | awk 'NF' | sort -u | paste -sd "," -)

# 8. Export the cleaned no_proxy and NO_PROXY variables
export no_proxy="$UNIQUE_NO_PROXY"
export NO_PROXY="$no_proxy"

echo "✅ no_proxy is set to:"
echo "$no_proxy"
