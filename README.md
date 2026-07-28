# GLM Chat Application

A publicly accessible web chat interface backed by a self-hosted GLM-4 (GLM 5.2) large language model, deployed on AWS EKS with cost-optimised spot GPU nodes.

## Architecture Overview

- **Frontend** — React + Vite SPA with SSE streaming, served via Nginx
- **Chat Service** — FastAPI gateway (Python 3.12), session management, rate limiting
- **RAG Pipeline** — Retrieval-Augmented Generation, pgvector similarity search
- **Embedding Service** — `BAAI/bge-m3` sentence-transformers, 1024-dim embeddings
- **Confidence Scorer** — Cross-encoder scorer; answers below 0.7 are refused
- **Inference Service** — vLLM serving THUDM/glm-4-9b-chat on EKS GPU spot nodes
- **Infrastructure** — Terraform (VPC, EKS, RDS Aurora/pgvector, ElastiCache Redis, EFS, S3)
- **Orchestration** — Karpenter NodePools (g6e/g7e spot), AWS NTH for spot interruption handling
- **Observability** — kube-prometheus-stack, DCGM Exporter, Grafana dashboards, CloudWatch Logs

## Repository Layout

```
.
├── infra/
│   └── terraform/          # AWS infrastructure (VPC, EKS, RDS, Redis, EFS, S3, IRSA)
├── helm/                   # Helm charts for every service + umbrella chart
├── services/
│   ├── chat-service/       # FastAPI API gateway
│   ├── inference-service/  # vLLM inference wrapper
│   ├── rag-service/        # RAG pipeline + pgvector search
│   ├── embedding-service/  # Sentence-transformer embedding API
│   └── confidence-scorer/  # Cross-encoder confidence scoring
├── frontend/               # Vite + React + TypeScript SPA
└── .github/
    └── workflows/          # GitHub Actions CI/CD pipelines
```

## Prerequisites

| Tool      | Version   | Install hint                     |
|-----------|-----------|----------------------------------|
| Python    | 3.12      | `pyenv install 3.12` (`.python-version` pins it) |
| Node.js   | 20        | `nvm use` (`.nvmrc` pins it)     |
| Terraform | ≥ 1.7     | [terraform.io/downloads](https://developer.hashicorp.com/terraform/downloads) |
| Helm      | ≥ 3.14    | `brew install helm`              |
| kubectl   | ≥ 1.30    | `brew install kubectl`           |
| Docker    | ≥ 25      | [docs.docker.com](https://docs.docker.com/get-docker/) |
| AWS CLI   | v2        | `brew install awscli`            |

## Quick Start

```bash
# 1. Clone and set up language versions
git clone <repo-url> && cd glm-chat-app
nvm use          # switches to Node 20
pyenv local      # switches to Python 3.12

# 2. Lint all services
make lint

# 3. Run all tests
make test

# 4. Build all container images
make build

# 5. Provision infrastructure
cd infra/terraform && terraform init && terraform apply
```

## Common Make Targets

| Target        | Description                                      |
|---------------|--------------------------------------------------|
| `make lint`   | Run linters for all Python services and frontend |
| `make test`   | Run unit + property tests for all services       |
| `make build`  | Build Docker images for all services             |
| `make clean`  | Remove build artefacts and cached files          |

## Services and Ports

| Service              | Default Port |
|----------------------|-------------|
| chat-service         | 8080        |
| inference-service    | 8000        |
| rag-service          | 8002        |
| embedding-service    | 8001        |
| confidence-scorer    | 8003        |
| frontend (Nginx)     | 80          |

## Security Notes

- All inter-service traffic stays within the VPC; inference has no public listener.
- IRSA is used for all AWS access — no static credentials in pods.
- Session cookies are `HttpOnly; Secure; SameSite=Strict`.
- Rate limiting: 60 req / 60 s per source IP (returns HTTP 429).
- TLS 1.2+ enforced at ALB; HTTP redirects to HTTPS (301).

## Contributing

1. Create a feature branch.
2. Run `make lint` and `make test` before pushing.
3. Open a PR — CI runs automatically via GitHub Actions.
4. Production deploys require a manual approval step (GitHub environment protection).

## License

See [LICENSE](./LICENSE).
