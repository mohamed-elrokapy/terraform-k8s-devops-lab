#!/usr/bin/env bash
# HTTP smoke test through `kubectl port-forward` (no ingress controller needed).
# Usage: scripts/smoke-test.sh   (env: NS, APP, CONTEXT, LOCAL_PORT)
# If the app runs with DNS_STUB=true (the default for `make apply`), the DNS assertions are exact.
set -euo pipefail

NS="${NS:-devops-lab}"
APP="${APP:-labapi}"
CONTEXT="${CONTEXT:-kind-tfk8s-lab}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
BASE="http://127.0.0.1:${LOCAL_PORT}"

kubectl --context "$CONTEXT" -n "$NS" port-forward "svc/${APP}" "${LOCAL_PORT}:80" >/tmp/port-forward.log 2>&1 &
pf_pid=$!
trap 'kill "$pf_pid" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "${BASE}/healthz" 2>/dev/null; then break; fi
  sleep 1
done

fail=0
# expect <description> <path> <expected status> <expected substring>
expect() {
  local body status
  body="$(mktemp)"
  status="$(curl -sS -o "$body" -w '%{http_code}' "${BASE}$2")"
  if [[ "$status" == "$3" ]] && grep -qF -- "$4" "$body"; then
    echo "ok    $1 -> $status"
  else
    echo "FAIL  $1: wanted $3 containing '$4', got $status: $(head -c 300 "$body")"
    fail=1
  fi
  rm -f "$body"
}

expect "healthz"        "/healthz" 200 '"status":"ok"'
expect "readyz"         "/readyz"  200 '"status":"ready"'
expect "version"        "/version" 200 '"version"'
expect "invalid domain" "/api/dns?domain=not_a_domain" 422 'detail'
expect "missing domain" "/api/dns" 422 'detail'

if curl -fsS "${BASE}/version" | grep -q '"dns_stub":true'; then
  expect "dns: all record types" "/api/dns?domain=example.com" 200 '"A":["192.0.2.10"]'
  expect "dns: mx present"       "/api/dns?domain=example.com" 200 '"MX":["10 mail.example.com."]'
  expect "dns: name with only an A record" "/api/dns?domain=a-only.example.com" 200 '"MX":[],"TXT":[]'
  expect "dns: nxdomain structure" "/api/dns?domain=missing.invalid" 200 '"status":"nxdomain"'
  expect "dns: timeout maps to 504" "/api/dns?domain=slow.example.com" 504 'timed out'
else
  echo "skip  dns assertions: app is not running with DNS_STUB=true"
fi

expect "metrics: request counter" "/metrics" 200 'http_requests_total{method="GET",route="/healthz",status="200"}'
expect "metrics: build info"      "/metrics" 200 'app_build_info'

exit "$fail"
