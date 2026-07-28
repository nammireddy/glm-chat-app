# Inference Service Dockerfile
# Base image: vLLM OpenAI-compatible server pinned to a specific digest for reproducibility
FROM vllm/vllm-openai:latest@sha256:3e63151a2db2ee28f5a95e4e15d2401740bfbc35a2a4e6342e860104a8ae7fb0

# Set model environment variable
ENV MODEL_NAME=THUDM/glm-4-9b-chat

# Copy entrypoint script
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Expose vLLM serving port
EXPOSE 8000

ENTRYPOINT ["/opt/entrypoint.sh"]
