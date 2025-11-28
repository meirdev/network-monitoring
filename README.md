# Network Monitoring

Open source alternative to [Cloudflare Magic Network Monitoring](https://developers.cloudflare.com/magic-network-monitoring/).

## Components

- **GoFlow2**: IPFIX, NetFlow v5/v9, and sFlow collector.
- **Kafka**.
- **ClickHouse**.
- **Grafana**.

GoFlow2 sends flow data to Kafka, which is then consumed by ClickHouse for storage and analysis. Grafana is used to visualize the data.

## Grafana Dashboards

Image of Grafana dashboard showing network flow data in Mbps/MB (same dashboard is also available for PPS/Packets):

<div align="center">
  <img src="./assets/grafana-dashboard-mbps.png" alt="Grafana Dashboard - Mbps" width="600">
</div>

## Setup Instructions

Clone the repository and use `docker compose` to start the services:

```bash
docker compose up -d
```

Username and password for ClickHouse: `default:password`.

Username and password for Grafana: `admin:admin`.

##  Routers

Some routers do not provide `sampling_rate` in their flow data, which is required to understand what the "real" traffic is. In this case, you can enter the router's IP address with the `default_sampling`:

```bash
curl -X POST http://localhost:8090/routers \
  -d '{
    "name": "my-router",
    "router_ip": "127.0.0.1",
    "default_sampling": 1000
  }'
```

## Rules

### Static Rule

Monitor a network prefix and alert when bandwidth exceeds 1 Gbps for 5 consecutive minutes:

```bash
curl -X POST http://localhost:8090/rules \
  -d '{
    "name": "Production Network - High Bandwidth",
    "prefixes": ["10.0.0.0/8"],
    "type": "threshold",
    "bandwidth_threshold": 1000000000,
    "duration": 5
  }'
```

Monitor for DDoS attacks by detecting high packet rates, 1 Mps for 3 consecutive minutes:

```bash
curl -X POST http://localhost:8090/rules \
  -d '{
    "name": "DDoS Detection - Packet Flood",
    "prefixes": ["203.0.113.0/24"],
    "type": "threshold",
    "packet_threshold": 1000000,
    "duration": 3
  }'
```

### Dynamic Rule

Detect unusual bandwidth spikes with medium sensitivity:

```bash
curl -X POST http://localhost:8090/rules \
  -d '{
    "name": "Web Servers - Bandwidth Anomaly",
    "prefixes": ["10.20.30.0/24"],
    "type": "zscore",
    "zscore_sensitivity": "medium",
    "zscore_target": "bits"
  }'
```

Options:

zscore_sensitivity: `low`, `medium`, `high`.

zscore_target: `bits`, `packets`.

## API Reference

### Routers

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/routers` | List all routers |
| GET | `/routers/:router_id` | Get specific router |
| POST | `/routers` | Create new router |
| PUT | `/routers/:router_id` | Update router |
| DELETE | `/routers/:router_id` | Delete router |

### Rules

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/rules` | List all rules |
| GET | `/rules/:rule_id` | Get specific rule |
| POST | `/rules` | Create new rule |
| PUT | `/rules/:rule_id` | Update rule |
| DELETE | `/rules/:rule_id` | Delete rule |

## Alerting

The `alert` script is used to trigger another command whenever rules are crossed.
Add it to your crontab (or a similar scheduler) and run it every 30–60 seconds.

Example with `mail` command:

```bash
./alert | \
  mail -s "Network Alert" \
       -a "Content-Type: application/json" \
       mssp@example.com
```
