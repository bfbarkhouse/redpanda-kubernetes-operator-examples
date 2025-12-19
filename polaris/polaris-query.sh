#!/usr/bin/env bash
# POLARIS_NAMESPACE="polaris" POLARIS_CATALOG_NAME="redpanda_catalog" ICEBERG_TABLE="events" ./polaris-query.sh
set -euo pipefail

# ===== Configuration =====
# Kubernetes namespace for Polaris
POLARIS_NAMESPACE="${POLARIS_NAMESPACE:-polaris}"
# Polaris catalog name
POLARIS_CATALOG_NAME="${POLARIS_CATALOG_NAME:-redpanda_catalog}"
# Topic/Table to query
ICEBERG_TABLE="${ICEBERG_TABLE:-events}"

# Get the Polaris pod name dynamically
POLARIS_POD=$(kubectl get pod -n ${POLARIS_NAMESPACE} --selector=app.kubernetes.io/name=polaris -o jsonpath='{.items[0].metadata.name}')
echo "Using Polaris pod: $POLARIS_POD"

TOKEN=$(kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s http://localhost:8181/api/catalog/v1/oauth/tokens \
  --user root:s3cr3t \
  -H "Polaris-Realm: POLARIS" \
  -d grant_type=client_credentials \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)

kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET http://localhost:8181/api/catalog/v1/${POLARIS_CATALOG_NAME}/namespaces/redpanda/tables \
-H "Authorization: Bearer $TOKEN" | jq

kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET http://localhost:8181/api/catalog/v1/${POLARIS_CATALOG_NAME}/namespaces/redpanda/tables/${ICEBERG_TABLE} \
-H "Authorization: Bearer $TOKEN" | jq
