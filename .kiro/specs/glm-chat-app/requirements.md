# Requirements Document

## Introduction

This document defines requirements for a public-facing web chat application that allows any user to ask questions and receive accurate, grounded answers. The backend uses a self-hosted GLM-4 (GLM 5.2) model running on AWS EKS with spot instances for cost efficiency. The system includes anti-hallucination measures to ensure answer reliability, spot instance resilience for high availability, and auto-scaling to handle variable load.

## Glossary

- **Chat_UI**: The web-based frontend interface through which users submit questions and receive answers.
- **Inference_Service**: The backend service that processes prompts and generates responses using the GLM model.
- **GLM_Model**: The GLM-4 (GLM 5.2) large language model used to generate responses.
- **RAG_Pipeline**: Retrieval-Augmented Generation pipeline that grounds answers in retrieved context documents.
- **Confidence_Scorer**: The component that evaluates the reliability of a generated answer before returning it to the user.
- **EKS_Cluster**: The AWS Elastic Kubernetes Service cluster that hosts the Inference_Service.
- **Spot_Manager**: The component responsible for managing spot instance lifecycle, interruption handling, and node provisioning.
- **Load_Balancer**: The AWS load balancer that distributes incoming requests across available Inference_Service pods.
- **HPA**: Horizontal Pod Autoscaler — the Kubernetes mechanism that scales Inference_Service pods based on observed load.
- **Karpenter**: The Kubernetes node provisioner used to provision and deprovision spot instances dynamically.
- **Session**: A user's browser-level chat session, identified by a session token, containing the conversation history.

---

## Requirements

### Requirement 1: Public Web Chat Interface

**User Story:** As a visitor, I want to access a chat interface from any web browser without needing an account, so that I can immediately ask questions and receive answers.

#### Acceptance Criteria

1. THE Chat_UI SHALL be accessible at a public URL via HTTPS without requiring user authentication.
2. WHEN a user opens the chat URL, THE Chat_UI SHALL display an input field and a conversation history area within 3 seconds.
3. THE Chat_UI SHALL support modern browsers (Chrome, Firefox, Safari, Edge — latest two major versions each).
4. WHEN a user submits a message, THE Chat_UI SHALL display a loading indicator and disable the input field until a response is received or an error occurs; IF the backend returns an error or does not respond within 30 seconds, THEN THE Chat_UI SHALL re-enable the input field and display an error message.
5. WHEN a response is received, THE Chat_UI SHALL append the answer to the conversation history and scroll to the latest message regardless of the user's current scroll position.
6. THE Chat_UI SHALL maintain the conversation history for the duration of the browser Session, defined as the lifetime of the current browser tab; THE Chat_UI SHALL cap stored history at 100 messages per Session and discard the oldest messages when the cap is exceeded.

---

### Requirement 2: Question and Answer Interaction

**User Story:** As a user, I want to type a question and receive a clear answer, so that I can get information from the system.

#### Acceptance Criteria

1. WHEN a user submits a non-empty message and the system has 50 or fewer concurrent active sessions, THE Inference_Service SHALL return a response within 30 seconds.
2. WHEN a user submits an empty or whitespace-only message, THE Chat_UI SHALL prevent submission and display an inline validation message.
3. WHEN a message is valid and submission succeeds, THE Chat_UI SHALL not display a validation message.
4. THE Inference_Service SHALL preserve the last 20 turns of conversation history within a Session and include them in the prompt context when generating each response.
5. WHEN a response is generated, THE Chat_UI SHALL render markdown formatting (bold, italic, code blocks, numbered and bulleted lists) in the response text.
6. THE Chat_UI SHALL limit the input message length to 4096 characters, display a character count indicator, and block further input when the 4096-character limit is reached.
7. IF THE Inference_Service does not return a response within 30 seconds or returns an error, THEN THE Chat_UI SHALL display an error message and preserve the user's submitted message text in the input field.

---

### Requirement 3: Anti-Hallucination and Answer Grounding

**User Story:** As a user, I want the system to only provide answers it is confident about, so that I do not receive fabricated or misleading information.

#### Acceptance Criteria

1. THE Inference_Service SHALL pass each user query through the RAG_Pipeline to retrieve context documents with a similarity score at or above a configurable minimum similarity threshold before generating a response.
2. WHEN the RAG_Pipeline retrieves context documents, THE Inference_Service SHALL include those documents in the prompt to the GLM_Model as grounding context.
3. WHEN a generated answer is evaluated by the Confidence_Scorer with a score below the configured minimum threshold (default 0.7 on a 0.0–1.0 scale), THE Inference_Service SHALL return a refusal message stating the system cannot confidently answer the question rather than the low-confidence answer.
4. WHEN the RAG_Pipeline returns no relevant context documents for a query, THE Inference_Service SHALL set the `grounding` field in the response metadata to `"none"` to indicate the answer is based on model knowledge without external grounding.
5. WHEN the RAG_Pipeline returns relevant context documents, THE Inference_Service SHALL include the source document references in the response metadata so the Chat_UI can optionally display them.
6. WHEN the RAG_Pipeline returns no relevant documents, THE Inference_Service SHALL omit the source reference section from the response metadata.
7. WHEN a system prompt or grounding instruction is configured, THE Inference_Service SHALL prepend it to every GLM_Model request to constrain answer scope.
8. WHEN the Confidence_Scorer is unavailable, THE Inference_Service SHALL treat the confidence score as below threshold and return the refusal message.

---

### Requirement 4: GLM Model Backend

**User Story:** As a system operator, I want the chat application to use the GLM-4 (GLM 5.2) model for inference, so that the system leverages a capable and controllable self-hosted model.

#### Acceptance Criteria

1. THE Inference_Service SHALL load and serve the GLM-4 (GLM 5.2) model using vLLM or TGI, and SHALL pass a readiness check (HTTP 200 on `/ready`) only after the model is fully loaded and able to process requests.
2. THE Inference_Service SHALL expose an internal HTTP API endpoint at `/v1/chat/completions` that accepts requests containing at minimum the `model`, `messages`, and `stream` fields in the OpenAI Chat Completions schema and returns responses containing the `id`, `choices`, `usage`, and `finish_reason` fields.
3. WHEN a request is received with `stream: true`, THE Inference_Service SHALL stream tokens back to the caller using server-sent events and SHALL emit a final `[DONE]` event when generation is complete.
4. THE Inference_Service SHALL accept the following configurable parameters per request: `system_prompt` (string), `temperature` (float, 0.0–2.0), `top_p` (float, 0.0–1.0), and `max_tokens` (integer, 1–8192); IF a parameter value is outside its valid range, THEN THE Inference_Service SHALL return HTTP 400 with a descriptive error message.
5. IF a GLM_Model inference request exceeds the configured timeout of 60 seconds, THEN THE Inference_Service SHALL cancel the request and return an HTTP 504 error.
6. THE Inference_Service SHALL log each request's latency, input token count, output token count, and `finish_reason` for observability.
7. IF a request contains an unrecognised or unsupported parameter, THEN THE Inference_Service SHALL return HTTP 400 with a message identifying the offending parameter.

---

### Requirement 5: EKS Spot Instance Deployment

**User Story:** As a system operator, I want inference workloads to run on EKS spot instances, so that I can reduce compute costs while maintaining availability.

#### Acceptance Criteria

1. THE EKS_Cluster SHALL be deployed in an AWS US region that has spot instance availability for g6e and/or g7e instance families.
2. THE Spot_Manager SHALL configure node pools covering at least six instance types across g6e and g7e families (xlarge, 2xlarge, 4xlarge).
3. WHEN a spot interruption notice is received with a 2-minute warning, THE Spot_Manager SHALL cordon the affected node, drain in-flight requests within a 90-second window, and terminate the node gracefully.
4. IF the termination trigger is not a spot interruption notice (e.g., manual scaling or cluster scale-down), THEN THE Spot_Manager SHALL NOT initiate the cordon-drain-terminate sequence defined in criterion 3.
5. WHEN the EKS_Cluster requires additional inference capacity and all spot instance types in the configured pool are unavailable or constrained beyond 5 minutes, THE Spot_Manager SHALL first retry alternate instance types in the pool, and then provision an on-demand GPU instance with at least 24 GiB of GPU memory to maintain service continuity.
6. THE EKS_Cluster SHALL maintain at least one on-demand node for system-critical components (Load_Balancer, Karpenter controller, monitoring) that are not subject to spot interruption.

---

### Requirement 6: Auto-Scaling

**User Story:** As a system operator, I want the inference pods to scale automatically with user demand, so that the application remains responsive under variable load without over-provisioning.

#### Acceptance Criteria

1. THE HPA SHALL scale Inference_Service pods based on average GPU utilisation measured over a 60-second rolling window, targeting 70% average utilisation per pod.
2. WHEN average GPU utilisation exceeds 70% for 60 consecutive seconds, THE HPA SHALL increase the Inference_Service pod count by at least 1 and at most 4 pods.
3. WHEN average GPU utilisation falls below 30% for 300 consecutive seconds, THE HPA SHALL decrease the Inference_Service pod count by one pod, subject to a minimum pod count of 1.
4. THE EKS_Cluster SHALL enforce a maximum Inference_Service pod count of 20 to cap costs.
5. WHEN a new Inference_Service pod is scheduled and no existing node has at least one free GPU unit capable of hosting one Inference_Service pod, THE Spot_Manager (via Karpenter) SHALL provision a new GPU node; new pods SHALL be allowed to share existing GPU nodes when sufficient capacity is available.
6. WHEN the pod count decreases, the Kubernetes pod lifecycle SHALL ensure in-flight requests on terminating pods complete before the pod is removed, using a graceful termination period of 120 seconds; IF in-flight requests persist beyond 120 seconds, THE pod SHALL be forcefully terminated.

---

### Requirement 7: Reliability and Error Handling

**User Story:** As a user, I want the application to recover gracefully from errors, so that temporary infrastructure issues do not cause a permanent outage.

#### Acceptance Criteria

1. WHEN an Inference_Service pod becomes unavailable, THE Load_Balancer SHALL route all subsequent new requests only to healthy pods; requests that were not yet in-flight at the time of pod failure SHALL not receive an error response attributable to that pod failure.
2. IF a request to the Inference_Service fails with a 5xx error, THEN THE Chat_UI SHALL display a message indicating the request failed and present a visible retry control to the user.
3. IF THE Inference_Service encounters a transient internal error (HTTP 5xx, excluding 501 and 505), THEN THE Inference_Service SHALL retry the request up to 3 times using exponential backoff starting at 1 second, with a maximum total retry duration of 10 seconds.
4. WHEN the EKS_Cluster loses more than 50% of Inference_Service pods simultaneously, THE system SHALL continue to serve requests using the remaining pods at a throughput of at least 50% of the pre-failure baseline.
5. WHILE the pod loss is below 50%, THE system SHALL serve all incoming requests without measurable throughput degradation compared to the pre-failure baseline.
6. THE system SHALL expose a `/health` liveness endpoint and a `/ready` readiness endpoint; WHEN the service is healthy, each endpoint SHALL return HTTP 200; WHEN the service is unhealthy or not ready, each respective endpoint SHALL return a non-2xx status code.

---

### Requirement 8: Security and Compliance

**User Story:** As a system operator, I want all traffic to be encrypted and the infrastructure to follow least-privilege principles, so that user data and model assets are protected.

#### Acceptance Criteria

1. THE Chat_UI SHALL be served exclusively over HTTPS with TLS 1.2 or higher; HTTP requests SHALL be redirected to HTTPS.
2. THE EKS_Cluster SHALL use AWS IAM roles for service accounts (IRSA) so that each pod's service account is bound to a dedicated IAM role that contains no wildcard actions or resources, and pods access AWS services without static credentials.
3. THE Inference_Service SHALL have no public-facing listener and its associated security group SHALL deny all ingress traffic from outside the VPC, ensuring model weights and inference API endpoints are not reachable from the public internet.
4. WHEN a user session token is generated, THE Chat_UI backend SHALL set it as an HttpOnly, Secure, SameSite=Strict cookie.
5. IF a source IP sends more than 60 requests within any 60-second window, THEN THE system SHALL reject subsequent requests from that IP with HTTP 429 until the rate drops below the threshold.

---

### Requirement 9: Observability

**User Story:** As a system operator, I want comprehensive metrics and logs, so that I can monitor system health and troubleshoot incidents.

#### Acceptance Criteria

1. THE Inference_Service SHALL emit Prometheus-compatible metrics including request rate, response latency (p50, p95, p99 in milliseconds), error rate (percentage), GPU utilisation (0–100%), and token throughput (tokens/second).
2. THE EKS_Cluster SHALL deploy a Prometheus and Grafana stack that scrapes metrics from all services deployed within the cluster at an interval of 60 seconds or less.
3. WHEN a request results in an error, THE Inference_Service SHALL log a structured entry containing: correlation ID, timestamp (ISO 8601), HTTP status code, error type, and request size in tokens; THE log entry SHALL NOT include the user's message content or any personally identifiable information.
4. THE system SHALL retain logs for a minimum of 30 calendar days from ingestion time using CloudWatch Logs or a service that provides equivalent searchable log storage and retrieval.
5. WHEN any service metric exceeds a configurable alert threshold continuously for 60 seconds, THE system SHALL deliver an alert to a configured notification channel (e.g., SNS or PagerDuty) within 120 seconds of the threshold being crossed.
6. IF the configured notification channel is unavailable when an alert is triggered, THEN THE system SHALL retry alert delivery up to 3 times with exponential backoff and log each failed delivery attempt with the alert payload.
