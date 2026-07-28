# Implementation Plan: GLM Chat Application

## Overview

This plan converts the GLM Chat Application design into discrete, dependency-ordered coding tasks. Infrastructure is provisioned first (Terraform), followed by Kubernetes base manifests and Karpenter configuration, then each backend microservice (inference, embedding, RAG, scorer, chat-service), the React frontend, observability stack, and finally the CI/CD pipeline. Security hardening tasks are woven into each layer rather than deferred to the end.

Tasks marked with `*` are optional (tests / property tests) and may be skipped for a faster MVP. All other tasks must be completed. Checkpoints verify incremental correctness before the next layer starts.

---

## Tasks

- [x] 1. Repository and project scaffolding
  - Create the monorepo directory layout: `infra/terraform/`, `helm/`, `services/chat-service/`, `services/inference-service/`, `services/rag-service/`, `services/embedding-service/`, `services/confidence-scorer/`, `frontend/`, `.github/workflows/`
  - Add root `.gitignore`, `README.md`, and `Makefile` with common targets (`lint`, `test`, `build`)
  - Pin Python 3.12 via `.python-version` (pyenv) and Node 20 via `.nvmrc`
  - _Requirements: 4.1, 5.1_


- [x] 2. Terraform — core AWS networking
  - [x] 2.1 Write `infra/terraform/vpc/main.tf`: VPC `10.0.0.0/16`, three public subnets (`10.0.0.0/20`, `10.0.16.0/20`, `10.0.32.0/20`) and three private subnets (`10.0.48.0/20`, `10.0.64.0/20`, `10.0.80.0/20`) across `us-east-1a/b/c`; Internet Gateway; NAT Gateway per AZ; route tables
    - _Requirements: 5.1, 5.6_
  - [x] 2.2 Write `infra/terraform/endpoints/main.tf`: VPC Gateway endpoint for S3; interface endpoints for ECR API, ECR DKR, CloudWatch Logs, STS
    - _Requirements: 8.2, 8.3_
  - [x] 2.3 Write `infra/terraform/security_groups/main.tf`: define `sg-alb`, `sg-chat-svc`, `sg-inference`, `sg-rds`, `sg-redis` with the exact ingress/egress rules from the design; tag all SGs with `karpenter.sh/discovery: glm-chat` and `karpenter.sh/discovery: glm-chat-gpu` where appropriate
    - _Requirements: 8.3_
  - [ ]* 2.4 Write Terraform unit tests (using `terraform validate` + `tflint`) asserting no rule in `sg-inference` allows ingress from `0.0.0.0/0`
    - _Requirements: 8.3_

- [x] 3. Terraform — EKS cluster
  - [x] 3.1 Write `infra/terraform/eks/main.tf`: EKS control plane (Kubernetes 1.30+), OIDC provider for IRSA, managed node group `system-od` (`m7i.2xlarge`, on-demand, min 2 / max 4), cluster add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI)
    - _Requirements: 5.6_
  - [x] 3.2 Write `infra/terraform/eks/karpenter_iam.tf`: Karpenter controller IAM role (IRSA), `KarpenterNodeRole-glm-chat` instance profile, EC2 fleet/spot policies scoped to cluster tags; no wildcard resources
    - _Requirements: 5.1, 5.2, 8.2_
  - [x] 3.3 Write `infra/terraform/acm/main.tf`: request ACM certificate for the application domain with DNS validation; output the certificate ARN
    - _Requirements: 8.1_


- [x] 4. Terraform — data stores and storage
  - [x] 4.1 Write `infra/terraform/rds/main.tf`: Aurora PostgreSQL cluster (engine `aurora-postgresql`, `pgvector` extension enabled), two instances across two AZs, placed in private subnets, SG `sg-rds`; output the cluster endpoint
    - _Requirements: 3.1_
  - [x] 4.2 Write `infra/terraform/elasticache/main.tf`: ElastiCache Redis (engine 7.x), single-shard with one read replica, Multi-AZ, placed in private subnets, SG `sg-redis`; output the primary endpoint
    - _Requirements: 2.4, 7.3_
  - [x] 4.3 Write `infra/terraform/efs/main.tf`: EFS file system with mount targets in all three private subnets; access point for the inference service; lifecycle policy to transition to IA after 30 days
    - _Requirements: 4.1_
  - [x] 4.4 Write `infra/terraform/s3/main.tf`: S3 bucket for model weights with versioning enabled, SSE-S3 encryption, public access blocked, bucket policy restricting `s3:GetObject` to the inference IRSA role
    - _Requirements: 8.2, 8.3_

- [x] 5. Terraform — IRSA roles
  - [x] 5.1 Write `infra/terraform/irsa/chat_service.tf`: IAM role for `chat-service` service account allowing only `elasticache:Connect`, `logs:PutLogEvents`, `logs:CreateLogStream` scoped to specific resource ARNs
    - _Requirements: 8.2_
  - [x] 5.2 Write `infra/terraform/irsa/rag_service.tf`: IAM role for `rag-service` allowing `rds-db:connect` to the specific Aurora cluster resource ARN only
    - _Requirements: 8.2_
  - [x] 5.3 Write `infra/terraform/irsa/inference_service.tf`: IAM role for `inference-service` allowing `s3:GetObject` on the weights bucket prefix and `elasticfilesystem:ClientMount` on the specific EFS access point ARN
    - _Requirements: 8.2, 8.3_
  - [ ]* 5.4 Write a policy-as-code test (using `aws-nuke` dry-run or `opa` with a Rego rule) asserting all IRSA policies contain no `"*"` action or resource
    - _Requirements: 8.2_

- [x] 6. Checkpoint — infrastructure provisioning
  - Run `terraform plan` across all modules and verify zero errors; confirm EKS cluster reaches `ACTIVE` state; confirm RDS, ElastiCache, and EFS are reachable from the `system-od` node group.
  - Ensure all tests pass, ask the user if questions arise.


- [x] 7. Karpenter installation and NodePool manifests
  - [x] 7.1 Write `helm/karpenter/` values and install script: deploy Karpenter controller (v1.x) into the `karpenter` namespace on the `system-od` node group using the Helm chart; configure the IRSA annotation on the `karpenter` service account
    - _Requirements: 5.2, 5.6_
  - [x] 7.2 Write `infra/k8s/karpenter/gpu-nodepool.yaml`: `NodePool` manifest `gpu-inference` with all six g6e/g7e instance types, spot-first capacity type ordering, `consolidationPolicy: WhenEmpty`, `consolidateAfter: 60s`, `budgets: [{nodes: "10%"}]`, GPU taint `nvidia.com/gpu: NoSchedule`, and GPU limit `nvidia.com/gpu: 20`
    - _Requirements: 5.2, 5.3, 5.4, 6.4_
  - [x] 7.3 Write `infra/k8s/karpenter/gpu-nodeclass.yaml`: `EC2NodeClass` `gpu-nodes` referencing `KarpenterNodeRole-glm-chat`, AL2023 AMI family, private subnet selector tag, GPU SG selector tag, 200 GiB gp3 root volume, userData bootstrapping NVIDIA toolkit
    - _Requirements: 5.2, 5.3_
  - [x] 7.4 Write `infra/k8s/karpenter/cpu-nodepool.yaml`: `NodePool` `cpu-workloads` covering `c7i.2xlarge` and `c7i.4xlarge`, spot capacity, no GPU taint, consolidation enabled
    - _Requirements: 5.2_

- [x] 8. AWS Node Termination Handler (NTH) DaemonSet
  - Write `infra/k8s/nth/daemonset.yaml`: deploy NTH on all GPU nodes (node selector `workload: inference`); configure IMDS polling interval 5 seconds; enable cordon-and-drain on spot ITN; mount host IMDS endpoint; set `enableSpotInterruptionDraining: true` and `enableScheduledEventDraining: false`
  - _Requirements: 5.3, 5.4_


- [x] 9. Inference Service — container and Helm chart
  - [x] 9.1 Write `services/inference-service/Dockerfile`: base image `vllm/vllm-openai:latest` pinned to a specific digest; copy model-loading entrypoint script; set `ENV MODEL_NAME=THUDM/glm-4-9b-chat`; expose port 8000
    - _Requirements: 4.1, 4.2_
  - [x] 9.2 Write `services/inference-service/entrypoint.sh`: download model weights from EFS mount (path `/mnt/efs/models/glm-4-9b-chat`) if not already present; invoke `vllm serve` with `--model`, `--served-model-name glm-4-9b-chat`, `--dtype float16`, `--max-model-len 8192`, `--port 8000`
    - _Requirements: 4.1, 4.2, 4.3_
  - [x] 9.3 Write `helm/inference-service/templates/deployment.yaml`: `Deployment` with `nvidia.com/gpu: 1` resource request/limit, toleration for `nvidia.com/gpu: NoSchedule`, node affinity for `workload: inference`, `terminationGracePeriodSeconds: 100`, `preStop` hook (`kill -SIGTERM 1; sleep 90`), env var `VLLM_GRACEFUL_SHUTDOWN_TIMEOUT=90`, liveness on `/health` and readiness on `/ready` at port 8000
    - _Requirements: 4.1, 5.3, 6.6_
  - [x] 9.4 Write `helm/inference-service/templates/pdb.yaml`: `PodDisruptionBudget` `minAvailable: 1` for the inference deployment
    - _Requirements: 7.4_
  - [x] 9.5 Write `helm/inference-service/templates/hpa.yaml`: `HorizontalPodAutoscaler` using external metric `dcgm_fi_dev_gpu_util` with `averageValue: 70`, `minReplicas: 1`, `maxReplicas: 20`, scale-up stabilisation 60 s / max +4 pods, scale-down stabilisation 300 s / -1 pod
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [x] 9.6 Write `helm/inference-service/templates/service.yaml`: ClusterIP `Service` on port 8000; annotate with Prometheus scrape `true`
    - _Requirements: 9.1_
  - [ ]* 9.7 Write unit tests in `services/inference-service/tests/test_lifecycle.py` using `httpx` against a locally-spawned stub server: assert `/health` returns 200 when up; assert `/ready` returns non-2xx after SIGTERM signal is sent to the process
    - _Requirements: 4.1, 7.6_


- [x] 10. Inference Service — parameter validation
  - [x] 10.1 Write `services/inference-service/vllm_proxy.py` (FastAPI wrapper or vLLM middleware): add a validation layer that checks `temperature ∈ [0.0, 2.0]`, `top_p ∈ [0.0, 1.0]`, `max_tokens ∈ [1, 8192]`, and rejects unrecognised top-level parameters; return HTTP 400 with a descriptive message on violation; forward valid requests to the vLLM server on localhost:8000
    - _Requirements: 4.4, 4.7_
  - [x] 10.2 Write `services/inference-service/timeout_middleware.py`: ASGI middleware that cancels any request exceeding 60 seconds and returns HTTP 504
    - _Requirements: 4.5_
  - [ ]* 10.3 Write property tests in `services/inference-service/tests/test_validation_props.py` using `hypothesis`: for any `temperature` outside `[0.0, 2.0]` the proxy returns 400; for any `max_tokens` outside `[1, 8192]` the proxy returns 400; for any unrecognised key the proxy returns 400 with the key named in the body
    - _Requirements: 4.4, 4.7_

- [x] 11. Embedding Service
  - [x] 11.1 Write `services/embedding-service/app.py`: FastAPI app, `POST /embed` endpoint; load `BAAI/bge-m3` via `sentence-transformers`; accept `{"text": str}`, return `{"embedding": float[1024]}`; export `/metrics` via `prometheus_fastapi_instrumentator`
    - _Requirements: 3.1_
  - [x] 11.2 Write `services/embedding-service/Dockerfile`: `python:3.12-slim`; install `sentence-transformers`, `onnxruntime`; copy `app.py`; expose port 8001
    - _Requirements: 3.1_
  - [x] 11.3 Write `helm/embedding-service/templates/deployment.yaml`: 2 CPU replicas, readiness on `GET /health`, no GPU toleration, node affinity for `cpu-workloads`
    - _Requirements: 3.1_
  - [ ]* 11.4 Write unit tests in `services/embedding-service/tests/test_embed.py`: assert output dimension is 1024; assert the same input produces an identical embedding (determinism at inference-mode)
    - _Requirements: 3.1_


- [x] 12. RAG Pipeline Service
  - [x] 12.1 Write `services/rag-service/db.py`: asyncpg connection pool to Aurora PostgreSQL; implement `create_documents_table()` that runs the `CREATE TABLE documents (…)` DDL and `CREATE INDEX … USING hnsw` from the design; implement `cosine_search(embedding, top_k, min_score) → list[Document]`
    - _Requirements: 3.1, 3.4_
  - [x] 12.2 Write `services/rag-service/app.py`: FastAPI app, `POST /retrieve` endpoint; accept `{query, top_k, min_score}`; call Embedding Service via `httpx`; call `cosine_search`; compute `grounding` field (`"full"` if all docs ≥ min_score, `"partial"` if some, `"none"` if empty); return response model from the design
    - _Requirements: 3.1, 3.2, 3.4, 3.5, 3.6_
  - [x] 12.3 Write `services/rag-service/Dockerfile`: `python:3.12-slim`; install `fastapi`, `uvicorn`, `asyncpg`, `httpx`; expose port 8002
    - _Requirements: 3.1_
  - [x] 12.4 Write `helm/rag-service/templates/deployment.yaml`: 2–6 replicas, IRSA annotation for `rag-service` service account, readiness on `GET /health`
    - _Requirements: 3.1, 8.2_
  - [ ]* 12.5 Write unit tests in `services/rag-service/tests/test_retrieve.py`: mock `cosine_search` to return empty list → assert `grounding == "none"` and `documents == []`; mock it to return docs all above threshold → assert `grounding == "full"`; mock with mixed scores → assert `grounding == "partial"`
    - _Requirements: 3.4, 3.5, 3.6_
  - [ ]* 12.6 Write property tests in `services/rag-service/tests/test_retrieve_props.py` using `hypothesis`: for any list of documents all with score ≥ `min_score`, the `grounding` field is never `"none"`; for any empty document list, no source references appear in the response
    - _Requirements: 3.4, 3.5, 3.6_


- [x] 13. Confidence Scorer Service
  - [x] 13.1 Write `services/confidence-scorer/app.py`: FastAPI app, `POST /score` endpoint; load `cross-encoder/ms-marco-MiniLM-L-6-v2` via `sentence-transformers`; accept `{query: str, answer: str}`; compute logit → sigmoid to `[0, 1]`; return `{score: float, threshold_met: bool}` where `threshold_met = score >= 0.7`
    - _Requirements: 3.3, 3.8_
  - [x] 13.2 Write `services/confidence-scorer/Dockerfile`: `python:3.12-slim`; install `sentence-transformers`; expose port 8003
    - _Requirements: 3.3_
  - [x] 13.3 Write `helm/confidence-scorer/templates/deployment.yaml`: 2–4 replicas, readiness on `GET /health`, circuit-breaker annotation for Chat Service to detect unavailability
    - _Requirements: 3.3, 3.8_
  - [ ]* 13.4 Write property tests in `services/confidence-scorer/tests/test_score_props.py` using `hypothesis`: for any query/answer pair the score is always in `[0.0, 1.0]`; `threshold_met` is `True` iff `score >= 0.7`
    - _Requirements: 3.3_

- [x] 14. Checkpoint — backend microservices
  - Build Docker images locally for inference-service, embedding-service, rag-service, confidence-scorer; run all unit and property tests; confirm each service responds correctly on its designated port.
  - Ensure all tests pass, ask the user if questions arise.


- [x] 15. Chat Service — session management and Redis integration
  - [x] 15.1 Write `services/chat-service/session.py`: async Redis client (aioredis); implement `load_session(session_id) → list[Turn]`, `save_session(session_id, turns)` (RPUSH + LTRIM to 100 entries, TTL 86400 s); hash `session_id` with SHA-256 before using it as a log field; return empty list on Redis unavailability (stateless fallback)
    - _Requirements: 2.4, 7.3, 9.3_
  - [x] 15.2 Write `services/chat-service/cookie.py`: helper that issues and reads `session_id` as an `HttpOnly; Secure; SameSite=Strict` cookie; generate a new UUID v4 when no cookie is present
    - _Requirements: 8.4_
  - [ ]* 15.3 Write property tests in `services/chat-service/tests/test_session_props.py` using `hypothesis`: for any list of turns with length > 100, after `save_session` the stored list length is ≤ 100 and the oldest entries are discarded; for any `session_id`, `load_session(save_session(id, turns)) == turns[-100:]`
    - _Requirements: 2.4_

- [x] 16. Chat Service — rate limiting
  - [x] 16.1 Write `services/chat-service/rate_limit.py`: integrate `slowapi`; configure token-bucket rate limiter at 60 requests per 60 seconds keyed on source IP; return HTTP 429 when exceeded; add `Retry-After` header
    - _Requirements: 8.5_
  - [ ]* 16.2 Write unit tests in `services/chat-service/tests/test_rate_limit.py`: assert the 61st request from the same IP within a 60-second window returns 429; assert the first 60 requests return 2xx
    - _Requirements: 8.5_


- [x] 17. Chat Service — main application and SSE streaming
  - [x] 17.1 Write `services/chat-service/rag_client.py`: async HTTP client to RAG Pipeline; call `POST /retrieve` with query, `top_k=5`, `min_score=0.65`; time out after 5 seconds; return empty document list on timeout (proceed without context, set `grounding: "none"`)
    - _Requirements: 3.1, 3.2, 7.1_
  - [x] 17.2 Write `services/chat-service/inference_client.py`: async HTTP client to Inference Service; call `POST /v1/chat/completions` with assembled prompt (system prompt + retrieved docs + last-20-turns history); set `stream: true`; implement 3-retry exponential backoff (1s, 2s, 4s) on 5xx errors (excluding 501, 505); total retry budget ≤ 10 s; raise after exhaustion
    - _Requirements: 4.2, 4.3, 7.3_
  - [x] 17.3 Write `services/chat-service/scorer_client.py`: async HTTP client to Confidence Scorer; call `POST /score`; return `(score=0.0, threshold_met=False)` when the scorer is unreachable (circuit breaker open)
    - _Requirements: 3.3, 3.8_
  - [x] 17.4 Write `services/chat-service/prompt_builder.py`: assemble the final prompt list: system prompt, retrieved document chunks as `role: user` context block, then the last-20-turn conversation history, then the current user message
    - _Requirements: 2.4, 3.2, 3.7_
  - [x] 17.5 Write `services/chat-service/app.py`: FastAPI app with `POST /chat`, `GET /health`, `GET /ready`; `POST /chat` validates message (non-empty, ≤ 4096 chars), reads session cookie, loads history, calls RAG → builds prompt → streams from Inference Service via `StreamingResponse`; after stream completes calls scorer; if `threshold_met` is False replaces buffered answer with refusal message and sends it; appends final turn to session; `/ready` checks Redis, RAG, and Inference reachability; logs structured JSON per the design log schema
    - _Requirements: 1.1, 2.1, 2.2, 2.4, 3.3, 3.5, 3.8, 4.3, 7.6, 9.3_
  - [x] 17.6 Write `services/chat-service/Dockerfile`: `python:3.12-slim`; install `fastapi`, `uvicorn`, `httpx`, `aioredis`, `slowapi`, `prometheus_fastapi_instrumentator`; expose port 8080
    - _Requirements: 1.1_


- [ ] 18. Chat Service — tests
  - [ ]* 18.1 Write unit tests in `services/chat-service/tests/test_app.py`: assert empty message returns 422 (validation error); assert message > 4096 chars returns 422; assert a valid message with a mocked inference stream returns SSE events ending with `data: [DONE]`
    - _Requirements: 2.2, 2.6, 4.3_
  - [ ]* 18.2 Write unit tests in `services/chat-service/tests/test_refusal.py`: mock scorer to return `score=0.3` → assert response body contains refusal message; mock scorer to return `score=0.8` → assert response body does not contain refusal message
    - _Requirements: 3.3, 3.8_
  - [ ]* 18.3 Write unit tests in `services/chat-service/tests/test_retry.py`: mock inference client to fail twice with 500 then succeed → assert the caller receives a successful response; mock to fail four times → assert HTTP 504 is returned
    - _Requirements: 7.3_
  - [ ]* 18.4 Write property tests in `services/chat-service/tests/test_chat_props.py` using `hypothesis`: for any non-whitespace message with length ∈ [1, 4096] the chat endpoint with mocked downstream services returns a 200 with at least one SSE `data:` event; for any whitespace-only string the endpoint returns a 4xx error
    - _Requirements: 2.1, 2.2_

- [x] 19. Chat Service — Helm chart
  - [x] 19.1 Write `helm/chat-service/templates/deployment.yaml`: 2–20 replicas, IRSA annotation for `chat-service` service account, readiness on `GET /ready`, liveness on `GET /health`, SG annotation `sg-chat-svc`
    - _Requirements: 7.6, 8.2_
  - [x] 19.2 Write `helm/chat-service/templates/service.yaml` and `ingress.yaml`: ClusterIP service; ALB `Ingress` with HTTPS listener, ACM certificate ARN from Terraform output, HTTP→HTTPS 301 redirect action, SSL policy `ELBSecurityPolicy-TLS13-1-2-2021-06`
    - _Requirements: 8.1_

- [x] 20. Checkpoint — Chat Service integration
  - Wire Chat Service against stub implementations of RAG, Inference, and Scorer (return mock responses); run all tests; verify SSE streaming works end-to-end using `curl --no-buffer`; confirm `/ready` returns 503 when Redis is unavailable.
  - Ensure all tests pass, ask the user if questions arise.


- [x] 21. Frontend — project setup and core components
  - [x] 21.1 Bootstrap `frontend/` as a Vite + React + TypeScript project; install `react-markdown`, `remark-gfm`, `eventsource-parser`, `dompurify`; configure `tsconfig.json` for strict mode
    - _Requirements: 1.1, 2.5_
  - [x] 21.2 Write `frontend/src/components/ChatWindow.tsx`: renders conversation history (list of `{role, content}` messages); auto-scrolls to the latest message on each new message; caps in-memory message list at 100 and drops oldest
    - _Requirements: 1.5, 1.6_
  - [x] 21.3 Write `frontend/src/components/MessageBubble.tsx`: renders a single message; uses `react-markdown` with `remark-gfm` to render bold, italic, code blocks, numbered and bulleted lists; sanitises HTML via `dompurify`
    - _Requirements: 2.5_
  - [x] 21.4 Write `frontend/src/components/InputBar.tsx`: textarea input with `maxLength={4096}`; displays live character count `(N / 4096)`; disables the textarea and submit button while a response is loading; prevents submission when the trimmed value is empty and shows inline validation message; restores the user's submitted message text on error
    - _Requirements: 2.2, 2.3, 2.6, 2.7, 1.4_


- [x] 22. Frontend — SSE client and error handling
  - [x] 22.1 Write `frontend/src/lib/sseClient.ts`: function `streamChat(message, onToken, onDone, onError)` that opens a `fetch` SSE request to `POST /chat`, parses `data:` events with `eventsource-parser`, calls `onToken(delta)` for each token, `onDone()` on `[DONE]`, and `onError(err)` on network error or 4xx/5xx response
    - _Requirements: 1.4, 2.1, 7.2_
  - [x] 22.2 Write `frontend/src/components/ErrorBanner.tsx`: displays an error message and a visible "Retry" button when the last request failed (HTTP 5xx or timeout); clicking "Retry" re-submits the last message
    - _Requirements: 1.4, 7.2_
  - [x] 22.3 Write `frontend/src/components/LoadingIndicator.tsx`: animated spinner or skeleton shown while a response is in progress
    - _Requirements: 1.4_
  - [x] 22.4 Write `frontend/src/App.tsx`: wire `ChatWindow`, `InputBar`, `ErrorBanner`, `LoadingIndicator`, `sseClient` together; manage `messages`, `loading`, `error` state; on submit: clear error, set loading, append user message, start SSE stream, append assistant message token-by-token; on `[DONE]` clear loading; on error set error state and preserve input text; session cookie is set by the backend
    - _Requirements: 1.4, 1.5, 2.1, 2.7_

- [ ] 23. Frontend — tests
  - [ ]* 23.1 Write unit tests in `frontend/src/components/__tests__/InputBar.test.tsx` using Vitest + `@testing-library/react`: assert empty input shows validation message and does not call submit; assert input with 4097 characters is blocked; assert character counter displays correct value
    - _Requirements: 2.2, 2.6_
  - [ ]* 23.2 Write unit tests in `frontend/src/lib/__tests__/sseClient.test.ts`: mock `fetch` to return a sequence of SSE lines; assert `onToken` is called for each delta; assert `onDone` is called after `[DONE]`; assert `onError` is called when the server returns 500
    - _Requirements: 4.3, 7.2_


- [x] 24. Frontend — Nginx container and Helm chart
  - [x] 24.1 Write `frontend/Dockerfile`: multi-stage build — stage 1 uses `node:20-alpine` to run `npm ci && npm run build`; stage 2 uses `nginx:1.27-alpine`, copies the `dist/` artefact, adds an `nginx.conf` that serves the SPA with `try_files $uri /index.html`, sets `Cache-Control: no-cache` for `index.html`, and proxies `/chat`, `/health`, `/ready` to the Chat Service
    - _Requirements: 1.1_
  - [x] 24.2 Write `helm/frontend/templates/deployment.yaml` and `service.yaml`: 2 replicas, readiness on `GET /`; ClusterIP service on port 80
    - _Requirements: 1.1, 1.2_

- [x] 25. Checkpoint — full stack local smoke test
  - Use `docker compose` to run all six services (chat-service, inference-stub, rag-service, embedding-service, confidence-scorer, frontend) together; open `http://localhost` in a browser and verify a message round-trip; confirm SSE streaming is visible; confirm an empty message shows a validation error.
  - Ensure all tests pass, ask the user if questions arise.


- [x] 26. Observability — DCGM Exporter and prometheus-adapter
  - [x] 26.1 Write `infra/k8s/dcgm/daemonset.yaml`: DCGM Exporter DaemonSet (`nvidia/dcgm-exporter`) on GPU nodes (node selector `workload: inference`), expose port 9400, Prometheus scrape annotations
    - _Requirements: 9.1, 9.2_
  - [x] 26.2 Write `infra/k8s/prometheus-adapter/values.yaml`: configure `prometheus-adapter` Helm values to expose `dcgm_fi_dev_gpu_util` as an external metric aggregated by pod, matching the HPA metric selector in task 9.5
    - _Requirements: 6.1, 9.2_

- [x] 27. Observability — kube-prometheus-stack
  - [x] 27.1 Write `helm/kube-prometheus-stack/values.yaml`: deploy `kube-prometheus-stack` into the `monitoring` namespace on `system-od` nodes; configure scrape intervals 60 s; add `ServiceMonitor` targets for `chat-service`, `rag-service`, `vllm-inference`, `dcgm-exporter`; enable `kube-state-metrics`; configure Prometheus storage 50 Gi
    - _Requirements: 9.1, 9.2_
  - [x] 27.2 Write `infra/k8s/alertmanager/alertrules.yaml`: Prometheus alert rules for `HighGPUUtilization` (>85% for 60 s), `InferenceErrorRate` (>5% for 60 s), `ConfidenceScorerDown` (up==0 for 30 s); configure Alertmanager to route to SNS with 3-retry exponential backoff; log each failed SNS publish to CloudWatch
    - _Requirements: 9.5, 9.6_
  - [x] 27.3 Write `infra/k8s/grafana/dashboards/`: four dashboard JSON files: `inference-overview.json` (TTFT p50/p95/p99, token throughput, GPU util, queue depth), `rag-health.json` (retrieval latency, no-context rate), `cluster-topology.json` (Karpenter node inventory, spot/on-demand split), `slo.json` (error rate, availability, p99 vs targets)
    - _Requirements: 9.2_

- [x] 28. Observability — CloudWatch log export
  - Write `infra/k8s/fluent-bit/daemonset.yaml` and `configmap.yaml`: Fluent Bit DaemonSet forwarding all pod `stdout`/`stderr` to CloudWatch Log Groups `/glm-chat/chat-service`, `/glm-chat/inference-service`, `/glm-chat/rag-service`; set log group retention to 30 days via the Fluent Bit CloudWatch plugin `log_retention_days 30`; filter out any field named `message_content` or `user_message` before forwarding
    - _Requirements: 9.3, 9.4_


- [x] 29. CI/CD — GitHub Actions pipeline
  - [x] 29.1 Write `.github/workflows/ci.yml`: on push to any branch, run `pytest` for all Python services (with `--tb=short`) and `vitest --run` for the frontend; cache pip and npm dependencies; fail fast on any test failure
    - _Requirements: all_
  - [x] 29.2 Write `.github/workflows/build-push.yml`: on merge to `main`, build Docker images for all six services using `docker buildx`; tag with `${{ github.sha }}`; push to ECR; run ECR image scan (`aws ecr start-image-scan`); fail the workflow if any critical CVE is found
    - _Requirements: 8.2_
  - [x] 29.3 Write `.github/workflows/deploy-staging.yml`: after a successful build, run `helm upgrade --install --atomic --timeout 5m` for all services against the staging EKS cluster; run smoke tests (`curl` `/health` and `/ready` endpoints for each service; send one chat message and assert `data: [DONE]` is received); gate on smoke test success
    - _Requirements: 7.6, 4.1_
  - [x] 29.4 Write `.github/workflows/deploy-prod.yml`: require a manual approval step (GitHub environment protection rule); run `helm upgrade --install --atomic --timeout 10m` against prod EKS cluster; run post-deploy Prometheus query asserting `rate(http_requests_total{status=~"5.."}[5m]) < 0.01`; send a Slack/SNS notification on success or failure
    - _Requirements: all_

- [x] 30. Security hardening — final validation pass
  - [x] 30.1 Verify the ALB Ingress annotation `alb.ingress.kubernetes.io/actions.redirect-http` redirects all port-80 traffic to HTTPS with a 301; write an integration test (using `curl -I http://<domain>`) asserting the redirect
    - _Requirements: 8.1_
  - [x] 30.2 Verify `sg-inference` has no ingress rule allowing source `0.0.0.0/0` or `::/0`; add a Terraform `check` block or OPA policy asserting this
    - _Requirements: 8.3_
  - [x] 30.3 Verify the session cookie `Set-Cookie` header contains `HttpOnly`, `Secure`, and `SameSite=Strict`; write an integration test (using `httpx`) asserting all three attributes are present in the `POST /chat` response
    - _Requirements: 8.4_
  - [x] 30.4 Verify the rate limiter: write an integration test that fires 65 sequential requests from a single IP and asserts the 61st and beyond return 429 with a `Retry-After` header
    - _Requirements: 8.5_

- [x] 31. Final checkpoint — end-to-end validation
  - Deploy all Helm charts to the staging cluster; run the full smoke-test suite; confirm Grafana dashboards populate with live data; confirm a spot interruption simulation (using `aws ec2 request-spot-instances` cancel) triggers NTH cordon-drain without dropping any active chat request; confirm Alertmanager delivers a test alert to SNS within 120 seconds.
  - Ensure all tests pass, ask the user if questions arise.


---

## Task Dependency Graph

```json
{
  "waves": [
    {
      "wave": 1,
      "tasks": ["1"],
      "description": "Repository scaffolding"
    },
    {
      "wave": 2,
      "tasks": ["2", "3", "4", "5"],
      "description": "AWS infrastructure — VPC, EKS, data stores, IRSA"
    },
    {
      "wave": 3,
      "tasks": ["6"],
      "description": "Checkpoint — infrastructure"
    },
    {
      "wave": 4,
      "tasks": ["7", "8"],
      "description": "Karpenter NodePool manifests and NTH DaemonSet"
    },
    {
      "wave": 5,
      "tasks": ["9", "10", "11", "12", "13"],
      "description": "Backend microservices — inference, embedding, RAG, scorer"
    },
    {
      "wave": 6,
      "tasks": ["14"],
      "description": "Checkpoint — backend microservices"
    },
    {
      "wave": 7,
      "tasks": ["15", "16", "17", "18", "19"],
      "description": "Chat Service — session, rate limiting, app, tests, Helm chart"
    },
    {
      "wave": 8,
      "tasks": ["20"],
      "description": "Checkpoint — Chat Service integration"
    },
    {
      "wave": 9,
      "tasks": ["21", "22", "23", "24"],
      "description": "Frontend — React SPA, SSE client, tests, Nginx container"
    },
    {
      "wave": 10,
      "tasks": ["25"],
      "description": "Checkpoint — full stack local smoke test"
    },
    {
      "wave": 11,
      "tasks": ["26", "27", "28"],
      "description": "Observability — DCGM, kube-prometheus-stack, Fluent Bit"
    },
    {
      "wave": 12,
      "tasks": ["29"],
      "description": "CI/CD — GitHub Actions pipeline"
    },
    {
      "wave": 13,
      "tasks": ["30"],
      "description": "Security hardening — final validation pass"
    },
    {
      "wave": 14,
      "tasks": ["31"],
      "description": "Final checkpoint — end-to-end validation"
    }
  ]
}
```

---

## Notes

- Tasks marked with `*` are optional (test sub-tasks) and may be skipped for a faster MVP; all un-starred tasks must be implemented.
- Each task references the requirement numbers it satisfies for traceability; sub-requirement granularity (e.g., `3.3`, `8.2`) is used wherever possible.
- Dependency order: infrastructure (tasks 2–6) → Karpenter/NTH (tasks 7–8) → microservices (tasks 9–18) → frontend (tasks 21–24) → observability (tasks 26–28) → CI/CD (task 29) → security validation (task 30).
- Checkpoints (tasks 6, 14, 20, 25, 31) are verification milestones; run all accumulated tests before proceeding past each one.
- Property tests (tagged with `hypothesis`) validate universal correctness properties defined in the design document.
- Unit tests focus on specific examples, edge cases, and error conditions that complement the property tests.
