# STB HG680P Bash Automation

Automating the setup of an HG680P Set-Top Box (STB) as a Linux-based mini server using Bash Script.

This project combines several manual installation and configuration steps into a single automated workflow. The script prepares the system, installs Docker and Docker Compose, installs CasaOS and Portainer, and deploys a monitoring stack using Prometheus, Node Exporter, cAdvisor, and Grafana.

The goal is to make the server preparation process more consistent, repeatable, and easier to apply to another compatible STB.

> **Note:** IP addresses, hostnames, usernames, and passwords used in this documentation are examples only. Do not commit real credentials, private network information, or other sensitive configuration to a public repository.

## Project Overview

The HG680P can be converted from a regular Set-Top Box into a small Linux server by installing Armbian and several server applications.

Previously, these components were installed manually in multiple stages. This project introduces a Bash-based automation approach that combines the installation and configuration process into a single script.

The automation covers:

* System validation
* Docker Engine installation
* Docker Compose Plugin installation
* CasaOS installation
* Portainer deployment
* Monitoring directory and configuration creation
* Prometheus authentication using bcrypt
* Monitoring stack deployment

The resulting environment provides both web-based server management and container monitoring.

## Architecture

The resulting environment consists of several components:

```text
                         HG680P STB
                              │
                         Armbian Linux
                              │
              ┌───────────────┴────────────────┐
              │                                │
           Docker                           CasaOS
              │
              ├────────────── Portainer
              │
              └────────────── Monitoring Stack
                                   │
                 ┌─────────────────┼─────────────────┐
                 │                 │                 │
             Prometheus       Node Exporter       cAdvisor
                 │
                 └─────────────────┐
                                   │
                                Grafana
```

## Prerequisites

Before running the automation script, prepare the following:

* HG680P STB
* Armbian installed and booting successfully
* Network connectivity
* SSH access or local terminal access
* `sudo` privileges
* Internet access for package and container image downloads

The script is designed primarily for Ubuntu-based Armbian environments.

## Prepare the STB

Verify the network interface and assigned IP address:

```bash
ip a
```

Example:

```text
192.168.10.100
```

Use the actual IP address assigned to the STB when accessing the services from another device.

## Repository Structure

```text
stb-hg680p-bash-automation/
├── README.md
└── install.sh
```

The repository intentionally keeps the implementation simple:

* `README.md` documents the automation and deployment process.
* `install.sh` contains the Bash automation script.

## Bash Automation

The main script is:

```text
install.sh
```

The script uses:

```bash
#!/bin/bash

set -e
```

`set -e` makes the script stop when a command returns a non-zero exit status, helping prevent the installation process from continuing after an unexpected failure.

## System Validation

Before installing the services, the script checks whether it is being executed with root privileges.

It also reads `/etc/os-release` and displays:

* Current user
* Hostname
* Operating system
* CPU architecture

Example checks performed by the script:

```bash
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi

. /etc/os-release

echo "User         : $(whoami)"
echo "Hostname     : $(hostname)"
echo "OS           : $PRETTY_NAME"
echo "Architecture : $(dpkg --print-architecture)"
```

The script also warns when the detected operating system is not Ubuntu.

## Docker Installation

The script checks whether Docker and Docker Compose are already available.

If they are installed, the existing Docker service is enabled and started.

Otherwise, the script configures the official Docker repository and installs:

* Docker Engine
* Docker CLI
* Containerd
* Docker Buildx
* Docker Compose Plugin

The Docker repository is configured dynamically according to the detected Ubuntu release and system architecture.

After installation, Docker is enabled:

```bash
systemctl enable --now docker
```

The installed versions can be verified with:

```bash
docker --version
docker compose version
```

Running containers can be checked with:

```bash
docker ps
```

## CasaOS

CasaOS provides a web-based interface for managing the Linux server and applications.

The script checks whether CasaOS is already installed and running before attempting installation.

When CasaOS is not available, the official installer is executed:

```bash
curl -fsSL https://get.casaos.io | bash
```

The CasaOS service is then checked using:

```bash
systemctl status casaos --no-pager
```

Once installed, CasaOS can be accessed using the STB address:

```text
http://IP-STB
```

For example:

```text
http://192.168.10.100
```

Replace the example address with the actual address of the target STB.

## Portainer

Portainer is deployed as a Docker container and provides a web interface for managing Docker resources.

The script creates:

```text
/opt/portainer
```

and:

```text
/opt/portainer/portainer_data
```

The generated Compose configuration uses:

```yaml
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
```

The container is started with:

```bash
cd /opt/portainer
docker compose up -d
```

Verify the container:

```bash
docker ps --filter "name=^portainer$"
```

Portainer can then be accessed through:

```text
https://IP-STB:9443
```

Portainer provides management for Docker:

* Containers
* Images
* Volumes
* Networks
* Container resources

## Monitoring Stack

The automation also deploys a monitoring stack consisting of:

| Component     | Purpose                        | Port |
| ------------- | ------------------------------ | ---: |
| Node Exporter | Host system metrics            | 9100 |
| cAdvisor      | Container metrics              | 8080 |
| Prometheus    | Metrics collection and storage | 9090 |
| Grafana       | Metrics visualization          | 3000 |

The monitoring configuration is stored under:

```text
/opt/monitoring
```

The script creates:

```text
/opt/monitoring/
├── docker-compose.yml
└── monitoring-data/
    ├── config/
    │   ├── prometheus.yml
    │   ├── web-config.yml
    │   └── datasources.yml
    ├── prometheus_data/
    └── grafana_data/
```

## Monitoring Docker Compose

The monitoring stack uses the following container images:

```text
gcr.io/cadvisor/cadvisor:v0.47.1
prom/node-exporter:v1.7.0
prom/prometheus:v3.0.0
grafana/grafana:11.5.0
```

The Compose configuration creates four containers:

```text
monitoring-cadvisor
monitoring-node-exporter
monitoring-prometheus
monitoring-grafana
```

cAdvisor receives access to Docker and host filesystem information so that container-level metrics can be collected.

Node Exporter exposes host-level metrics.

Prometheus collects metrics from Node Exporter and cAdvisor.

Grafana uses Prometheus as its data source and provides dashboards for visualization.

## Prometheus Configuration

The generated Prometheus configuration defines three scrape targets:

```yaml
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets:
          - localhost:9090

  - job_name: "cadvisor"
    static_configs:
      - targets:
          - cadvisor:8080

  - job_name: "VM-STB"
    static_configs:
      - targets:
          - node-exporter:9100
```

The scrape interval is configured to:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
```

The target names can be changed to match the environment where the script is deployed.

## Prometheus Authentication

The script requests the monitoring password interactively:

```bash
read -rsp "Enter monitoring password: " MONITORING_PASSWORD
echo
```

The password is not hard-coded into the script.

The script then generates a bcrypt hash using Python:

```bash
python3 -c "import bcrypt"
```

If the bcrypt module is unavailable, the script installs:

```text
python3-bcrypt
```

The generated hash is used by Prometheus Basic Authentication.

The generated configuration follows this structure:

```yaml
basic_auth_users:
  admin: "<GENERATED_BCRYPT_HASH>"
```

The actual password and generated hash should never be committed to a public repository.

## Grafana Datasource

Grafana is automatically configured to use Prometheus:

```yaml
apiVersion: 1

datasources:
  - name: prometheus
    type: prometheus
    url: http://prometheus:9090
    access: proxy
    isDefault: true
    basicAuth: true
    basicAuthUser: admin
    secureJsonData:
      basicAuthPassword: "<MONITORING_PASSWORD>"
```

The actual password is generated at runtime and should not be stored in Git.

Grafana is exposed on:

```text
http://IP-STB:3000
```

## Run the Automation

Clone or copy the repository to the STB.

Make the script executable:

```bash
chmod +x install.sh
```

Run the installer with root privileges:

```bash
sudo bash install.sh
```

The script will request the monitoring password interactively.

The installation then proceeds through the following stages:

```text
System Check
    ↓
Docker
    ↓
CasaOS
    ↓
Portainer
    ↓
Monitoring
```

Because the script checks whether several components already exist, it can avoid reinstalling some components unnecessarily.

## Verify the Installation

### Docker

```bash
docker --version
docker compose version
```

### Running Containers

```bash
docker ps
```

### Portainer

```bash
docker ps --filter "name=^portainer$"
```

### Monitoring Containers

```bash
docker ps --filter "name=monitoring-"
```

### Docker Service

```bash
systemctl status docker --no-pager
```

### CasaOS

```bash
systemctl status casaos --no-pager
```

## Access the Services

Replace `IP-STB` with the actual STB address.

### CasaOS

```text
http://IP-STB
```

### Portainer

```text
https://IP-STB:9443
```

### cAdvisor

```text
http://IP-STB:8080
```

### Prometheus

```text
http://IP-STB:9090
```

### Grafana

```text
http://IP-STB:3000
```

## Verify Prometheus Targets

Open Prometheus and navigate to:

```text
Status → Target
```

The monitoring targets should become available after the containers start.

Expected targets include:

```text
cadvisor:8080
node-exporter:9100
```

A target showing `UP` indicates that Prometheus can successfully scrape the configured endpoint.

## Monitoring Flow

The monitoring data flow is:

```text
STB Host
   │
   ├── Node Exporter ──────┐
   │                       │
   └── cAdvisor ───────────┤
                           ↓
                       Prometheus
                           │
                           ↓
                        Grafana
```

Node Exporter provides host-level metrics, while cAdvisor provides container-level metrics.

Prometheus collects these metrics and Grafana uses Prometheus as its data source for visualization.

## Troubleshooting

### Docker is not available

Check the Docker service:

```bash
systemctl status docker --no-pager
```

Restart it if necessary:

```bash
sudo systemctl restart docker
```

Then verify:

```bash
docker ps
```

### Portainer is not running

Check:

```bash
docker ps -a --filter "name=^portainer$"
```

View the logs:

```bash
docker logs portainer
```

Restart the container:

```bash
cd /opt/portainer
docker compose restart
```

### Monitoring containers are not running

Check:

```bash
cd /opt/monitoring
docker compose ps
```

View the logs:

```bash
docker compose logs
```

Restart the monitoring stack:

```bash
docker compose up -d
```

### Prometheus targets are DOWN

Check the monitoring containers:

```bash
docker ps --filter "name=monitoring-"
```

Then inspect Prometheus logs:

```bash
docker logs monitoring-prometheus
```

Also verify that the configured Docker Compose service names match the Prometheus targets.

## Security Considerations

This project is intended for a public GitHub repository, therefore sensitive information must remain outside the repository.

Do not commit:

* Real passwords
* SSH private keys
* API tokens
* Cloud credentials
* Private network configuration
* Production secrets
* Real authentication hashes if they are considered sensitive in the deployment environment

The monitoring password is requested interactively by the script instead of being stored directly in `install.sh`.

When adapting the script to another environment, review all configuration files generated by the script before exposing the server to an untrusted network.

## Result

After the automation completes successfully, the HG680P STB provides a Linux-based mini server environment with:

* Armbian Linux
* Docker
* Docker Compose
* CasaOS
* Portainer
* Prometheus
* Node Exporter
* cAdvisor
* Grafana

The installation process that previously required multiple manual steps can therefore be executed through a single Bash automation script.

## Next Stage

This Bash automation provides the foundation for more structured infrastructure automation.

The next stage is to move the configuration and installation process to **Ansible**, allowing the server setup to be managed through declarative playbooks, inventories, and repeatable automation.
