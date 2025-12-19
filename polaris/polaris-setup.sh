#!/usr/bin/env bash
# S3_BUCKET="s3://redpanda" MINIO_ENDPOINT="http://minio.minio.svc.cluster.local:9000" POLARIS_NAMESPACE="polaris" POLARIS_CATALOG_NAME="redpanda_catalog" ./polaris-setup.sh
set -euo pipefail

# ===== Configuration =====
# Kubernetes namespace for Polaris
POLARIS_NAMESPACE="${POLARIS_NAMESPACE:-polaris}"
# Polaris catalog name
POLARIS_CATALOG_NAME="${POLARIS_CATALOG_NAME:-redpanda_catalog}"
# S3 bucket for Polaris catalog
S3_BUCKET="${S3_BUCKET:-s3://redpanda}"
# MinIO endpoint URL
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://minio.minio.svc.cluster.local:9000}"
# Storage region
STORAGE_REGION="${STORAGE_REGION:-local}"

# Download the chart into a local directory:
if [ -d "./helm/polaris" ]; then
  echo "Helm chart already exists at ./helm/polaris, skipping download..."
else
  helm pull polaris \
    --repo https://downloads.apache.org/incubator/polaris/helm-chart \
    --devel \
    --untar \
    --untardir ./helm
fi

# Pause for manual configuration
echo ""
echo "===== BEFORE PROCEEDING ====="
echo "1. Set the MinIO access key secrets in helm/polaris/ci/fixtures/storage.yaml"
echo "2. Add the following extraEnv stanza to helm/polaris/ci/persistence-values.yaml"
echo ""
cat << 'EOF'
extraEnv:
 - name: AWS_ACCESS_KEY_ID
   valueFrom:
     secretKeyRef:
       name: polaris-storage
       key: access-key
 - name: AWS_SECRET_ACCESS_KEY
   valueFrom:
     secretKeyRef:
       name: polaris-storage
       key: secret-key
EOF
echo ""
echo "3. Adjust the Polaris storage settings. Add the following storage stanza to helm/polaris/ci/persistence-values.yaml"
echo ""
cat << 'EOF'
storage:
  className: default # whatever your PVC class name is. (standard, default, hostpath, etc.)
  size: 1Gi # adjust the desired size
EOF
echo ""
echo "Press enter when completed..."
echo "============================="
read -r


# Create required resources:
kubectl get namespace ${POLARIS_NAMESPACE} || kubectl create namespace ${POLARIS_NAMESPACE}
kubectl apply --namespace ${POLARIS_NAMESPACE} -f helm/polaris/ci/fixtures/
kubectl wait --namespace ${POLARIS_NAMESPACE} --for=condition=ready pod --selector=app.kubernetes.io/name=postgres --timeout=120s

# Install the chart with a persistent backend:

helm upgrade --install polaris helm/polaris --namespace ${POLARIS_NAMESPACE} --values helm/polaris/ci/persistence-values.yaml
kubectl wait --namespace ${POLARIS_NAMESPACE} --for=condition=ready pod --selector=app.kubernetes.io/name=polaris --timeout=120s

# Get the Polaris pod name dynamically
POLARIS_POD=$(kubectl get pod -n ${POLARIS_NAMESPACE} --selector=app.kubernetes.io/name=polaris -o jsonpath='{.items[0].metadata.name}')
echo "Using Polaris pod: $POLARIS_POD"

# Run the catalog bootstrap using the Polaris admin tool:

kubectl run polaris-bootstrap \
  -n ${POLARIS_NAMESPACE} \
  --image=apache/polaris-admin-tool:latest \
  --restart=Never \
  --rm -it \
  --env="quarkus.datasource.username=$(kubectl get secret polaris-persistence -n ${POLARIS_NAMESPACE} -o jsonpath='{.data.username}' | base64 --decode)" \
  --env="quarkus.datasource.password=$(kubectl get secret polaris-persistence -n ${POLARIS_NAMESPACE} -o jsonpath='{.data.password}' | base64 --decode)" \
  --env="quarkus.datasource.jdbc.url=$(kubectl get secret polaris-persistence -n ${POLARIS_NAMESPACE} -o jsonpath='{.data.jdbcUrl}' | base64 --decode)" \
  -- \
  bootstrap -r POLARIS -c POLARIS,root,s3cr3t -p

# Now the cluster should be up and running. You can run the built-in connection test to verify:

helm test polaris --namespace ${POLARIS_NAMESPACE}

# Create the catalog
TOKEN=$(kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s http://localhost:8181/api/catalog/v1/oauth/tokens \
  --user root:s3cr3t \
  -H "Polaris-Realm: POLARIS" \
  -d grant_type=client_credentials \
  -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)

kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -v -X POST http://localhost:8181/api/management/v1/catalogs \
  -H "Polaris-Realm: POLARIS" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d "{\"type\":\"INTERNAL\",\"name\":\"${POLARIS_CATALOG_NAME}\",\"properties\":{\"default-base-location\":\"${S3_BUCKET}\"},\"createTimestamp\":0,\"lastUpdateTimestamp\":0,\"entityVersion\":0,\"storageConfigInfo\":{\"stsUnavailable\":\"true\",\"region\":\"${STORAGE_REGION}\",\"endpoint\":\"${MINIO_ENDPOINT}\",\"pathStyleAccess\":true,\"storageType\":\"S3\",\"allowedLocations\":[\"${S3_BUCKET}\"]}}"

kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET http://localhost:8181/api/management/v1/catalogs \
  -H "Authorization: Bearer $TOKEN" | jq


# === Troubleshooting ===

# You might need to change the storage settings in the polaris/helm/polaris/values.yaml file if you see the pod pending due to PVC claim error
# storage:
#       # -- The storage class name of the persistent volume claim to create.
#       className: hostpath # standard, default or whatever class name is required
#       # -- The size of the persistent volume claim to create.
#       size: 1Gi

# If the Polaris pod can't pull the image because of the Never policy, edit image.pullPolicy in helm/polaris/ci/persistence-values.yaml

# View tables in the catalog
# kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET http://localhost:8181/api/catalog/v1/${POLARIS_CATALOG_NAME}/namespaces/redpanda/tables \
#  -H "Authorization: Bearer $TOKEN" | jq

# View a table's metadata
# kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET http://localhost:8181/api/catalog/v1/${POLARIS_CATALOG_NAME}/namespaces/redpanda/tables/<table_name> \
# -H "Authorization: Bearer $TOKEN" | jq

# Delete a catalog (requires emptying first)

# CATALOG_NAME="${POLARIS_CATALOG_NAME}"
# echo "Enumerating namespaces in catalog: $CATALOG_NAME"
# NAMESPACES=$(kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET \
#   "http://localhost:8181/api/catalog/v1/$CATALOG_NAME/namespaces" \
#   -H "Authorization: Bearer $TOKEN" | jq -r '.namespaces[].namespace | join(".")')
#
# for NS in $NAMESPACES; do
#   echo "Processing namespace: $NS"
#
#   # Get all tables in the namespace
#   TABLES=$(kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X GET \
#     "http://localhost:8181/api/catalog/v1/$CATALOG_NAME/namespaces/$NS/tables" \
#     -H "Authorization: Bearer $TOKEN" | jq -r '.identifiers[]?.name // empty')
#
#   # Delete each table
#   for TABLE in $TABLES; do
#     echo "  Deleting table: $NS.$TABLE"
#     kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X DELETE \
#       "http://localhost:8181/api/catalog/v1/$CATALOG_NAME/namespaces/$NS/tables/$TABLE?purgeRequested=true" \
#       -H "Authorization: Bearer $TOKEN"
#   done
# done
#
# # Delete all namespaces
# for NS in $NAMESPACES; do
#   echo "Deleting namespace: $NS"
#   kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X DELETE \
#     "http://localhost:8181/api/catalog/v1/$CATALOG_NAME/namespaces/$NS" \
#     -H "Authorization: Bearer $TOKEN"
# done
#
# # Finally delete the catalog
# echo "Deleting catalog: $CATALOG_NAME"
# kubectl exec $POLARIS_POD -n ${POLARIS_NAMESPACE} -- curl -s -X DELETE \
#   "http://localhost:8181/api/management/v1/catalogs/$CATALOG_NAME" \
#   -H "Authorization: Bearer $TOKEN" | jq

# Sources:
# https://github.com/apache/polaris/tree/main/helm/polaris
# https://github.com/redpanda-data-blog/demos-iceberg-topics/blob/main/setup.sh
# 