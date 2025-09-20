#!/bin/bash

# Function to detect if running in Proxmox LXC container
is_proxmox_lxc() {
    # Check for LXC in environment
    if [ -n "$container" ] && [ "$container" = "lxc" ]; then
        return 0  # LXC container
    fi
    
    # Check for LXC in /proc/1/environ
    if grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
        return 0  # LXC container
    fi
    
    return 1  # Not LXC
}

# Default image settings
DEFAULT_REGISTRY="dokploy/dokploy"
GITHUB_REGISTRY="ghcr.io/monikon22/dokploy"

# Parse command line arguments
USE_GITHUB_PACKAGES=false
REGISTRY_URL=""
IMAGE_TAG="latest"
COMMAND="install"

# Parse command first
if [ "$1" = "update" ]; then
    COMMAND="update"
    shift
fi

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --github-packages)
            USE_GITHUB_PACKAGES=true
            shift
            ;;
        --registry)
            REGISTRY_URL="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  (no command)       Install Dokploy"
            echo "  update             Update existing Dokploy installation"
            echo ""
            echo "Options:"
            echo "  --github-packages    Use GitHub Packages instead of Docker Hub"
            echo "  --registry URL       Use custom registry URL"
            echo "  --tag TAG           Specify image tag (default: latest)"
            echo "  --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Install with Docker Hub"
            echo "  $0 --github-packages        # Install with GitHub Packages"
            echo "  $0 --registry myregistry.com/dokploy --tag v1.0.0"
            echo "  $0 update --github-packages # Update using GitHub Packages"
            echo "  $0 update --tag canary      # Update to canary version"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Determine which image to use
if [ -n "$REGISTRY_URL" ]; then
    DOKPLOY_IMAGE="$REGISTRY_URL:$IMAGE_TAG"
elif [ "$USE_GITHUB_PACKAGES" = true ]; then
    DOKPLOY_IMAGE="$GITHUB_REGISTRY:$IMAGE_TAG"
else
    DOKPLOY_IMAGE="$DEFAULT_REGISTRY:$IMAGE_TAG"
fi

echo "Using Dokploy image: $DOKPLOY_IMAGE"

install_dokploy() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" >&2
        exit 1
    fi

    # check if is Mac OS
    if [ "$(uname)" = "Darwin" ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    # check if is running inside a container
    if [ -f /.dockerenv ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    # check if something is running on port 80
    if ss -tulnp | grep ':80 ' >/dev/null; then
        echo "Error: something is already running on port 80" >&2
        exit 1
    fi

    # check if something is running on port 443
    if ss -tulnp | grep ':443 ' >/dev/null; then
        echo "Error: something is already running on port 443" >&2
        exit 1
    fi

    command_exists() {
      command -v "$@" > /dev/null 2>&1
    }

    if command_exists docker; then
      echo "Docker already installed"
    else
      curl -sSL https://get.docker.com | sh
    fi

    # Check if running in Proxmox LXC container and set endpoint mode
    endpoint_mode=""
    if is_proxmox_lxc; then
        echo "⚠️ WARNING: Detected Proxmox LXC container environment!"
        echo "Adding --endpoint-mode dnsrr to Docker service for LXC compatibility."
        echo "This may affect service discovery but is required for LXC containers."
        echo ""
        endpoint_mode="--endpoint-mode dnsrr"
        echo "Waiting for 5 seconds before continuing..."
        sleep 5
    fi


    docker swarm leave --force 2>/dev/null

    get_ip() {
        local ip=""
        
        # Try IPv4 first
        # First attempt: ifconfig.io
        ip=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
        
        # Second attempt: icanhazip.com
        if [ -z "$ip" ]; then
            ip=$(curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
        fi
        
        # Third attempt: ipecho.net
        if [ -z "$ip" ]; then
            ip=$(curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
        fi

        # If no IPv4, try IPv6
        if [ -z "$ip" ]; then
            # Try IPv6 with ifconfig.io
            ip=$(curl -6s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
            
            # Try IPv6 with icanhazip.com
            if [ -z "$ip" ]; then
                ip=$(curl -6s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
            fi
            
            # Try IPv6 with ipecho.net
            if [ -z "$ip" ]; then
                ip=$(curl -6s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
            fi
        fi

        if [ -z "$ip" ]; then
            echo "Error: Could not determine server IP address automatically (neither IPv4 nor IPv6)." >&2
            echo "Please set the ADVERTISE_ADDR environment variable manually." >&2
            echo "Example: export ADVERTISE_ADDR=<your-server-ip>" >&2
            exit 1
        fi

        echo "$ip"
    }

    get_private_ip() {
        ip addr show | grep -E "inet (192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)" | head -n1 | awk '{print $2}' | cut -d/ -f1
    }

    advertise_addr="${ADVERTISE_ADDR:-$(get_private_ip)}"

    if [ -z "$advertise_addr" ]; then
        echo "ERROR: We couldn't find a private IP address."
        echo "Please set the ADVERTISE_ADDR environment variable manually."
        echo "Example: export ADVERTISE_ADDR=192.168.1.100"
        exit 1
    fi
    echo "Using advertise address: $advertise_addr"

    docker swarm init --advertise-addr $advertise_addr
    
     if [ $? -ne 0 ]; then
        echo "Error: Failed to initialize Docker Swarm" >&2
        exit 1
    fi

    echo "Swarm initialized"

    docker network rm -f dokploy-network 2>/dev/null
    docker network create --driver overlay --attachable dokploy-network

    echo "Network created"

    mkdir -p /etc/dokploy

    chmod 777 /etc/dokploy

    # Login to GitHub Container Registry if using GitHub Packages
    if [ "$USE_GITHUB_PACKAGES" = true ] || [[ "$DOKPLOY_IMAGE" == *"ghcr.io"* ]]; then
        echo "GitHub Packages detected. Authentication required for private repositories."
        echo "For public repositories, authentication is optional but recommended."
        
        if [ -n "$GITHUB_TOKEN" ]; then
            echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$(echo $DOKPLOY_IMAGE | cut -d'/' -f2)" --password-stdin
            if [ $? -eq 0 ]; then
                echo "Successfully authenticated with GitHub Container Registry"
            else
                echo "Warning: Failed to authenticate with GitHub Container Registry"
                echo "Proceeding anyway (may fail if repository is private)"
            fi
        else
            echo "Note: GITHUB_TOKEN environment variable not set."
            echo "If the repository is private, set GITHUB_TOKEN to authenticate:"
            echo "export GITHUB_TOKEN=your_github_token"
            echo "Proceeding without authentication..."
        fi
    fi

    docker service create \
    --name dokploy-postgres \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --env POSTGRES_USER=dokploy \
    --env POSTGRES_DB=dokploy \
    --env POSTGRES_PASSWORD=amukds4wi9001583845717ad2 \
    --mount type=volume,source=dokploy-postgres-database,target=/var/lib/postgresql/data \
    postgres:16

    docker service create \
    --name dokploy-redis \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --mount type=volume,source=redis-data-volume,target=/data \
    redis:7

    # Installation
    docker service create \
      --name dokploy \
      --replicas 1 \
      --network dokploy-network \
      --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
      --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
      --mount type=volume,source=dokploy-docker-config,target=/root/.docker \
      --publish published=3000,target=3000,mode=host \
      --update-parallelism 1 \
      --update-order stop-first \
      --constraint 'node.role == manager' \
      $endpoint_mode \
      -e ADVERTISE_ADDR=$advertise_addr \
      $DOKPLOY_IMAGE

    sleep 4

    docker run -d \
        --name dokploy-traefik \
        --restart always \
        -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
        -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -p 80:80/tcp \
        -p 443:443/tcp \
        -p 443:443/udp \
        traefik:v3.5.0
    
    docker network connect dokploy-network dokploy-traefik


    # Optional: Use docker service create instead of docker run
    #   docker service create \
    #     --name dokploy-traefik \
    #     --constraint 'node.role==manager' \
    #     --network dokploy-network \
    #     --mount type=bind,source=/etc/dokploy/traefik/traefik.yml,target=/etc/traefik/traefik.yml \
    #     --mount type=bind,source=/etc/dokploy/traefik/dynamic,target=/etc/dokploy/traefik/dynamic \
    #     --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    #     --publish mode=host,published=443,target=443 \
    #     --publish mode=host,published=80,target=80 \
    #     --publish mode=host,published=443,target=443,protocol=udp \
    #     traefik:v3.5.0

    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    NC="\033[0m" # No Color

    format_ip_for_url() {
        local ip="$1"
        if echo "$ip" | grep -q ':'; then
            # IPv6
            echo "[${ip}]"
        else
            # IPv4
            echo "${ip}"
        fi
    }

    public_ip="${ADVERTISE_ADDR:-$(get_ip)}"
    formatted_addr=$(format_ip_for_url "$public_ip")
    echo ""
    printf "${GREEN}Congratulations, Dokploy is installed!${NC}\n"
    printf "${BLUE}Wait 15 seconds for the server to start${NC}\n"
    printf "${YELLOW}Please go to http://${formatted_addr}:3000${NC}\n\n"
}

update_dokploy() {
    echo "Updating Dokploy..."
    echo "Using Dokploy image for update: $DOKPLOY_IMAGE"
    
    # Login to GitHub Container Registry if using GitHub Packages
    if [ "$USE_GITHUB_PACKAGES" = true ] || [[ "$DOKPLOY_IMAGE" == *"ghcr.io"* ]]; then
        echo "GitHub Packages detected. Authentication required for private repositories."
        
        if [ -n "$GITHUB_TOKEN" ]; then
            echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$(echo $DOKPLOY_IMAGE | cut -d'/' -f2)" --password-stdin
            if [ $? -eq 0 ]; then
                echo "Successfully authenticated with GitHub Container Registry"
            else
                echo "Warning: Failed to authenticate with GitHub Container Registry"
                echo "Proceeding anyway (may fail if repository is private)"
            fi
        else
            echo "Note: GITHUB_TOKEN environment variable not set."
            echo "If the repository is private, set GITHUB_TOKEN to authenticate:"
            echo "export GITHUB_TOKEN=your_github_token"
            echo "Proceeding without authentication..."
        fi
    fi
    
    # Check if dokploy service exists
    if ! docker service ls | grep -q dokploy; then
        echo "Error: Dokploy service not found. Please run installation first."
        exit 1
    fi
    
    # Pull the latest image
    echo "Pulling latest image..."
    docker pull "$DOKPLOY_IMAGE"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to pull image $DOKPLOY_IMAGE"
        exit 1
    fi
    
    # Update the service
    echo "Updating Dokploy service..."
    docker service update --image "$DOKPLOY_IMAGE" dokploy
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to update Dokploy service"
        exit 1
    fi
    
    echo "Dokploy has been updated to the latest version using image: $DOKPLOY_IMAGE"
}

# Main script execution
if [ "$COMMAND" = "update" ]; then
    update_dokploy
else
    install_dokploy
fi
