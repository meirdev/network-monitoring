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

## API Reference

View the full API documentation at http://127.0.0.1:8090/docs/

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
