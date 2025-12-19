# Reference Data Streaming & Analytics Architecture

A Kubernetes-based data lakehouse platform demonstrating end-to-end data streaming, cataloging, and analytics using Apache Iceberg, Redpanda, Polaris, and Trino.

## Overview

This project provides a complete reference architecture for building a modern data stack on Kubernetes, featuring:

- **Redpanda**: High-performance streaming data platform (Kafka API-compatible)
- **Apache Polaris**: Open-source Iceberg REST catalog for metadata management
- **Trino**: Distributed SQL query engine with time-travel capabilities
- **Redpanda Connect**: Data integration and transformation pipeline

## Architecture

```
┌─────────────────────┐
│ Redpanda Connect    │  ← Real-time data ingestion (Weather API, Events)
│ (Data Pipelines)    │
└──────────┬──────────┘
           │
           ↓
┌─────────────────────┐
│   Redpanda Cluster  │  ← Message streaming with Avro schema validation
│  (3-node cluster)   │     Automatic Iceberg table creation
└──────────┬──────────┘
           │
           ├─────────→ ┌──────────────┐
           │           │   Polaris    │  ← Iceberg catalog management
           │           │ (REST API)   │     ACID transactions
           │           └──────────────┘
           │
           ↓
┌─────────────────────┐
│      Trino          │  ← SQL analytics with time-travel queries
│  (Query Engine)     │
└─────────────────────┘
           │
           ↓
    ┌──────────────┐
    │  S3/MinIO    │  ← Persistent data storage
    │   Storage    │
    └──────────────┘
```

## Features

- **Real-time Streaming**: Ingest data from multiple sources with Redpanda Connect
- **Schema Management**: Avro schema validation and evolution with schema registry
- **ACID Compliance**: Iceberg tables with snapshot isolation and time-travel
- **SQL Analytics**: Query streaming data with standard SQL via Trino
- **Cloud-Native**: Fully containerized and orchestrated with Kubernetes operator and Helm
- **Security**: SASL/SCRAM authentication, TLS encryption, and role-based access control
- **Management**: Built-in Redpanda Console for cluster management

## Prerequisites

- Kubernetes cluster (1.23+)
- `kubectl` configured with cluster access
- `helm` (3.0+)
- Redpanda Enterprise license (for enterprise features)
- MinIO or S3-compatible storage

## Project Structure

```
.
├── redpanda/              # Redpanda cluster configuration
│   ├── redpanda-cluster.yaml       # Redpanda cluster K8s Custom Resource
│   ├── redpanda-console.yaml       # Redpanda Console K8s Custom Resource
│   ├── cloud-storage-secrets.yaml  # S3/MinIO credentials secret
│   ├── produce-events.sh           # Create a sample 'events' topic with AVRO schem and produce messages
│   └── events.avro                 # AVRO schema definition
│
├── redpanda-connect/      # Data integration pipelines
│   ├── weather.yaml                # Multi-city weather ingestion
│   ├── pipeline.yaml               # Basic pipeline example
│   ├── weather.avro                # Weather telemetry schema
│   ├── rpcn-install.sh             # Helm installation script
│   └── create-weather-topic.sh     # Topic setup script
│
├── polaris/               # Iceberg catalog management
│   ├── polaris-setup.sh            # Complete Polaris setup
│   ├── polaris-query.sh            # Query Iceberg tables from Polaris catalog API
│   └── polaris-delete-catalog.sh   # Catalog cleanup utility
│
└── trino/                 # SQL query engine
    ├── values.yaml                 # Helm configuration
    ├── trino.sql                   # Example queries
    └── polaris-trino-creds.yaml    # Credentials secret
```

## Quick Start

### 1. Setup Apache Polaris Catalog

```bash
cd polaris
./polaris-setup.sh
```
### 2. Deploy Redpanda Cluster

```bash
# Install the K8s cluster-scoped Redpanda Operator. 
# This enables deployment of multiple Redpanda clusters in multiple namespaces from one operator installation
helm repo add redpanda https://charts.redpanda.com
helm repo update
helm upgrade --install redpanda-controller redpanda/operator \
  --namespace redpanda-operator \
  --create-namespace \
  --version v25.3.1 \
  --set crds.enabled=true

# Create Redpanda cluster namespace
kubectl create namespace redpanda

# Create superusers secret
echo 'superuser:secretpassword:SCRAM-SHA-256' >> superusers.txt
kubectl create secret generic redpanda-superusers --from-file=superusers.txt --namespace redpanda 

# Create the license key secret
kubectl create secret generic redpanda-license --from-file=license=./redpanda.license --namespace redpanda

# Configure cloud storage secrets
kubectl apply -f redpanda/cloud-storage-secrets.yaml

# Deploy Redpanda cluster
kubectl apply -f redpanda/redpanda-cluster.yaml

# Deploy Redpanda Console UI for management
kubectl apply -f redpanda/redpanda-console.yaml
```

### 3. Deploy Trino Query Engine

```bash
# Create namespace
kubectl create namespace trino

# Configure credentials
kubectl apply -f trino/polaris-trino-creds.yaml

# Install Trino
helm install trino trino/trino -f trino/values.yaml -n trino
```

### 4. Deploy Redpanda Connect Pipelines

```bash
cd redpanda-connect

# Create weather topic and schema
./create-weather-topic.sh

# Install Redpanda Connect
./rpcn-install.sh
```

## Usage Examples

### Query Iceberg Tables via Polaris API

```bash
cd polaris
./polaris-query.sh
```

### Access Redpanda Console

```bash
kubectl port-forward svc/redpanda-console 8080:8080 -n redpanda
# Open http://localhost:8080 in browser
```

### Query Data with Trino

```bash
# Port-forward Trino service
kubectl port-forward svc/trino 8080:8080 -n trino

# Connect with Trino CLI or shell into Trino container
trino --server localhost:8080

# Run example queries
SHOW SCHEMAS FROM polaris;
SELECT * FROM polaris.redpanda.weather LIMIT 10;
```

### Basic Analytics

```sql
-- Get latest weather data by city
SELECT city, temperature_c, humidity, wind_speed_kmh, description
FROM polaris.redpanda.weather
ORDER BY timestamp DESC
LIMIT 10;

-- Average temperature by city
SELECT city, AVG(temperature_f) as avg_temp
FROM polaris.redpanda.weather
GROUP BY city;
```

### Time-Travel Queries

```sql
-- View historical snapshots
SELECT snapshot_id, committed_at
FROM polaris.redpanda."weather$snapshots"
ORDER BY committed_at DESC;

-- Query data as of specific snapshot
SELECT * FROM polaris.redpanda.weather
FOR VERSION AS OF 1234567890;

-- Query data as of specific timestamp (time travel)
SELECT * FROM polaris.redpanda.events 
FOR TIMESTAMP AS OF TIMESTAMP '2025-12-11 17:16:00';
```

## Data Pipeline Examples

The `weather.yaml` pipeline demonstrates:
- Multi-input data sources (wttr.in API for Boston, NYC, LA, London)
- Bloblang transformations for data parsing and normalization
- Avro encoding with schema registry integration
- Keyed publishing to Redpanda topic

## Configuration

### Redpanda Cluster

- **Nodes**: 3 brokers with 64GB memory, 16 CPU cores each
- **Storage**: 20GiB persistent volume per broker + S3 tiered storage
- **Security**: SASL/SCRAM authentication with TLS encryption
- **Iceberg Integration**: Automatic table creation from Redpanda topics

### Polaris Catalog

- **Backend**: PostgreSQL for metadata persistence
- **Storage**: S3/MinIO for Iceberg data files
- **Authentication**: OAuth2 client credentials
- **API**: REST catalog endpoint at `http://polaris.redpanda-polaris.svc.cluster.local:8181`

### Trino

- **Catalogs**: Iceberg REST catalog connected to Polaris
- **Storage**: S3-compatible object storage
- **Workers**: 1 worker node (scalable)
- **Debug**: Enabled for Iceberg/S3 operations

## Troubleshooting

### Common Issues

1. **Redpanda cluster not starting**
   - Verify license secret is properly configured
   - Check resource availability (CPU/memory)
   - Review logs: `kubectl logs -n redpanda <pod-name>`

2. **Polaris connection errors**
   - Ensure namespace and service DNS resolution
   - Verify OAuth2 credentials in secrets
   - Check Polaris service is running: `kubectl get pods -n redpanda-polaris`

3. **Trino cannot access Iceberg tables**
   - Verify S3 credentials are correct
   - Check Polaris catalog configuration in `values.yaml`
   - Review Trino coordinator logs for detailed errors

## Performance Tuning

- **Redpanda**: Adjust `resources.memory` and `resources.cpu` per broker based on workload
- **Trino**: Scale workers horizontally for better query parallelism
- **Polaris**: Increase PostgreSQL resources for high metadata throughput

## Security Considerations

- All credentials are stored in Kubernetes secrets
- SASL/SCRAM authentication required for Redpanda access
- TLS encryption for data in transit
- Network policies recommended for production deployments
- Regular rotation of OAuth2 client credentials

## License

This project is provided as-is for reference and educational purposes.

## Resources

- [Redpanda Documentation](https://docs.redpanda.com/)
- [Apache Polaris](https://polaris.apache.org/)
- [Apache Iceberg](https://iceberg.apache.org/)
- [Trino Documentation](https://trino.io/docs/)
- [Redpanda Connect](https://docs.redpanda.com/redpanda-connect/)