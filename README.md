# GLM Chat Application

A production-ready web chat interface powered by the self-hosted [GLM-4-9B-Chat](https://huggingface.co/THUDM/glm-4-9b-chat) large language model, deployed on AWS EKS with GPU spot instances for cost efficiency.

![Architecture](https://img.shields.io/badge/LLM-GLM--4--9B-blue) ![AWS](https://img.shields.io/badge/Cloud-AWS_EKS-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Real-time streaming chat** — Server-Sent Events (SSE) for token-by-token responses
- **Self-hosted LLM** — No API keys or third-party dependencies; full control over the model
- **RAG pipeline** — Retrieval-Augmented Generation with pgvector similarity search
- **Cost-optimised** — GPU spot instances (g5/g6) via Karpenter for ~70% savings
- **Fallback to general knowledge** — When RAG has no relevant documents, the model answers from its training data
- **Session memory** — Conversation history preserved across messages (Redis-backed)
- **Confidence scoring** — Cross-encoder scoring for observability (never blocks responses)

## Architecture

```
┌──────────┐     ┌──────────────┐     ┌──────────────────┐
│ Frontend │────▶│ Chat Service │────▶│ Inference (vLLM)  │
│ React+TS │     │   FastAPI    │     │ GLM-4-9B on GPU   │
└──────────┘     └──────┬───────┘     └──────────────────┘
                        │
              ┌─────────┼─────────┐
              ▼         ▼         ▼
        ┌─────────┐ ┌───────┐ ┌──────────────────┐
        │  Redis  │ │  RAG  │ │Confidence Scorer │
        │(session)│ │Service│ │  (cross-encoder) │
        └─────────┘ └───┬───┘ └──────────────────┘
                        │
              ┌─────────┼─────────┐
              ▼                   ▼
        ┌───────────┐     ┌────────────┐
        │PostgreSQL │     │ Embedding  │
        │ pgvector  │     │  Service   │
        └───────────┘     └────────────┘
```

## Repository Layout

```
.
├── frontend/               # React + Vite + TypeScript SPA
├── services/
│   ├── chat-service/       # FastAPI gateway (session, rate-limit, orchestration)
│   ├── inference-service/  # vLLM wrapper + mock server for local dev
│   ├── rag-service/        # RAG pipeline + pgvector search
│   ├── embedding-service/  # BAAI/bge-m3 sentence-transformer API
│   └── confidence-scorer/  # Cross-encoder confidence scoring
├── helm/                   # Helm charts for Kubernetes deployment
├── k8s/                    # Raw Kubernetes manifests (vLLM GPU deployment)
├── infra/                  # Terraform for AWS infrastructure
├── scripts/                # Deployment automation scripts
├── docker-compose.yml      # Local development stack
└── Makefile                # Build, lint, test shortcuts
```

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker | ≥ 25 | [docs.docker.com](https://docs.docker.com/get-docker/) or `brew install colima docker` |
| Node.js | 20 | `nvm install 20` (pinned in `.nvmrc`) |
| Python | 3.12 | `pyenv install 3.12` (pinned in `.python-version`) |
| AWS CLI | v2 | `brew install awscli` |
| kubectl | ≥ 1.30 | `brew install kubectl` |
| Helm | ≥ 3.14 | `brew install helm` |
| Terraform | ≥ 1.7 | `brew install terraform` |

---

## Quick Start — Local Development

Run the entire stack locally with Docker Compose. The inference service is replaced by a mock that returns realistic responses without requiring a GPU.

### 1. Clone the Repository

```bash
git clone https://github.com/namrahul/glm-chat-app.git
cd glm-chat-app
```

### 2. Set Up Environment

```bash
cp .env.example .env
```

### 3. Start All Services

```bash
docker compose up -d
```

This starts:
- **Redis** (port 6379) — session storage
- **PostgreSQL + pgvector** (port 5432) — RAG vector database
- **Inference Mock** (port 8000) — simulates GLM-4 responses
- **Embedding Service** (port 8001) — sentence embeddings
- **RAG Service** (port 8002) — retrieval pipeline
- **Confidence Scorer** (port 8003) — answer scoring
- **Chat Service** (port 8080) — API gateway
- **Frontend** (port 80) — web UI

### 4. Open the App

Visit **http://localhost** in your browser and start chatting.

### 5. View Logs

```bash
docker compose logs -f chat-service
```

### 6. Stop Everything

```bash
docker compose down
```

> **Note:** The embedding-service loads a ~2GB model on first start. If your machine has less than 8GB RAM, you may need to increase Docker's memory limit or start services selectively:
> ```bash
> docker compose up -d redis postgres inference-mock chat-service frontend
> ```

---

## Production Deployment — AWS EKS

Deploy the full application on EKS with a real GPU-accelerated GLM-4-9B model.

### Architecture Overview

- **EKS Cluster** with managed node groups (CPU + GPU spot)
- **vLLM** serving GLM-4-9B-Chat on g5/g6 spot instances (NVIDIA A10G/L4 GPU)
- **ECR** for container image registry
- **Redis (ElastiCache)** for session storage
- **PostgreSQL (Aurora)** with pgvector for RAG

### Step 1: Configure AWS Credentials

```bash
aws configure
# or use temporary credentials:
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# Verify:
aws sts get-caller-identity
```

### Step 2: Provision Infrastructure with Terraform

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

This creates: VPC, EKS cluster, ECR repositories, RDS Aurora (pgvector), ElastiCache Redis, EFS, IAM roles (IRSA).

### Step 3: Configure kubectl

```bash
aws eks update-kubeconfig --name glm-chat --region us-east-1
kubectl get nodes  # verify connectivity
```

### Step 4: Create GPU Node Group

```bash
aws eks create-nodegroup \
  --cluster-name glm-chat \
  --nodegroup-name gpu-spot \
  --node-role <NODE_ROLE_ARN> \
  --subnets <SUBNET_IDS> \
  --instance-types g5.xlarge g5.2xlarge g6.xlarge g6.2xlarge \
  --capacity-type SPOT \
  --scaling-config minSize=1,maxSize=2,desiredSize=1 \
  --ami-type AL2_x86_64_GPU \
  --disk-size 100 \
  --labels workload=gpu-inference \
  --region us-east-1
```

### Step 5: Install NVIDIA Device Plugin

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml
```

### Step 6: Build and Push Images

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Build for linux/amd64 (required for EKS x86 nodes)
TAG=$(date +%Y%m%d-%H%M%S)
SERVICES=(chat-service inference-service rag-service embedding-service confidence-scorer frontend)
DIRS=(services/chat-service services/inference-service services/rag-service services/embedding-service services/confidence-scorer frontend)

for i in "${!SERVICES[@]}"; do
  docker build --platform linux/amd64 \
    -t <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/glm-chat/${SERVICES[$i]}:$TAG \
    ${DIRS[$i]}
  docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/glm-chat/${SERVICES[$i]}:$TAG
done
```

> **Important:** ECR repositories use immutable tags. Always use unique tags (timestamp or git SHA), never `latest`.

### Step 7: Deploy Services with Helm

```bash
NAMESPACE=glm-chat
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Deploy each service
for svc in inference-service embedding-service rag-service confidence-scorer chat-service frontend; do
  helm upgrade --install $svc helm/$svc \
    --namespace $NAMESPACE \
    --set image.repository=<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/glm-chat/$svc \
    --set image.tag=$TAG \
    --values helm/overrides.yaml
done
```

### Step 8: Deploy vLLM on GPU Node

```bash
# Apply the vLLM deployment (uses nodeSelector: workload=gpu-inference)
kubectl apply -f k8s/vllm-glm4.yaml

# Watch the model download and startup (~5-10 minutes)
kubectl logs -f -n glm-chat -l app=inference-service
```

The vLLM pod will:
1. Pull the vLLM Docker image (~5.6GB)
2. Download GLM-4-9B-Chat weights from HuggingFace (~18GB)
3. Load model into GPU memory
4. Pass the `/health` readiness probe and start serving

### Step 9: Verify

```bash
# Check all pods
kubectl get pods -n glm-chat

# Test the API
curl -X POST http://<FRONTEND_ELB_URL>/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, what is machine learning?"}'
```

### Automated Deployment

For a fully automated deploy (infra + build + deploy):

```bash
./scripts/deploy.sh
```

Options:
- `--skip-infra` — skip Terraform provisioning
- `--skip-build` — skip Docker image builds
- `--skip-deploy` — skip Helm deployments

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_URL` | `redis://localhost:6379` | Redis connection URL |
| `INFERENCE_SERVICE_URL` | `http://inference-service:8000` | vLLM endpoint |
| `RAG_SERVICE_URL` | `http://rag-service:8002` | RAG pipeline endpoint |
| `SCORER_SERVICE_URL` | `http://confidence-scorer:8003` | Confidence scorer endpoint |
| `INFERENCE_MODEL_NAME` | `THUDM/glm-4-9b-chat` | Model name for vLLM API calls |
| `PGHOST` | `localhost` | PostgreSQL host |
| `PGPORT` | `5432` | PostgreSQL port |
| `PGUSER` | `glmchat_admin` | PostgreSQL user |
| `PGPASSWORD` | — | PostgreSQL password |
| `PGDATABASE` | `glmchat` | PostgreSQL database |

### GPU Instance Recommendations

| Instance | GPU | VRAM | Cost (Spot) | Notes |
|----------|-----|------|-------------|-------|
| g5.xlarge | A10G | 24GB | ~$0.40/hr | Good for GLM-4-9B |
| g5.2xlarge | A10G | 24GB | ~$0.55/hr | More CPU/RAM headroom |
| g6.xlarge | L4 | 24GB | ~$0.35/hr | Newest, best value |
| g6.2xlarge | L4 | 24GB | ~$0.50/hr | More CPU/RAM headroom |

GLM-4-9B-Chat requires ~18GB VRAM. All instances above provide 24GB.

---

## Services & Ports

| Service | Port | Protocol | Description |
|---------|------|----------|-------------|
| Frontend | 80 | HTTP | React SPA served via Nginx |
| Chat Service | 8080 | HTTP | API gateway, session management |
| Inference Service | 8000 | HTTP | vLLM OpenAI-compatible API |
| RAG Service | 8002 | HTTP | Document retrieval |
| Embedding Service | 8001 | HTTP | Sentence embeddings |
| Confidence Scorer | 8003 | HTTP | Answer confidence scoring |

---

## API Reference

### POST /chat

Send a chat message and receive a streaming SSE response.

**Request:**
```json
{
  "message": "What is machine learning?"
}
```

**Response:** Server-Sent Events stream
```
data: {"id":"chatcmpl-abc123","choices":[{"delta":{"content":"Machine"},"finish_reason":null}],"usage":null}

data: {"id":"chatcmpl-abc123","choices":[{"delta":{"content":" learning"},"finish_reason":null}],"usage":null}

...

data: {"id":"chatcmpl-abc123","choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":59,"completion_tokens":120},"metadata":{"grounding":"none","confidence":0.72,"sources":[]}}

data: [DONE]
```

### GET /health
Returns `200` if the service is running.

### GET /ready
Returns `200` if all dependencies (Redis, RAG, Inference) are reachable.

---

## Development

### Run Linters

```bash
make lint
```

### Run Tests

```bash
make test
```

### Build Images Locally

```bash
make build
```

### Frontend Development (hot reload)

```bash
cd frontend
npm install
npm run dev
```

---

## Troubleshooting

### Docker Desktop Not Working (macOS)

If Docker Desktop requires org sign-in or won't start, use [Colima](https://github.com/abiosoft/colima) as an alternative:

```bash
brew install colima docker
colima start --cpu 4 --memory 8
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
docker ps  # verify it works
```

### Embedding Service OOM

The embedding service loads a ~2GB model. Ensure your Docker runtime has at least 8GB RAM allocated:
- **Colima:** `colima start --memory 8`
- **Docker Desktop:** Settings → Resources → Memory → 8GB+

### vLLM Pod Stuck in ContainerCreating

The vLLM image is ~5.6GB and the model is ~18GB. First startup takes 5-10 minutes:
```bash
kubectl describe pod -n glm-chat -l app=inference-service
kubectl logs -n glm-chat -l app=inference-service --tail=20
```

### Platform Mismatch (Image Pull Error)

If EKS shows "no match for platform in manifest", rebuild with `--platform linux/amd64`:
```bash
docker build --platform linux/amd64 -t <image>:<tag> .
```

### HuggingFace Gated Model

If GLM-4-9B-Chat becomes gated, add your HF token to the deployment:
```bash
kubectl set env deployment/inference-service-gpu \
  HUGGING_FACE_HUB_TOKEN=hf_your_token_here \
  -n glm-chat
```

---

## Security

- All inter-service traffic stays within the VPC
- IRSA (IAM Roles for Service Accounts) — no static AWS credentials
- Session cookies: `HttpOnly; Secure; SameSite=Strict`
- Rate limiting: 60 requests / 60 seconds per IP (HTTP 429)
- No user message content is logged (only metadata)
- Session IDs stored as SHA-256 hashes in logs

---

## License

MIT — see [LICENSE](./LICENSE).
