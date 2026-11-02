#!/usr/bin/env bash
# Asserts that Terraform created what it claims to have created, by asking the cluster.
# Usage: scripts/verify-cluster.sh   (env: NS, APP, CONTEXT, EXPECT_HPA, EXPECT_PDB, EXPECT_NETPOL)
set -euo pipefail

NS="${NS:-devops-lab}"
APP="${APP:-labapi}"
CONTEXT="${CONTEXT:-kind-tfk8s-lab}"
EXPECT_HPA="${EXPECT_HPA:-true}"
EXPECT_PDB="${EXPECT_PDB:-true}"
EXPECT_NETPOL="${EXPECT_NETPOL:-true}"

k() { kubectl --context "$CONTEXT" -n "$NS" "$@"; }
fail=0
check() { # check <description> <actual> <expected>
  if [[ "$2" == "$3" ]]; then
    echo "ok    $1 ($2)"
  else
    echo "FAIL  $1: expected '$3', got '$2'"
    fail=1
  fi
}

desired="$(k get deployment "$APP" -o jsonpath='{.spec.replicas}')"
ready="$(k get deployment "$APP" -o jsonpath='{.status.readyReplicas}')"
check "deployment ready replicas match desired" "${ready:-0}" "$desired"

check "readOnlyRootFilesystem" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}')" "true"
check "allowPrivilegeEscalation" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}')" "false"
check "capabilities drop" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.containers[0].securityContext.capabilities.drop[0]}')" "ALL"
check "runAsNonRoot" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}')" "true"
check "seccomp profile" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}')" "RuntimeDefault"
check "has startup probe" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.containers[0].startupProbe.httpGet.path}')" "/healthz"
check "has liveness probe" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}')" "/healthz"
check "has readiness probe" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}')" "/readyz"
check "cpu limit set" "$(k get deployment "$APP" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}')" "250m"
check "namespace enforces restricted PSA" "$(kubectl --context "$CONTEXT" get namespace "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')" "restricted"
check "service selects pods (endpoints exist)" "$([[ -n "$(k get endpointslices -l "kubernetes.io/service-name=$APP" -o jsonpath='{.items[*].endpoints[*].addresses[0]}')" ]] && echo yes || echo no)" "yes"

if [[ "$EXPECT_HPA" == "true" ]]; then
  check "hpa targets the deployment" "$(k get hpa "$APP" -o jsonpath='{.spec.scaleTargetRef.name}')" "$APP"
  check "hpa API version" "$(k get hpa "$APP" -o jsonpath='{.apiVersion}')" "autoscaling/v2"
fi
if [[ "$EXPECT_PDB" == "true" ]]; then
  check "pdb max unavailable" "$(k get pdb "$APP" -o jsonpath='{.spec.maxUnavailable}')" "1"
fi
if [[ "$EXPECT_NETPOL" == "true" ]]; then
  check "network policies" "$(k get networkpolicy -o name | sort | tr '\n' ' ')" "networkpolicy.networking.k8s.io/default-deny-ingress networkpolicy.networking.k8s.io/${APP}-allow-ingress "
fi

exit "$fail"
