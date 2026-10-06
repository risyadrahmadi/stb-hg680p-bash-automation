```bash
#!/bin/bash

set -e

# Monitoring credentials
MONITORING_USER="admin"

read -rsp "Enter monitoring password: " MONITORING_PASSWORD
echo

if [ -z "$MONITORING_PASSWORD" ]; then
    echo "Monitoring password cannot be empty."
    exit 1
fi

export MONITORING_PASSWORD

generate_monitoring_hash() {
    echo
    echo "[CHECK] Preparing bcrypt for monitoring authentication..."

    if ! python3 -c "import bcrypt" >/dev/null 2>&1; then
        echo "Python bcrypt module is not installed."
        echo "Installing python3-bcrypt..."
        apt-get update
        apt-get install -y python3-bcrypt
    fi

    MONITORING_PASSWORD_HASH=$(python3 -c \
    'import bcrypt, os; print(bcrypt.hashpw(
    os.environ["MONITORING_PASSWORD"].encode(),
    bcrypt.gensalt()).decode())')

    export MONITORING_PASSWORD_HASH

    echo "Monitoring bcrypt hash generated successfully."
}

echo "=========================================="
echo " STB Automation Installer"
echo "=========================================="

check_system() {
    echo
    echo "[CHECK] Checking system..."

    if [ "$EUID" -ne 0 ]; then
        echo "Please run this script with sudo."
        exit 1
    fi

    . /etc/os-release

    echo "User         : $(whoami)"
    echo "Hostname     : $(hostname)"
    echo "OS           : $PRETTY_NAME"
    echo "Architecture : $(dpkg --print-architecture)"

    if [ "$ID" != "ubuntu" ]; then
        echo "Warning: This script is designed for Ubuntu/Armbian based on Ubuntu."
    fi

    echo
    echo "System check completed."
}

install_docker() {
    echo
    echo "[1/4] Installing Docker..."

    if command -v docker >/dev/null 2>&1 &&
       docker compose version >/dev/null 2>&1; then

        echo "Docker and Docker Compose are already installed."
        systemctl enable --now docker

        docker --version
        docker compose version
        return
    fi

    echo "Docker is not installed. Installing Docker..."

    apt-get update
    apt-get install -y ca-certificates curl

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc

    chmod a+r /etc/apt/keyrings/docker.asc

    . /etc/os-release

    cat > /etc/apt/sources.list.d/docker.sources <<DOCKER_REPO
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER_REPO

    apt-get update

    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker

    echo
    echo "Docker installation completed."

    docker --version
    docker compose version
}

install_casaos() {
    echo
    echo "[2/4] Installing CasaOS..."

    if systemctl is-active --quiet casaos; then
        echo "CasaOS is already installed and running."
        systemctl status casaos --no-pager
        return
    fi

    if [ -x /usr/bin/casaos ]; then
        echo "CasaOS binary already exists."
        echo "Starting CasaOS services..."
        systemctl enable --now casaos
        return
    fi

    echo "CasaOS is not installed."
    echo "Installing CasaOS using the official installer..."

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is not installed. Installing curl..."
        apt-get update
        apt-get install -y curl
    fi

    curl -fsSL https://get.casaos.io | bash

    echo
    echo "CasaOS installation completed."
    systemctl status casaos --no-pager
}

install_portainer() {
    echo
    echo "[3/4] Installing Portainer..."

    if docker ps --format '{{.Names}}' |
       grep -qx "portainer"; then

        echo "Portainer is already running."
        docker ps --filter "name=^portainer$"
        return
    fi

    echo "Preparing Portainer directory..."

    mkdir -p /opt/portainer/portainer_data

    cat > /opt/portainer/docker-compose.yml <<'COMPOSE'
services:
  portainer:
    container_name: portainer
    image: portainer/portainer-ce:lts
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer_data:/data
    ports:
      - "9443:9443"
      - "8000:8000"

networks:
  default:
    name: portainer_network
COMPOSE

    echo "Starting Portainer..."

    cd /opt/portainer
    docker compose up -d

    echo
    echo "Portainer installation completed."

    docker ps --filter "name=^portainer$"
}

install_monitoring() {
    echo
    echo "[4/4] Installing Monitoring..."

    mkdir -p /opt/monitoring/monitoring-data/config
    mkdir -p /opt/monitoring/monitoring-data/prometheus_data
    mkdir -p /opt/monitoring/monitoring-data/grafana_data

    cat > /opt/monitoring/docker-compose.yml <<'COMPOSE'
services:
  cadvisor:
    container_name: monitoring-cadvisor
    image: gcr.io/cadvisor/cadvisor:v0.47.1
    restart: always
    devices:
      - "/dev/kmsg:/dev/kmsg"
    volumes:
      - "/:/rootfs:ro"
      - "/sys:/sys:ro"
      - "/sys/fs/cgroup:/sys/fs/cgroup:ro"
      - "/var/lib/docker:/var/lib/docker:ro"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "/dev/disk:/dev/disk:ro"
    privileged: true
    ports:
      - "8080:8080"

  node-exporter:
    container_name: monitoring-node-exporter
    image: prom/node-exporter:v1.7.0
    restart: always
    command:
      - "--path.rootfs=/host"
    volumes:
      - "/:/host:ro"
    ports:
      - "9100:9100"

  prometheus:
    container_name: monitoring-prometheus
    image: prom/prometheus:v3.0.0
    user: root
    restart: always
    volumes:
      - "./monitoring-data/config/prometheus.yml:/etc/prometheus/prometheus.yml"
      - "./monitoring-data/config/web-config.yml:/etc/prometheus/web-config.yml"
      - "./monitoring-data/prometheus_data:/prometheus"
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=3d"
      - "--web.config.file=/etc/prometheus/web-config.yml"
    ports:
      - "9090:9090"
    depends_on:
      - cadvisor
      - node-exporter

  grafana:
    container_name: monitoring-grafana
    image: grafana/grafana:11.5.0
    user: root
    restart: always
    volumes:
      - "./monitoring-data/config/datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml"
      - "./monitoring-data/grafana_data:/var/lib/grafana"
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
COMPOSE

    cat > /opt/monitoring/monitoring-data/config/prometheus.yml <<PROMETHEUS
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets:
          - localhost:9090
    basic_auth:
      username: ${MONITORING_USER}
      password: ${MONITORING_PASSWORD}

  - job_name: "cadvisor"
    static_configs:
      - targets:
          - cadvisor:8080

  - job_name: "VM-STB"
    static_configs:
      - targets:
          - node-exporter:9100
PROMETHEUS

    cat > /opt/monitoring/monitoring-data/config/web-config.yml <<WEBCONFIG
basic_auth_users:
  ${MONITORING_USER}: "${MONITORING_PASSWORD_HASH}"
WEBCONFIG

    cat > /opt/monitoring/monitoring-data/config/datasources.yml <<DATASOURCE
apiVersion: 1

datasources:
  - name: prometheus
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    isDefault: true
    basicAuth: true
    basicAuthUser: ${MONITORING_USER}
    secureJsonData:
      basicAuthPassword: "${MONITORING_PASSWORD}"
DATASOURCE

    echo "Starting monitoring services..."

    cd /opt/monitoring
    docker compose up -d

    echo
    echo "Monitoring installation completed."

    docker ps --filter "name=monitoring-"
}

check_system
install_docker
install_casaos
install_portainer
generate_monitoring_hash
install_monitoring

echo
echo "=========================================="
echo " Installation process completed."
echo "=========================================="
```
