# RCA Platform – Autonomous AI SRE & Microservices Platform

An enterprise-grade, end-to-end Kubernetes platform featuring:
- 🏗️ **Microservices Architecture:** Distributed `order-service` and `product-service` built with FastAPI.
- ⚙️ **Infrastructure as Code (Terraform):** Automated AWS provisioning (VPC, Security Groups, IAM with OIDC, ECR repositories, and EC2 with single-node **k3s cluster** installed via user-data).
- 🔄 **GitOps & CI/CD:** Continuous Integration via **GitHub Actions** (OIDC, automated ECR pushes, and GitOps manifest tag updates) and Continuous Deployment via **ArgoCD** (App-of-Apps pattern).
- 🧠 **Autonomous AI SRE Agent:** Continuous Kubernetes cluster observer that gathers logs, container exit codes, and Warning events to diagnose incidents, perform Root Cause Analysis (RCA) with Claude or automated heuristics, and dispatch **email notifications with an attached interactive HTML RCA report**.
- 💥 **Integrated Chaos Testing:** Built-in chaos endpoints to simulate real-world failure scenarios (`OOMKilled`, `CrashLoopBackOff`, and Database pool exhaustion) for instant demonstration.

---

## 🏛️ Architecture Overview

```text
                                  +-------------------------------------------------------------+
                                  |                     AWS Cloud (ap-south-1)                  |
                                  |                                                             |
+-------------------+             |   +-----------------------+     +-----------------------+   |
|   GitHub Actions  |--- OIDC --->|   |  ECR Container Regist |     |  Amazon SES / SMTP    |   |
|   CI Pipeline     |-- Push ---->|   |  - ai-sre-agent       |     |  Email Notifications  |   |
+---------+---------+             |   |  - order-service      |     |  with HTML Attachment |   |
          |                       |   |  - product-service    |     +-----------^-----------+   |
          | Update Image Tags     |   +-----------+-----------+                 |               |
          v                       |               | Pull Images                 | Sends Alert   |
+-------------------+             |               v                             | & Report      |
|  GitOps (ArgoCD)  |============>|   +-----------------------------------------+-----------+   |
|  Reconciliation   |             |   |               EC2 k3s Cluster Node                  |   |
+-------------------+             |   |                                                     |   |
                                  |   |   [argocd] Namespace                                |   |
                                  |   |     • argocd-server (NodePort :30443)               |   |
                                  |   |                                                     |   |
                                  |   |   [apps] Namespace (Microservices)                  |   |
                                  |   |     • order-service   (NodePort :30081)             |   |
                                  |   |     • product-service (NodePort :30082)             |   |
                                  |   |                                                     |   |
                                  |   |   [ai-agent] Namespace                              |   |
                                  |   |     • sre-agent       (NodePort :30080)             |   |
                                  |   |       - Reads Pod Statuses, Logs & Events           |   |
                                  |   |       - Diagnoses Failures & Generates HTML RCA     |   |
                                  |   +-----------------------------------------------------+   |
                                  +-------------------------------------------------------------+
```

---

## 📂 Repository Layout

```
RCA_Platform/
├── .github/
│   └── workflows/
│       └── ci-cd.yml                     # Multi-service build, ECR push & GitOps manifest updater
│
├── gitops/                               # ArgoCD GitOps Manifests
│   ├── apps/
│   │   ├── namespaces.yaml               # 'apps' and 'ai-agent' namespaces
│   │   ├── order-service/                # Deployment & Service (NodePort 30081)
│   │   ├── product-service/              # Deployment & Service (NodePort 30082)
│   │   └── sre-agent/                    # Deployment, Service (30080) & RBAC ClusterRole
│   └── argocd/
│       ├── root-application.yaml         # ArgoCD App-of-Apps master manifest
│       ├── application-order-service.yaml
│       ├── application-product-service.yaml
│       └── application-sre-agent.yaml
│
├── services/
│   ├── order-service/                    # Order placement & catalog consumer (FastAPI)
│   │   ├── main.py                       # HTTP API + Chaos endpoints (/chaos/crash, /chaos/db-error)
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   │
│   ├── product-service/                  # Inventory management (FastAPI)
│   │   ├── main.py                       # HTTP API + OOM injection (/chaos/oom, /chaos/latency)
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   │
│   └── sre-agent/                        # Autonomous AI SRE & RCA Agent (FastAPI + CLI)
│       ├── app.py                        # REST endpoints (/rca, /rca/auto-scan, /rca/latest, /chat)
│       ├── agent.py                      # Claude LLM tool-use loop + intelligent heuristic fallback
│       ├── tools.py                      # Kubernetes cluster scanner, log tailer, event fetcher
│       ├── report.py                     # HTML RCA renderer & email body generator
│       ├── mailer.py                     # AWS SES & standard SMTP multipart mailer with HTML attachment
│       ├── cli.py                        # Terminal CLI runner (`python cli.py rca`)
│       ├── Dockerfile
│       ├── requirements.txt
│       ├── templates/
│       │   └── rca.html.j2               # Modern interactive HTML RCA template
│       └── runbooks/                     # Knowledge base (crashloop, oomkilled, imagepull)
│
├── infra-terraform/                      # AWS Infrastructure as Code
│   ├── bootstrap/                        # S3 Remote State bucket + DynamoDB Lock Table
│   ├── modules/
│   │   ├── vpc/                          # Custom VPC, Public/Private Subnets, IGW, NAT Gateway
│   │   ├── security-groups/              # k3s Server SG (operator-restricted API and NodePorts)
│   │   ├── iam/                          # EC2 Node Role & GitHub Actions OIDC Role
│   │   ├── ecr/                          # ECR repositories (ai-sre-agent, order-service, product-service)
│   │   └── k3s-cluster/                  # EC2 Instance with k3s cluster installed via user-data
│   ├── environments/
│   │   └── prod/                         # Production environment configuration
│   └── Makefile                          # Infrastructure automation targets
│
└── scripts/
    ├── install-argocd.sh                 # One-click ArgoCD installer with NodePort setup
    └── trigger-chaos-rca.sh              # Failure injection & automated RCA email test runner
```

The primary demo target is the repository's existing AWS EC2 + k3s cluster. It installs LangGraph-based RCA workflows, self-hosted Langfuse, Prometheus, Grafana, Loki, and Grafana Alloy. Minikube remains available for local development; see [docs/architecture.md](./docs/architecture.md).

---

## 🚀 Execution Guide: Step-by-Step

Follow these steps to deploy and run the entire platform from scratch.

### Prerequisites

- [AWS CLI v2](https://aws.amazon.com/cli/) configured (`aws configure`)
- [Terraform](https://www.terraform.io/) $\ge$ 1.7
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://www.docker.com/) (optional for local testing)
- [jq](https://stedolan.github.io/jq/) and `curl`

---

### Local Minikube Demo

This local profile uses the existing FastAPI services and RCA agent. **LangGraph orchestrates the agent workflow** (model reasoning, tool execution, structured RCA, and fallback); **Langfuse observes the workflow**. Prometheus scrapes service metrics, Grafana provisions metrics/log dashboards, and Alloy forwards pod logs and Kubernetes events to Loki. The agent can query Loki for historical logs and still uses the Kubernetes API for pod state, events, and current/previous container logs.

The full stack is resource-intensive. Allocate about **6 CPUs, 12 GiB RAM, and 60 GiB disk** to Minikube, and install Helm 3.17 or newer. The local Helm values reduce bundled Langfuse database/object-store volumes for the demo.

```bash
minikube start --cpus=6 --memory=12288 --disk-size=60g
./scripts/install-observability.sh

kubectl create namespace ai-agent --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ai-agent create secret generic agent-secrets \
  --from-literal=agent_api_key=demo-key \
  --dry-run=client -o yaml | kubectl apply -f -

./scripts/deploy-minikube.sh
```

The agent falls back to heuristic analysis if `ANTHROPIC_API_KEY` is not configured. For LLM analysis, add `anthropic_api_key` to the `agent-secrets` Secret and restart the deployment.

Create a Langfuse organization/project in the local UI, then add its API keys to the agent Secret:

```bash
kubectl port-forward -n langfuse svc/langfuse-web 3001:3000
# Open http://localhost:3001, create a project, then use its keys below.
kubectl -n ai-agent create secret generic langfuse-credentials \
  --from-literal=public-key='<LANGFUSE_PUBLIC_KEY>' \
  --from-literal=secret-key='<LANGFUSE_SECRET_KEY>' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ai-agent rollout restart deployment/sre-agent
```

The agent captures operation/generation timings in Langfuse but disables prompt and response-body capture to avoid duplicating incident logs or report content in traces. Langfuse is for LLM observability; Loki is the log store.

Open the agent service with `minikube service -n ai-agent sre-agent`. Open Grafana with:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

The default Grafana login is `admin` / `prom-operator` for this local demo chart configuration. Change it before using the installation for any shared or persistent environment. The RCA Platform dashboard includes request rate, p95 latency, and application logs.

#### Demo scenarios

| Scenario | Trigger | Evidence to show |
|---|---|---|
| CrashLoopBackOff | `./scripts/trigger-chaos-rca.sh crash-order` | Restart/exit status, previous container logs, Loki stream, RCA |
| OOMKilled | `./scripts/trigger-chaos-rca.sh oom-product` | `OOMKilled` event, memory termination, Loki logs, RCA |
| Database pool exhaustion | `./scripts/trigger-chaos-rca.sh db-exhaustion` | Application error logs, Loki query, RCA recommendations |
| Deployment/image-pull failure | `./scripts/trigger-chaos-rca.sh bad-image-order` | `ImagePullBackOff`, Kubernetes events and Loki; the script rolls back after RCA |
| Latency spike | `./scripts/trigger-chaos-rca.sh latency-product` | Request latency in the Grafana p95 panel and matching Loki logs |

These chaos endpoints deliberately cause workload disruption and are meant only for the local demo. `bad-image-order` refuses to run unless the current kubectl context is `minikube`.

### AWS EC2 + k3s Observability Demo

The AWS deployment uses the existing Terraform-provisioned single-node k3s cluster. It is a demo setup, not a highly available production architecture. The bundled persistence requires a larger host and EBS volume than the low-cost Terraform example; a reasonable starting point is **8 vCPU, 32 GiB RAM, and 100 GiB EBS** (for example `m6i.2xlarge`). Review regional availability and cost before changing `k3s_instance_type` or `root_volume_size_gb`; Terraform apply can replace or restart infrastructure.

1. Follow Terraform steps 1–3 and fetch the cluster config:

   ```bash
   cd infra-terraform
   make kubeconfig
   export KUBECONFIG="$HOME/.kube/ai-sre-agent-prod.yaml"
   kubectl config current-context
   ```

2. Set `ssh_allowed_cidrs` in `terraform.tfvars` to your operator/management IP CIDR (never `0.0.0.0/0`). This restricts SSH, Kubernetes API access, the RCA API NodePort, the optional ArgoCD NodePort, and HTTP/HTTPS ingress. Grafana, Prometheus, Loki, and Langfuse are not exposed publicly; access them through `kubectl port-forward`.

3. Ensure the three service images are present in ECR and create the agent secret. `agent_api_key` is required when exposing the agent API; the Anthropic key is optional and heuristic RCA remains available without it:

   ```bash
   kubectl create namespace ai-agent --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n ai-agent create secret generic agent-secrets \
     --from-literal=agent_api_key='<AGENT_API_KEY>' \
     --from-literal=anthropic_api_key='<ANTHROPIC_API_KEY>' \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

4. Install the AWS-persisted observability values and AWS application overlay. The installer refuses to continue unless the current context matches the explicit context you provide and has a remote HTTPS API endpoint:

   ```bash
   AWS_K3S_CONTEXT='<exact-context-name>' ../scripts/install-observability.sh aws-k3s
   ```

   Replace the placeholder with the exact context name shown by `kubectl config current-context`, after confirming its API endpoint is the intended EC2 cluster. The first run installs the charts, provisions storage, and may take several minutes.

5. Create the Langfuse project and credentials, then enable agent tracing:

   ```bash
   kubectl port-forward -n langfuse svc/langfuse-web 3001:3000
   # Open http://localhost:3001, create a project, then:
   kubectl -n ai-agent create secret generic langfuse-credentials \
     --from-literal=public-key='<LANGFUSE_PUBLIC_KEY>' \
     --from-literal=secret-key='<LANGFUSE_SECRET_KEY>' \
     --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n ai-agent rollout restart deployment/sre-agent
   ```

6. Access the services without opening observability ports to the Internet:

   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   kubectl port-forward -n langfuse svc/langfuse-web 3001:3000
   ```

   Open Grafana at `http://localhost:3000` (the default credentials are `admin` / `prom-operator`; change them before shared use), Prometheus at `http://localhost:9090`, and Langfuse at `http://localhost:3001`. The agent API is available at `http://<EC2_PUBLIC_IP>:30080`; allow that port only from the management CIDRs in the security group.

The same five demo scenarios above are supported on AWS. Chaos triggers intentionally disrupt workloads; use only in the demo cluster. The agent observes Kubernetes state, Loki logs, and metrics but does not remediate workloads. Alloy forwards pod logs without content redaction, so do not send sensitive production logs without an ingestion redaction policy, access controls, and a retention plan. Langfuse prompt/response capture remains disabled.

---

### Step 1: Provision Infrastructure with Terraform

#### 1.1 Bootstrap S3 State & DynamoDB Table
```bash
cd infra-terraform
make bootstrap
```
Note the bucket name and DynamoDB lock table printed in the outputs.

#### 1.2 Configure Production Variables
Edit `infra-terraform/environments/prod/backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "<YOUR_BOOTSTRAP_BUCKET_NAME>"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "<YOUR_BOOTSTRAP_LOCK_TABLE_NAME>"
    encrypt        = true
  }
}
```

Copy and update `terraform.tfvars`:
```bash
cp environments/prod/terraform.tfvars.example environments/prod/terraform.tfvars
```
Set the following keys in `terraform.tfvars`:
- `github_repo = "your-github-username/your-repo-name"`
- `ses_sender_email = "alerts@yourdomain.com"` (or an email address you verify in AWS SES)
- `ssh_allowed_cidrs = ["YOUR_PUBLIC_IP/32"]` (required; do not use `0.0.0.0/0`)
- `tfstate_bucket = "<YOUR_BOOTSTRAP_BUCKET_NAME>"`
- `tflock_table = "<YOUR_BOOTSTRAP_LOCK_TABLE_NAME>"`

#### 1.3 Deploy Cluster & Infrastructure
```bash
make init
make plan
make apply
```

The user-data script on EC2 automatically:
1. Installs Amazon Linux 2023 dependencies (`awscli`, `jq`, `curl`, `git`).
2. Installs `k3s` with Traefik enabled and the Elastic IP registered in its TLS SAN.
3. Uploads the patched remote `kubeconfig` directly to AWS SSM Parameter Store (`/ai-sre-agent/prod/k3s/kubeconfig`).
4. Installs the Kubernetes Metrics Server.

---

### Step 2: Configure Local Kubectl Access

Fetch your cluster kubeconfig automatically using AWS SSM:
```bash
make kubeconfig
```
Or export the kubeconfig manually:
```bash
export KUBECONFIG=~/.kube/ai-sre-agent-prod.yaml
kubectl get nodes -o wide
```
You should see your EC2 k3s node in `Ready` status.

---

### Step 3: Install ArgoCD on the Cluster

Run the automated ArgoCD installation script:
```bash
cd ..
./scripts/install-argocd.sh
```
This script:
- Creates the `argocd` namespace.
- Deploys official ArgoCD manifests.
- Exposes `argocd-server` on **NodePort 30443**.
- Fetches and displays the initial admin credentials.

Access the ArgoCD Web Dashboard:
- URL: `https://<EC2_PUBLIC_IP>:30443`
- Username: `admin`
- Password: `<printed by script>`

---

### Step 4: Configure Secrets & Email Notifications

Create the SRE Agent Kubernetes secret in the `ai-agent` namespace:
```bash
kubectl create namespace ai-agent --dry-run=client -o yaml | kubectl apply -f -

kubectl -n ai-agent create secret generic agent-secrets \
  --from-literal=anthropic_api_key="sk-ant-..." \
  --from-literal=agent_api_key="your-sre-secret-key" \
  --from-literal=smtp_host="smtp.gmail.com" \
  --from-literal=smtp_user="your-email@gmail.com" \
  --from-literal=smtp_pass="your-app-password"
```

> [!NOTE]
> - **Anthropic Key:** Optional! If you don't provide an Anthropic key, the SRE Agent's built-in **intelligent heuristic engine** automatically takes over to inspect logs, events, and exit codes to produce a complete RCA report.
> - **Email:** Supports both **AWS SES** (via the EC2 instance role) and standard **SMTP** (e.g., Gmail App Passwords, Mailgun, SendGrid).

---

### Step 5: Deploy Services via ArgoCD (GitOps)

1. Open `gitops/argocd/*.yaml` and ensure `repoURL` points to your GitHub repository:
   ```yaml
   source:
     repoURL: https://github.com/<your-username>/RCA_Platform.git
     targetRevision: HEAD
   ```
2. Apply the **App-of-Apps** master manifest:
   ```bash
   kubectl apply -f gitops/argocd/root-application.yaml
   ```
3. ArgoCD immediately detects the definitions and synchronizes:
   - `apps/namespaces.yaml`
   - `order-service` (NodePort 30081)
   - `product-service` (NodePort 30082)
   - `sre-agent` (NodePort 30080)

Verify running pods:
```bash
kubectl get pods -n apps
kubectl get pods -n ai-agent
```

---

### Step 6: Configure GitHub Actions CI/CD Pipeline

Add the following repository secrets to GitHub (**Settings → Secrets and variables → Actions**):
- `AWS_ROLE_ARN`: The GitHub Actions OIDC IAM role ARN (from `terraform output github_actions_role_arn`)
- `AWS_REGION`: `ap-south-1`

Whenever code is pushed to `main`:
1. GitHub Actions runs code syntax checks and tests.
2. Builds Docker images for changed microservices and pushes them to AWS ECR.
3. Automatically updates image tags in `gitops/apps/*/deployment.yaml` and commits the changes.
4. ArgoCD detects the commit and performs an automated zero-downtime rolling update.

---

### Step 7: Test Chaos Injection & Automated RCA Generation

We provide a turnkey script that triggers failures and runs the full RCA pipeline:

```bash
# Scenario 1: Process crash in order-service (CrashLoopBackOff)
./scripts/trigger-chaos-rca.sh crash-order your-email@example.com

# Scenario 2: Memory exhaustion in product-service (OOMKilled - Exit code 137)
./scripts/trigger-chaos-rca.sh oom-product your-email@example.com

# Scenario 3: Database pool exhaustion simulation
./scripts/trigger-chaos-rca.sh db-exhaustion your-email@example.com
```

#### What Happens Behind the Scenes:
1. The script calls the service's chaos endpoint (`/chaos/crash` or `/chaos/oom`).
2. Kubernetes detects the failure (CrashLoopBackOff or cgroup OOM termination).
3. The AI SRE Agent:
   - Calls `tools.get_pod_logs(..., previous=True)` to extract previous crash logs and stack traces.
   - Fetches Kubernetes warning events and termination exit codes.
   - Diagnoses the root cause using the LLM agent or heuristic analyzer.
   - Formulates immediate remediation commands (`kubectl rollout undo`, scale limits, etc.) and long-term prevention.
   - Renders a responsive **HTML RCA Report**.
   - Dispatches an **email notification** with the full HTML report **attached**.
4. You can view the live HTML report anytime in your browser at:
   `http://<EC2_PUBLIC_IP>:30080/rca/latest`

---

## 🛠️ Service Endpoints Reference

| Service | NodePort | Description | Key Endpoints |
|---|---|---|---|
| **ArgoCD UI** | `30443` | GitOps Management Dashboard | `https://<IP>:30443` |
| **SRE Agent** | `30080` | RCA Generator & Cluster Observer | `GET /rca/latest`<br>`POST /rca`<br>`POST /rca/auto-scan`<br>`POST /chat` |
| **Order Service** | `30081` | Order Processing Microservice | `GET /orders`<br>`POST /orders`<br>`POST /chaos/crash`<br>`POST /chaos/db-error` |
| **Product Service** | `30082` | Product Catalog Microservice | `GET /products`<br>`POST /chaos/oom`<br>`POST /chaos/latency` |

---

## 💻 CLI Usage

You can also run the SRE Agent directly from the command line:

```bash
cd services/sre-agent

# Scan cluster for unhealthy pods
python cli.py scan

# Perform RCA and send email
python cli.py rca --question "product-service is restarting" --email you@example.com

# Test email transmission and HTML attachment
python cli.py test-email --to you@example.com
```
