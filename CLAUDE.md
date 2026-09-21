# CLAUDE.md — ABC Technologies CI/CD Project

## Project overview
- **Name**: ABC Technologies
- **What it does**: CI/CD pipeline for a retail company's Java servlet application. ABC Technologies (online retail) acquired an offline retail business running on conventional, slow, fragile deployment practices. Phase 1 scope: servlets for **Add Product** and **Display Product Details**, plus an HTML landing page. Source lives in GitHub at `github.com/Khanduri004/ABC_Tech_AI`.
- **Status**: Core app code and infra written; Docker build/K8s deploy verification in progress.
- **App architecture**: `RetailModule` (POJO: product_id, product_name, product_description, price) → `RetailAccessObject` interface → `RetailDataImp` (in-memory `HashMap`, NOT a real database) → `SharedDataStore` (single static shared DAO instance across servlets) → `AddProductServlet` (`POST /addProduct`) and `DisplayProductServlet` (`GET /displayProduct`).
- **Known limitation**: the in-memory DAO cannot support more than 1 replica (each pod would have separate, inconsistent state). Running at 1 replica until a real shared datastore (DB or Redis) is added — see Goal #1.

## Goals (translated from the business challenge into build decisions)

1. **High availability** (was: "low available")
   - EKS worker nodes spread across ≥2 AZs (eu-west-1a/1b), provisioned via Terraform
   - **TEMPORARY: running at 1 replica** — in-memory DAO breaks with >1 replica. Revisit to 2+ once a real shared datastore is added.
   - Liveness/readiness probes on the servlet endpoints (`initialDelaySeconds: 20` on liveness — Tomcat/JVM needs real startup time before health checks begin, or Kubernetes kills a healthy-but-still-starting pod)
   - Target once multi-replica: 99.9% availability via ≥2 replicas across ≥2 AZs with automatic pod rescheduling

2. **High scalability** (was: "low scalable")
   - Horizontal Pod Autoscaler on CPU (scale 2→6 replicas at 70% CPU) — deferred until multi-replica is viable (see Goal #1)
   - Cluster Autoscaler on the EKS node group (Terraform-managed)
   - Designed to absorb a 5–10x traffic spike (retail sales-event pattern), validated via load test (k6/JMeter), not live metrics

3. **High performance** (was: "low Performance")
   - Target: p95 response time under 300ms for Display Product under simulated load
   - No caching layer unless load testing shows it's needed — stretch goal, not core requirement

4. **Easily built and maintained** (was: "Hard built and maintained")
   - Reproducible build via Maven, Java 17 target (`maven.compiler.release=17`)
   - Multi-stage Dockerfile: Maven build stage → Tomcat runtime stage (servlets need a servlet container, not a bare JRE)
   - Clear separation: `app/` (application code) / `terraform/` (infra) / `k8s/` (deployment) as top-level, sibling folders

5. **Fast development & deployment** (was: "time consuming")
   - Pipeline flow: GitHub push → Jenkins build+test → Docker image built and pushed to Docker Hub → Jenkins applies K8s manifests (`kubectl`) to the EKS cluster Terraform provisioned
   - Terraform runs separately (infra changes only, not per app deploy)
   - Target: full app pipeline under 10–15 minutes
   - Manual approval gate before "production" namespace

## Tech stack & versions

**IaC**: Terraform v1.15.x. Files in `terraform/`: `provider.tf`, `vpc.tf`, `eks.tf`, `ec2.tf`, `variables.tf`, `outputs.tf`
**Terraform state**: local (`terraform.tfstate`, gitignored) — no remote backend (S3 deliberately deferred)

**App build**: Maven, `app/pom.xml` (war packaging, `jakarta.servlet-api:6.0.0` scope=provided — MUST match Tomcat 10.1's Servlet 6.0 spec; wrong version = compile or deploy failures)

**Containers**: Docker — multi-stage Dockerfile at repo root (NOT inside `app/`):
- Build stage: `maven:3.9.9-eclipse-temurin-17`
- Runtime stage: `tomcat:10.1-jre17-temurin`, WAR copied in as `ROOT.war` (serves at `/`, not a sub-path)

**Orchestration**: Kubernetes (EKS) v1.34. Local pre-flight testing via `kind` before touching real EKS.

K8s manifests — folder is `k8s/` (not `k8ns/` — this exact typo happened once already):
- Phase 1 scope: `namespace.yaml`, `deployment.yaml` (replicas: 1, see Goal #1), `service.yaml`, `hpa.yaml` (add once multi-replica), `ingress-nginx.yaml` (local/kind), `ingress-alb.yaml` (production EKS — requires AWS Load Balancer Controller installed separately via Helm+IRSA first)
- Practice only, not required by Phase 1 (`k8s/practice/`): `cron_job.yaml`, `persistent_volume.yaml`, `persistent_volume_claim.yaml`

**CI/CD**: Jenkins v2.581+ (Jenkinsfile at repo root). **Requires Java 21 minimum** — separate from the app's Java 17 target. Both JDKs installed side by side; `update-alternatives` points default `java` at 21 for Jenkins.

**Monitoring**: Prometheus + Grafana — config under `monitoring/` (not yet built)

**Languages**: Python3, Bash — `install_tools.sh` installs everything on the CI/CD EC2 instance (see corrected version — this file failed 3 separate times during setup; see decision log)

**Cloud**: AWS, region eu-west-1
- EC2 #1 — Jenkins + Docker + dev environment (same box; solo-project simplification, stated explicitly rather than accidental), IAM role attached for AWS/EKS API access, sized `t3.small`
- EKS managed node group — runs app pods, sized `t3.micro` **temporarily** (new-account Free Tier restriction blocked `t3.medium`; revert once lifted)
- VPC: public subnets only (no NAT Gateway, saves ~$32-35/month), compensated with restrictive Security Groups (SSH + Jenkins UI restricted to your current IP via `allowed_ssh_cidr`, not `0.0.0.0/0`)
- No S3 bucket — deferred, using local Terraform state

## Repo structure
```
.
├── terraform/
│   ├── provider.tf
│   ├── vpc.tf
│   ├── eks.tf
│   ├── ec2.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars        # gitignored — allowed_ssh_cidr, key_pair_name, eks_node_instance_type overrides
├── app/
│   ├── pom.xml
│   └── src/
│       ├── main/
│       │   ├── java/com/abc/
│       │   │   ├── RetailModule.java
│       │   │   ├── SharedDataStore.java
│       │   │   ├── AddProductServlet.java
│       │   │   ├── DisplayProductServlet.java
│       │   │   └── dataAccessObject/
│       │   │       ├── RetailAccessObject.java
│       │   │       └── RetailDataImp.java
│       │   └── webapp/
│       │       ├── index.jsp
│       │       └── WEB-INF/web.xml    # Servlet 5.0 (Jakarta EE) — NOT the old 2.3 DTD
│       └── test/java/com/abc/dataAccessObject/
│           └── ProductImpTest.java
├── k8s/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress-nginx.yaml
│   ├── ingress-alb.yaml
│   └── practice/
│       ├── cron_job.yaml
│       ├── persistent_volume.yaml
│       └── persistent_volume_claim.yaml
├── monitoring/
├── Dockerfile                    # at repo root — references app/pom.xml and app/src
├── install_tools.sh              # at repo root — see corrected version
├── Jenkinsfile
├── .gitattributes                # forces LF line endings (Windows CRLF broke .sh files once)
├── .gitignore                    # MUST include .terraform/, *.tfstate*, terraform.tfvars, *.pem BEFORE first commit
└── CLAUDE.md
```

## Conventions
- **Naming**: snake_case for Terraform resources/variables; kebab-case for Kubernetes object names/labels
- **Linting/formatting**: `tflint` on all Terraform before commit; `checkov`/`tfsec` optional at this scope
- **Commit messages**: Conventional Commits (`feat:`, `fix:`, `chore:`, `infra:`)
- **Secrets**: never hardcoded. AWS credentials via IAM role (EC2 instance profile), not access keys. App secrets via AWS Secrets Manager or K8s Secrets once needed.
- **Line endings**: `.gitattributes` forces LF — Windows `core.autocrlf` corrupted `.sh` files once already

## How to run things locally
- **Terraform**: `cd terraform && terraform init && terraform plan` → review → `terraform apply`
- **Build the app**: `mvn clean package -DskipTests` (from `app/`)
- **Run tests**: `mvn test` — confirm `ProductImpTest.java` uses JUnit 5 imports (`org.junit.jupiter.api.*`) before relying on the `junit-jupiter` dependency in pom.xml; if it's JUnit 4 style, the dependency needs adjusting
- **Docker build**: from repo root (not `app/`): `docker build -t abc-retail-portal:latest .`
- **Local K8s testing**: `kind create cluster --name abc-local`, `kind load docker-image abc-retail-portal:latest --name abc-local`, then `kubectl apply -f k8s/`
- **Get Jenkins password**: `sudo cat /home/ubuntu/.jenkins/secrets/initialAdminPassword`

## Constraints & non-negotiables
- No hardcoded credentials, ever
- All Terraform changes go through `terraform plan` review before `apply` — no blind applies
- Pipeline must include a manual approval gate before "production" namespace
- Docker images use the multi-stage build — never ship the Maven build image as runtime
- **Any fix made by running commands directly on a live EC2 instance must also be applied to the source script (`install_tools.sh`) in the same session** — a live-only fix disappears the next time the instance is destroyed/recreated. This happened twice in this project before the rule was written down.
- Run `terraform destroy` at the end of every work session unless actively deploying — EKS control plane bills ~$0.10/hr continuously regardless of use

## Working style
- Go file by file / module by module rather than generating everything at once
- Explain the reasoning behind non-obvious infra decisions (need to defend these in interviews)
- Flag security or cost implications of any suggested resource before creating it
- Build every file from scratch — don't assume boilerplate exists unless created in this repo
- **When editing an EXISTING resource/file, edit it in place — do not paste the changed version as a new addition at the end.** This caused duplicate-resource errors twice in this project (`aws_instance "jenkins"`, `aws_eks_cluster "main"`).
- **When omitting an optional field on an existing Terraform resource, understand whether that means "leave as-is" or "reset to default."** The latter can force an unwanted replacement (happened with `access_config` on the EKS cluster) — when in doubt, set every field in a changed block explicitly.
- Any script referencing an external URL, signing key, or "latest" version is a **live dependency** — verify against current docs before trusting it, especially before wiring it into `user_data` where failures cost real wait time
- Manifests must work against both `kind` (local) and EKS (real) — flag anything EKS-specific (AWS-specific StorageClass, LoadBalancer-type Service)
- Ingress: nginx-ingress for local `kind`; AWS Load Balancer Controller for production EKS — keep both manifests, don't replace one with the other
- Before any file-creating or git command in a new terminal session, confirm `pwd` — file-location and git-scope mistakes were the most repeated error class in this project

## Decision log
- 2026-09-08 — Chose Terraform over Ansible for infra provisioning + deployment
- 2026-09-08 — Multi-stage Dockerfile (Maven build → Tomcat runtime) — servlets require a servlet container
- 2026-09-08 — JUnit as test framework, `kind` for local K8s testing before EKS
- 2026-09-08 — nginx-ingress first (local validation), AWS Load Balancer Controller for production — staged rollout
- 2026-09-08 — Deferred S3 bucket / remote Terraform state backend — using local state
- 2026-09-09 — Developing directly on EC2 via SSH (not locally on Windows); same EC2 doubles as dev machine and CI/CD server
- 2026-09-09 — EC2 sized t3.small (not free-tier t2.micro) — Jenkins+Docker+Maven need more than 1GB RAM
- 2026-09-09 — VPC: public subnets only (no NAT Gateway) — cost saving, compensated with restrictive Security Groups
- 2026-09-09 — EKS node group temporarily t3.micro (not t3.medium) — new AWS account Free Tier launch restriction
- 2026-09-09 — Jenkins requires Java 21; app targets Java 17 — both JDKs installed, Jenkins pointed at 21
- 2026-09-10 — Discovered course-provided DAO (RetailDataImp) is in-memory, not a real database — original "no persistent storage" decision was correct
- 2026-09-10 — Running at 1 replica temporarily due to in-memory DAO — revisit with real datastore later
- 2026-09-10 — Shared static DAO instance (SharedDataStore) across both servlets, avoiding per-servlet isolated state
