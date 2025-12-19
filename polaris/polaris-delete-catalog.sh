#!/usr/bin/env bash
# POLARIS_NAMESPACE="polaris" POLARIS_CATALOG_NAME="redpanda_catalog" ./polaris-delete-catalog.sh
set -euo pipefail

# ===== Configuration =====
# Kubernetes namespace for Polaris
POLARIS_NAMESPACE="${POLARIS_NAMESPACE:-polaris}"
# Polaris catalog name
POLARIS_CATALOG_NAME="${POLARIS_CATALOG_NAME:-redpanda_catalog}"

# Get the Polaris pod name dynamically
POLARIS_POD=$(kubectl get pod -n ${POLARIS_NAMESPACE} --selector=app.kubernetes.io/name=polaris -o jsonpath='{.items[0].metadata.name}')
echo "Using Polaris pod: $POLARIS_POD"

# Get a token
TOKEN=$(kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s http://localhost:8181/api/catalog/v1/oauth/tokens \
  --user root:s3cr3t \
  -H "Polaris-Realm: POLARIS" \
  -d grant_type=client_credentials \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)

# Delete the catalog (requires emptying first)
CATALOG_NAME="${POLARIS_CATALOG_NAME}"
echo "Enumerating namespaces in catalog: $CATALOG_NAME"
NAMESPACES=$(kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET \
  "http://localhost:8181/api/catalog/v1/$CATALOG_NAME/namespaces" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.namespaces[].namespace | join(".")')

for NS in $NAMESPACES; do
  echo "Processing namespace: $NS"

# Get all tables in the namespace
  TABLES=$(kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET \
    "http://localhost:8181/api/catalog/v1/$CATALOG_NAME/namespaces/$NS/tables" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.identifiers[]?.name // empty')

# Delete each table
  for TABLE in $TABLES; do
    echo "  Deleting table: $NS.$TABLE"
    kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X DELETE \
      "http://localhost:8181/api/catalog/v1/$CATALOG_NAME/namespaces/$NS/tables/$TABLE?purgeRequested=true" \
      -H "Authorization: Bearer $TOKEN"
  done
done

# Delete all namespaces
for NS in $NAMESPACES; do
  echo "Deleting namespace: $NS"
  kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X DELETE \
    "http://localhost:8181/api/catalog/v1/$CATALOG_NAME/namespaces/$NS" \
    -H "Authorization: Bearer $TOKEN"
done

# Finally delete the catalog
echo "Deleting catalog: $CATALOG_NAME"
kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X DELETE \
  "http://localhost:8181/api/management/v1/catalogs/$CATALOG_NAME" \
  -H "Authorization: Bearer $TOKEN" | jq