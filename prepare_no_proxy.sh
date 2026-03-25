# 1. Defines standard hostnames, catch all IPs (like 0.0.0.0) 
BASE_NO_PROXY="localhost,127.0.0.1,127.0.1.1,0.0.0.0,::1,::,${no_proxy}"

# 2. creates services from compose file
COMPOSE_SERVICES=$(grep -E '^  [a-zA-Z0-9_-]+:$' compose.yml | tr -d ' :\r' | paste -sd "," -)

# 3. creates services with sub domain
COMPOSE_SERVICES_DOTS=$(echo "$COMPOSE_SERVICES" | sed 's/,/,./g' | sed 's/^/./')

# 4. add CIDR to catch 10.x.x.x IPs 
CIDR_BLOCKS="10.0.0.0/8"

# 5. creates no_proxy and NO_PROXY variables
export no_proxy="${BASE_NO_PROXY},${COMPOSE_SERVICES},${COMPOSE_SERVICES_DOTS},.dns.podman,${CIDR_BLOCKS}"
export NO_PROXY=$no_proxy

echo "✅ no_proxy is set to:"
echo $no_proxy
