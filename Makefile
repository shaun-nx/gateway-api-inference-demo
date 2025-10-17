# Makefile for Gateway API Inference Extension demo with NGINX Gateway Fabric
# This Makefile provides convenient targets to install prerequisites, deploy the
# vLLM simulator, install an InferencePool + Endpoint Picker, deploy a Gateway and
# HTTPRoute, test traffic, and clean up resources.
#
# References:
# - Gateway API Inference Extension: https://gateway-api-inference-extension.sigs.k8s.io/
# - NGF inference deploy manifest: https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/main/deploy/inference/deploy.yaml
# - vLLM simulator manifest: https://github.com/kubernetes-sigs/gateway-api-inference-extension/tree/main/config/manifests/vllm

SHELL := /bin/bash

# Versions and URLs (override via environment if needed)
IGW_CHART_VERSION ?= v1.0.1
NGF_REF ?= main
# Gateway API CRDs (standard install)
GATEWAY_API_CRDS_VERSION ?= v1.2.0
GATEWAY_API_CRDS_URL ?= https://github.com/kubernetes-sigs/gateway-api/releases/download/$(GATEWAY_API_CRDS_VERSION)/standard-install.yaml
# Inference Extension CRDs (kustomize)
INFERENCE_CRDS_KUSTOMIZE_URL ?= https://github.com/nginx/nginx-gateway-fabric/config/crd/inference-extension/?ref=$(NGF_REF)
# NGF deployment manifest with inference extension enabled + RBAC updates
NGF_DEPLOY_URL ?= https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/main/deploy/inference/deploy.yaml
# vLLM simulator (CPU, no GPU needed)
VLLM_SIM_URL ?= https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/vllm/sim-deployment.yaml
# Optional additional manifests used in cleanup
INFERENCE_OBJECTIVE_URL ?= https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/inferenceobjective.yaml
VLLM_CPU_URL ?= https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/vllm/cpu-deployment.yaml
VLLM_GPU_URL ?= https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/vllm/gpu-deployment.yaml

# Namespace for Gateway/HTTPRoute (default namespace by default)
NS ?= default

.PHONY: help
help:
	@echo "Targets:"
	@echo "  prerequisites                 - Verify kubectl and helm are installed"
	@echo "  install-gateway-api-crds      - Install core Gateway API CRDs (standard-install)"
	@echo "  install-inference-crds        - Install Gateway API Inference Extension CRDs (kustomize)"
	@echo "  install-ngf                   - Install NGINX Gateway Fabric with Inference Extension enabled (manifests)"
	@echo "  deploy-model-sim              - Deploy vLLM simulator model server"
	@echo "  install-inferencepool         - Install InferencePool + Endpoint Picker via Helm (OCI)"
	@echo "  deploy-gateway                - Apply manifests/gateway.yaml"
	@echo "  deploy-httproute              - Apply manifests/httproute.yaml"
	@echo "  status-gateway                - Describe the Gateway resource"
	@echo "  status-route                  - Describe the HTTPRoute resource"
	@echo "  print-gateway-address         - Print the NGF Service external address (if using LoadBalancer)"
	@echo "  test-curl                     - Send a test request (requires GW_IP set, optional GW_PORT)"
	@echo "  all                           - Run the full setup (up to printing gateway address)"
	@echo "  cleanup                       - Remove example resources, CRDs, and NGF (best-effort)"
	@echo ""
	@echo "Variables (override as needed):"
	@echo "  IGW_CHART_VERSION (default: $(IGW_CHART_VERSION))"
	@echo "  NGF_REF           (default: $(NGF_REF))"
	@echo "  GATEWAY_API_CRDS_VERSION (default: $(GATEWAY_API_CRDS_VERSION))"
	@echo "  NS               (default: $(NS))"
	@echo ""
	@echo "Usage examples:"
	@echo "  make all"
	@echo "  GW_IP=1.2.3.4 GW_PORT=80 make test-curl"
	@echo "  make cleanup"

.PHONY: prerequisites
prerequisites:
	@command -v kubectl >/dev/null 2>&1 || { echo >&2 "kubectl is required but not found."; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo >&2 "helm is required but not found."; exit 1; }
	@echo "kubectl and helm detected."

.PHONY: install-gateway-api-crds
install-gateway-api-crds:
	kubectl apply -f "$(GATEWAY_API_CRDS_URL)"

.PHONY: install-inference-crds
install-inference-crds:
	kubectl kustomize "$(INFERENCE_CRDS_KUSTOMIZE_URL)" | kubectl apply -f -

.PHONY: install-ngf
install-ngf:
	kubectl apply -f "$(NGF_DEPLOY_URL)"

.PHONY: deploy-model-sim
deploy-model-sim:
	kubectl apply -f "$(VLLM_SIM_URL)"

.PHONY: install-inferencepool
install-inferencepool:
	helm install vllm-llama3-8b-instruct \
		--set inferencePool.modelServers.matchLabels.app=vllm-llama3-8b-instruct \
		--version "$(IGW_CHART_VERSION)" \
		oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool

.PHONY: deploy-gateway
deploy-gateway:
	kubectl apply -f manifests/gateway.yaml

.PHONY: deploy-httproute
deploy-httproute:
	kubectl apply -f manifests/httproute.yaml

.PHONY: status-gateway
status-gateway:
	-kubectl describe gateway -n "$(NS)" inference-gateway

.PHONY: status-route
status-route:
	-kubectl describe httproute -n "$(NS)" llm-route

.PHONY: print-gateway-address
print-gateway-address:
	@echo "Trying to detect NGF Service external address (namespace: nginx-gateway):"
	-@kubectl get svc -n nginx-gateway -l app=nginx-gateway -o wide
	@echo "External IP (if any):"
	-@kubectl get svc -n nginx-gateway -l app=nginx-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'; echo
	@echo "Alternatively, set GW_IP and GW_PORT then run: make test-curl"

.PHONY: test-curl
test-curl:
	@if [ -z "$$GW_IP" ]; then echo "Set GW_IP (and optionally GW_PORT) before running this target."; exit 1; fi
	@PORT=$${GW_PORT:-80}; \
	echo "Sending request to $$GW_IP:$$PORT/v1/completions ..."; \
	curl -i "$$GW_IP:$$PORT/v1/completions" -H 'Content-Type: application/json' -d '{\
"model": "food-review-1",\
"prompt": "Write as if you were a critic: San Francisco",\
"max_tokens": 100,\
"temperature": 0\
}'

.PHONY: all
all: prerequisites install-gateway-api-crds install-inference-crds install-ngf deploy-model-sim install-inferencepool deploy-gateway deploy-httproute status-gateway status-route print-gateway-address

# Cleanup targets (best effort)
.PHONY: uninstall-inference
uninstall-inference:
	-helm uninstall vllm-llama3-8b-instruct
	-kubectl delete -f "$(INFERENCE_OBJECTIVE_URL)" --ignore-not-found
	-kubectl delete -f "$(VLLM_CPU_URL)" --ignore-not-found
	-kubectl delete -f "$(VLLM_GPU_URL)" --ignore-not-found
	-kubectl delete -f "$(VLLM_SIM_URL)" --ignore-not-found

.PHONY: uninstall-inference-crds
uninstall-inference-crds:
	-kubectl delete -k https://github.com/kubernetes-sigs/gateway-api-inference-extension/config/crd --ignore-not-found

.PHONY: uninstall-gateway
uninstall-gateway:
	-kubectl delete -f manifests/httproute.yaml --ignore-not-found
	-kubectl delete -f manifests/gateway.yaml --ignore-not-found

.PHONY: uninstall-ngf
uninstall-ngf:
	# If installed via Helm with release 'ngf' (namespace nginx-gateway)
	-helm uninstall ngf -n nginx-gateway
	# If installed via manifests
	-kubectl delete -f "$(NGF_DEPLOY_URL)" --ignore-not-found
	# Remove namespace and NGF CRDs (best effort)
	-kubectl delete ns nginx-gateway || true
	-kubectl delete -f "https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/$(NGF_REF)/deploy/crds.yaml" || true

.PHONY: uninstall-gateway-api-crds
uninstall-gateway-api-crds:
	-kubectl delete -f "$(GATEWAY_API_CRDS_URL)" || true

.PHONY: cleanup
cleanup: uninstall-inference uninstall-inference-crds uninstall-gateway uninstall-ngf uninstall-gateway-api-crds
	@echo "Cleanup complete (best effort)."
