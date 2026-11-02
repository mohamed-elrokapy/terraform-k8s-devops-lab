# terraform-k8s-devops-lab

[![CI](https://github.com/mohamed-elrokapy/terraform-k8s-devops-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/mohamed-elrokapy/terraform-k8s-devops-lab/actions/workflows/ci.yml)

A small learning lab: a tiny FastAPI service deployed to a local Kubernetes (kind) cluster with Terraform, with the checks a reviewer would expect around it (lint, tests, image build, IaC validation, a real end-to-end run in CI).

It is a lab, not a production platform. I wrote it to learn the Terraform and Kubernetes workflow end to end, coming from Linux administration, DNS/SSL, Docker Compose and GitHub Actions. The service does DNS lookups because that is the area I know best.

## What is in the repo

```
app/                 FastAPI service, tests, pinned requirements, non-root multi-stage Dockerfile
terraform/           Root module (provider + variables) and modules/app (the Kubernetes objects)
kind/                kind cluster config: 1 control-plane, 1 worker, ingress-ready port mappings
scripts/             verify-cluster.sh (asks the cluster), smoke-test.sh (curl via port-forward)
.github/workflows/   ci.yml
docs/ARCHITECTURE.md Diagram, decisions and trade-offs, what production would add
Makefile             cluster, image, apply, test, destroy, lint (+ ingress, metrics-server)
```

The service exposes `/healthz`, `/readyz`, `/version`, `/api/dns?domain=example.com` (A, MX and TXT via dnspython, short timeout, input validation) and Prometheus-style `/metrics`.

Terraform creates a namespace (Pod Security `restricted`), ConfigMap, Deployment (requests/limits, startup/liveness/readiness probes, non-root, read-only root filesystem, all capabilities dropped, seccomp `RuntimeDefault`, topology spread), Service, HorizontalPodAutoscaler (`autoscaling/v2`), PodDisruptionBudget, a default-deny ingress NetworkPolicy with an allow rule, and an optional nginx Ingress. The cluster is chosen by a kubeconfig path and context, so the same code can target any cluster.

## Quickstart

Prerequisites: Docker, [kind](https://kind.sigs.k8s.io/), kubectl, Terraform 1.6 or newer (OpenTofu works with `make TF=tofu ...`).

```sh
make cluster   # kind cluster "tfk8s-lab" (1 control-plane, 1 worker)
make image     # docker build + kind load docker-image
make apply     # terraform init + apply (the app runs with its built-in DNS table, see below)
make test      # verify the objects with kubectl, then curl the app through port-forward
make destroy   # terraform destroy; "make cluster-delete" removes the cluster
```

Try it by hand:

```sh
kubectl -n devops-lab port-forward svc/labapi 8080:80 &
curl -s localhost:8080/version
curl -s 'localhost:8080/api/dns?domain=example.com'
```

Notes:

- `make apply` sets `dns_stub=true` so the lab works offline. For real lookups use `make apply DNS_STUB=false`.
- After rebuilding the image under the same tag, run `kubectl -n devops-lab rollout restart deployment/labapi`; Terraform sees no change.
- To deploy to another cluster, copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and set `kubeconfig_path`, `kube_context` and `image` (a pushed image with an explicit tag; `:latest` is rejected by validation).
- Optional extras: `make metrics-server` (the HPA only acts when metrics-server runs; kind does not ship it) and `make ingress` followed by `make apply TF_ARGS='-var enable_ingress=true'`, then `curl http://lab.localtest.me:8081/healthz`.
- If `kind load docker-image` fails with a "content digest not found" error on a Docker setup that uses the containerd image store, load the image through an archive instead: `docker save labapi:dev -o /tmp/labapi.tar && kind load image-archive /tmp/labapi.tar --name tfk8s-lab`.
- `make lint` needs the Python dev tools (`pip install -r app/requirements-dev.txt`); it also runs hadolint, tflint and trivy if they are installed.

## What CI runs

The workflow in `.github/workflows/ci.yml` runs on pushes to `main`, pull requests and manual dispatch, with `contents: read` permissions only. Results are on the Actions tab.

1. **app**: ruff (lint and format check), pytest, hadolint on the Dockerfile, an image build, and a container start with `--read-only --cap-drop ALL` that checks the process runs as UID 10001 and answers `/healthz` and `/api/dns`.
2. **iac**: `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`, tflint, and `trivy config` on `terraform/` and the Dockerfile (fails on HIGH or CRITICAL; there is no ignore file).
3. **e2e** (after the first two): creates a kind cluster (helm/kind-action), builds the image and loads it into kind, runs `terraform apply`, waits for the rollout, then
   - checks the created objects with kubectl (probes, security context, PSA label, HPA, PDB, NetworkPolicies, Service endpoints),
   - smoke-tests the app through `kubectl port-forward`, including the DNS behaviour using the built-in stub table (existing name, name with only an A record, NXDOMAIN, simulated timeout, invalid input),
   - runs `trivy config` on the live Deployment and Service exported as YAML,
   - runs `terraform plan -detailed-exitcode` to check there is no drift after apply,
   - runs `terraform destroy` and checks the namespace is gone.

Action versions are pinned by major tag. Trivy and hadolint are installed from pinned releases with a SHA-256 check instead of through a third-party action.

## Verification status

The first CI run on `main` passed every step: [run 41405224530](https://github.com/mohamed-elrokapy/terraform-k8s-devops-lab/actions/runs/41405224530). That covers ruff and pytest, hadolint, the image build with a non-root, read-only-filesystem check, `terraform fmt`/`init`/`validate`, tflint, `trivy config`, a kind cluster, `terraform apply`, rollout under the `restricted` Pod Security level, the smoke test through port-forward, a Trivy scan of the live Deployment and Service, a no-drift `terraform plan`, `terraform destroy` and a check that the namespace is gone.

Before that run, the app tests and the linters had been run locally on Python 3.12 and 3.13 (34 tests). Docker, kind and a real `terraform apply` ran only in CI.

## What is NOT done

- No cloud account or cloud resources. Everything runs on a local or CI-hosted kind cluster.
- No TLS. The optional Ingress is plain HTTP, and ingress-nginx itself is retired upstream, so it is a lab convenience only.
- No real secrets and therefore no Secret resource. There is no secret management to show.
- No remote Terraform state. State is a local file, which is fine for a throwaway cluster and wrong for a team. `.terraform.lock.hcl` is not committed yet.
- Autoscaling is configured but not exercised: kind has no metrics-server by default, and CI does not install it, so the HPA object is created and checked but never scales. With one worker node the topology spread and the PDB cannot show their effect either.
- The NetworkPolicies are created and checked for shape, but enforcement depends on the CNI and no test sends blocked traffic.
- The real DNS resolver path is covered by unit tests with a mocked dnspython only. The cluster test uses the stub table.
- `/api/dns` has no authentication or rate limiting. Do not expose it to the internet.
- No image registry, signing or SBOM; images are built locally and loaded into kind.

## Design notes

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the diagram, the trade-offs behind the choices (why kind, why a local module, why `ignore_changes` on replicas, and so on) and what a production setup would add.

## Notes

Written with AI assistance (Claude, Anthropic) at the direction of the repository owner. The code, tests and CI were generated in that process; CI results are linked from the Actions tab.
