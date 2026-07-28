#!/bin/bash
set -e

MODEL_PATH="/mnt/efs/models/glm-4-9b-chat"

# Check if model weights are present on the EFS mount
if [ ! -d "${MODEL_PATH}" ] || [ -z "$(ls -A ${MODEL_PATH} 2>/dev/null)" ]; then
    echo "Model weights not found at ${MODEL_PATH}. Downloading..."
    mkdir -p "${MODEL_PATH}"
    python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='${MODEL_NAME}',
    local_dir='${MODEL_PATH}',
    local_dir_use_symlinks=False
)
"
    echo "Model download complete."
else
    echo "Model weights found at ${MODEL_PATH}. Skipping download."
fi

# Start vLLM serving
exec python -m vllm.entrypoints.openai.api_server \
    --model "${MODEL_PATH}" \
    --served-model-name glm-4-9b-chat \
    --dtype float16 \
    --max-model-len 8192 \
    --port 8000
