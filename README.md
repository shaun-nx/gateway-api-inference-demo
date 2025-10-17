[![Project Status: Concept – Minimal or no implementation has been done yet, or the repository is only intended to be a limited example, demo, or proof-of-concept.](https://www.repostatus.org/badges/latest/concept.svg)](https://www.repostatus.org/#concept)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/shaun-nx/gateway-api-inference-demo/badge)](https://securityscorecards.dev/viewer/?uri=github.com/shaun-nx/gateway-api-inference-demo)
[![Community Support](https://badgen.net/badge/support/community/cyan?icon=awesome)](/SUPPORT.md)
[![Community Forum](https://img.shields.io/badge/community-forum-009639?logo=discourse&link=https%3A%2F%2Fcommunity.nginx.org)](https://community.nginx.org)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/license/apache-2-0)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](/CODE_OF_CONDUCT.md)

# Gateway API Inference Extension demo with NGINX Gateway Fabric

This repo provides example deployment manifests and automation to use the Kubernetes Gateway API Inference Extension with NGINX Gateway Fabric (NGF) as the Gateway Controller.

The examples follow and reference the upstream guide:
- Gateway API Inference Extension How-to with NGF: https://github.com/bjee19/documentation/blob/abbda1fab5bfc4b534e6776bfe02ebc67d3bac4c/content/ngf/how-to/gateway-api-inference-extension.md

Important status notes:
- The Gateway API Inference Extension is alpha and should not be used in production.
- The Endpoint Picker Extension currently communicates without TLS; use only in non-production environments.

## Repository contents

- manifests/gateway.yaml — Gateway resource for NGF
- manifests/httproute.yaml — HTTPRoute that targets an InferencePool
- Makefile — Convenience targets to install CRDs, deploy NGF, vLLM simulator, InferencePool + Endpoint Picker, Gateway/Route, test traffic, and cleanup
- LICENSE — Apache 2.0

## Prerequisites

- A Kubernetes cluster and kubectl context set to your target cluster
  - A LoadBalancer-capable environment (e.g., cloud provider, kind with LB, minikube with tunnel) is recommended for testing via external IP
- kubectl v1.27+ (kubectl includes kustomize integration)
- helm v3.11+ 
- Network egress to pull images and the Helm OCI chart

Optional version tuning via environment variables (defaults shown):
- NGF_REF=main — branch/tag used to fetch NGF inference CRDs and deploy manifest
- GATEWAY_API_CRDS_VERSION=v1.2.0 — Gateway API CRDs version
- IGW_CHART_VERSION=v1.0.1 — InferencePool chart version

Example:
- NGF_REF=v1.X.Y make install-inference-crds install-ngf

## Quick start (Makefile-driven)

This path automates the upstream guide’s steps.

1) Install CRDs, NGF with inference extension, simulator, InferencePool+EPP, Gateway, Route:
- make all

2) Inspect gateway and route status:
- make status-gateway
- make status-route

3) Discover the external address (if using LoadBalancer):
- make print-gateway-address
  - If needed, manually inspect: kubectl get svc -n nginx-gateway

4) Send a test request:
- GW_IP=XXX.YYY.ZZZ.III GW_PORT=80 make test-curl

5) Cleanup (best effort):
- make cleanup

See Makefile for granular targets.

## Manual step-by-step (matching upstream guide)

These commands mirror the referenced how-to.

1) Install core Gateway API CRDs:
- kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

2) Install the Gateway API Inference Extension CRDs:
- kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/inference-extension/?ref=vX.Y.Z" | kubectl apply -f -
  - Replace vX.Y.Z with the desired NGF release version. The Makefile uses NGF_REF (default: main).

3) Install NGINX Gateway Fabric with the Inference Extension enabled:
- kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/main/deploy/inference/deploy.yaml
  - This manifest sets the --gateway-api-inference-extension flag and includes RBAC rules for inferencepools as per the upstream doc.
  - Alternative (Helm): set value nginxGateway.gwAPIInferenceExtension.enable=true when installing NGF.

4) Deploy a sample model server (vLLM simulator; CPU only):
- kubectl apply -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/vllm/sim-deployment.yaml

5) Install an InferencePool and the Endpoint Picker Extension via Helm:
- export IGW_CHART_VERSION=v1.0.1
- helm install vllm-llama3-8b-instruct \
  --set inferencePool.modelServers.matchLabels.app=vllm-llama3-8b-instruct \
  --version $IGW_CHART_VERSION \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool

6) Verify the Endpoint Picker deployment:
- kubectl describe deployment vllm-llama3-8b-instruct-epp

7) Create an Inference Gateway:
- kubectl apply -f manifests/gateway.yaml
- kubectl describe gateway inference-gateway
  - Wait for Programmed=True and capture the external IP and port of the NGF Service if using a LoadBalancer.

8) Deploy an HTTPRoute that targets the InferencePool:
- kubectl apply -f manifests/httproute.yaml
- kubectl describe httproute llm-route
  - Confirm Accepted=True and ResolvedRefs=True in status.

9) Send traffic:
- curl -i $GW_IP:$GW_PORT/v1/completions -H 'Content-Type: application/json' -d '{
"model": "food-review-1",
"prompt": "Write as if you were a critic: San Francisco",
"max_tokens": 100,
"temperature": 0
}'

10) Cleanup:
- helm uninstall vllm-llama3-8b-instruct
- kubectl delete -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/inferenceobjective.yaml --ignore-not-found
- kubectl delete -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/vllm/cpu-deployment.yaml --ignore-not-found
- kubectl delete -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/vllm/gpu-deployment.yaml --ignore-not-found
- kubectl delete -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/raw/main/config/manifests/vllm/sim-deployment.yaml --ignore-not-found
- kubectl delete gateway inference-gateway
- kubectl delete httproute llm-route
- kubectl delete -k https://github.com/kubernetes-sigs/gateway-api-inference-extension/config/crd --ignore-not-found
- helm uninstall ngf -n nginx-gateway || true
- kubectl delete ns nginx-gateway || true
- kubectl delete -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/vX.Y.Z/deploy/crds.yaml || true
- kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml || true

Tip: The Makefile target make cleanup performs best-effort cleanup across these resources.

## Makefile targets

Key targets:
- prerequisites — verify kubectl and helm are installed
- install-gateway-api-crds — core Gateway API CRDs
- install-inference-crds — Gateway API Inference Extension CRDs
- install-ngf — NGF with inference extension (manifests)
- deploy-model-sim — vLLM simulator
- install-inferencepool — InferencePool + Endpoint Picker (Helm OCI)
- deploy-gateway — apply manifests/gateway.yaml
- deploy-httproute — apply manifests/httproute.yaml
- status-gateway — describe Gateway
- status-route — describe HTTPRoute
- print-gateway-address — helper to discover NGF Service IP
- test-curl — send example completion request
- cleanup — best-effort removal of resources/CRDs/NGF

Examples:
- make all
- GW_IP=1.2.3.4 GW_PORT=80 make test-curl
- make cleanup

## References

- Introducing Gateway API Inference Extension: https://kubernetes.io/blog/2025/06/05/introducing-gateway-api-inference-extension/
- Deep dive into the Inference Extension: https://kgateway.dev/blog/deep-dive-inference-extensions/
- NGF Inference Extension Design Proposal: https://github.com/nginx/nginx-gateway-fabric/blob/main/docs/proposals/gateway-inference-extension.md
- NGF Inference Extension Epic: https://github.com/nginx/nginx-gateway-fabric/issues/3644
- Upstream NGF How-to (basis for this repo): https://github.com/bjee19/documentation/blob/abbda1fab5bfc4b534e6776bfe02ebc67d3bac4c/content/ngf/how-to/gateway-api-inference-extension.md

## Contributing

Please see the [contributing guide](/CONTRIBUTING.md).

## License

[Apache License, Version 2.0](/LICENSE)

© [F5, Inc.](https://www.f5.com/) 2025
