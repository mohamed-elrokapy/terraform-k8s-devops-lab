# Local lab workflow: kind cluster -> image -> terraform apply -> smoke test.
# Prerequisites on PATH: docker, kind, kubectl, terraform (or tofu: `make TF=tofu ...`).

CLUSTER   ?= tfk8s-lab
CONTEXT   ?= kind-$(CLUSTER)
IMAGE     ?= labapi:dev
VERSION   ?= dev
TF        ?= terraform
TF_DIR    := terraform
# The lab runs the app with its built-in DNS table so `make test` needs no network.
# Use `make apply DNS_STUB=false` for real lookups.
DNS_STUB  ?= true
TF_ARGS   ?=
GIT_SHA   := $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)

TF_VARS = -var kube_context=$(CONTEXT) -var image=$(IMAGE) -var app_version=$(VERSION) -var dns_stub=$(DNS_STUB) $(TF_ARGS)

.DEFAULT_GOAL := help
.PHONY: help cluster image apply test destroy lint ingress metrics-server cluster-delete

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

cluster: ## Create the kind cluster (1 control-plane, 1 worker) if it does not exist
	@kind get clusters | grep -qx '$(CLUSTER)' && echo "cluster $(CLUSTER) already exists" \
		|| kind create cluster --config kind/kind-config.yaml --wait 120s

image: ## Build the app image and load it into the kind nodes
	docker build --build-arg APP_VERSION=$(VERSION) --build-arg GIT_SHA=$(GIT_SHA) -t $(IMAGE) app
	kind load docker-image $(IMAGE) --name $(CLUSTER)

apply: ## terraform init + apply against the kind cluster
	$(TF) -chdir=$(TF_DIR) init -input=false
	$(TF) -chdir=$(TF_DIR) apply -input=false -auto-approve $(TF_VARS)

test: ## Verify the cluster objects, then curl the app through kubectl port-forward
	CONTEXT=$(CONTEXT) scripts/verify-cluster.sh
	CONTEXT=$(CONTEXT) scripts/smoke-test.sh

destroy: ## terraform destroy (leaves the kind cluster in place)
	$(TF) -chdir=$(TF_DIR) destroy -input=false -auto-approve $(TF_VARS)

cluster-delete: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

lint: ## ruff, pytest, terraform fmt/validate, plus hadolint/tflint/trivy when installed
	cd app && ruff check . && ruff format --check . && python -m pytest
	$(TF) -chdir=$(TF_DIR) fmt -check -recursive
	$(TF) -chdir=$(TF_DIR) init -backend=false -input=false
	$(TF) -chdir=$(TF_DIR) validate
	@if command -v hadolint >/dev/null; then hadolint app/Dockerfile; else echo "skip hadolint (not installed)"; fi
	@if command -v tflint >/dev/null; then tflint --chdir=$(TF_DIR) --recursive; else echo "skip tflint (not installed)"; fi
	@if command -v trivy >/dev/null; then trivy config --severity HIGH,CRITICAL --exit-code 1 $(TF_DIR) app/Dockerfile; else echo "skip trivy (not installed)"; fi

ingress: ## Optional: install ingress-nginx for kind, pinned to the port-mapped node
	kubectl --context $(CONTEXT) apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/kind/deploy.yaml
	kubectl --context $(CONTEXT) -n ingress-nginx patch deployment ingress-nginx-controller --type merge \
		-p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"}}}}}'
	kubectl --context $(CONTEXT) -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
	@echo "Now: make apply TF_ARGS='-var enable_ingress=true' && curl http://lab.localtest.me:8081/healthz"

metrics-server: ## Optional: install metrics-server (needed for the HPA to act) with kind's insecure kubelet TLS flag
	kubectl --context $(CONTEXT) apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml
	kubectl --context $(CONTEXT) -n kube-system patch deployment metrics-server --type json \
		-p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
	kubectl --context $(CONTEXT) -n kube-system rollout status deployment/metrics-server --timeout=120s
