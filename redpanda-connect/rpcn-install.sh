helm repo add redpanda https://charts.redpanda.com
helm repo update
kubectl create namespace redpanda-connect
# helm upgrade --install redpanda-connect-generate-text redpanda/connect --namespace redpanda-connect --values pipeline.yaml
helm upgrade --install redpanda-connect-weather redpanda/connect --namespace redpanda-connect --values weather.yaml

# helm uninstall redpanda-connect-generate-text --namespace redpanda-connect
# helm uninstall redpanda-connect-weather --namespace redpanda-connect
