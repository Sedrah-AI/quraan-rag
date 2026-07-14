#!/usr/bin/env bash
# Quran RAG system — full redeploy on a new machine.
#
# This script does NOT reconstruct the custom-trained model checkpoints or
# ingested database contents from scratch (that's hours/days of GPU work:
# Whisper fine-tuning, CTC word-alignment, tajweed embedding training,
# Milvus indexing, Postgres ingestion). Instead it:
#   - downloads the two fine-tuned model checkpoints from Hugging Face
#     (SedraRagaad/quran-whisper, SedraRagaad/wav2vec2-tajweed - both
#     private, need a token with read access to the SedraRagaad org)
#   - downloads the base Quran audio/text dataset from Hugging Face
#     (Buraaq/quran-audio-text-dataset - public)
#   - rsyncs everything else that's genuinely only-on-the-old-machine
#     (the ingested Postgres data, the built Milvus index, golden tajweed
#     embeddings) from the OLD machine over SSH
# and then just brings the stack up here - the practical "move to a new
# box" path, not a from-source rebuild.
#
# Usage:
#   ./deploy.sh SOURCE_HOST [SOURCE_SSH_USER]
#
# Example:
#   ./deploy.sh old-gpu-box.example.com nvidia
#
# Run this FROM the new machine. It needs:
#   - passwordless (key-based) SSH to the old machine for the rsync steps
#     (ssh-copy-id first if not already set up)
#   - a Hugging Face token with read access to the SedraRagaad org, in
#     .env as HF_TOKEN (the model repos are private) - see step 4 below
set -euo pipefail

SOURCE_HOST="${1:?Usage: ./deploy.sh SOURCE_HOST [SOURCE_SSH_USER]}"
SOURCE_USER="${2:-$USER}"
SOURCE="${SOURCE_USER}@${SOURCE_HOST}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="/data/quraan-rag"

HF_QURAN_WHISPER_REPO="SedraRagaad/quran-whisper"
HF_TAJWEED_REPO="SedraRagaad/wav2vec2-tajweed"
HF_DATASET_REPO="Buraaq/quran-audio-text-dataset"

step() { echo; echo "=== $1 ==="; }
confirm() {
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ── 1. Prerequisites ─────────────────────────────────────────────────────
step "Checking prerequisites"

command -v git >/dev/null || { echo "git not found - install it first."; exit 1; }

if ! command -v docker >/dev/null; then
  echo "Docker not found."
  if confirm "Install Docker now via apt?"; then
    sudo apt-get update
    sudo apt-get install -y docker.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "Added $USER to the docker group - log out/in (or 'newgrp docker') before continuing."
  else
    echo "Install Docker + the compose plugin, then re-run this script."; exit 1
  fi
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose plugin not found - install docker-compose-plugin, then re-run."
  exit 1
fi

if ! command -v nvidia-smi >/dev/null; then
  echo "nvidia-smi not found. This stack needs an NVIDIA GPU + driver for"
  echo "retrieval/pronunciation/tajweed-service (or set FORCE_CPU=1 in .env"
  echo "for a much slower CPU-only fallback). Install the NVIDIA driver first,"
  echo "then re-run this script."
  exit 1
fi
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader

if ! docker info 2>/dev/null | grep -qi "Default Runtime: nvidia"; then
  echo "NVIDIA is not Docker's default runtime yet."
  if confirm "Install nvidia-container-toolkit and configure Docker now?"; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
  else
    echo "GPU services will fail to start without this. Configure it, then re-run."
    exit 1
  fi
fi

# ── 2. Clone the repo (with submodules) if not already present ─────────
step "Repo checkout"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "This doesn't look like a git checkout - clone it first:"
  echo "  git clone --recurse-submodules https://github.com/Sedrah-AI/quraan-rag.git"
  exit 1
fi

git -C "$REPO_DIR" submodule update --init --recursive

# ── 3. Rsync what's only ever lived on the old machine ──────────────────
step "Syncing Postgres/Milvus data + golden embeddings from $SOURCE"

mkdir -p "$DATA_ROOT"/data/postgres_volumes \
         "$DATA_ROOT"/data/milvus_volumes

echo "Stop the source machine's postgres container first if you want a"
echo "perfectly consistent copy (rsyncing a live Postgres data dir can catch"
echo "an in-progress write). Safe to skip for a low-write dev box."
echo "Recommended: on $SOURCE_HOST, run 'docker stop quran-postgres' yourself"
echo "before continuing, then restart it afterward."
confirm "Have you stopped postgres on $SOURCE_HOST (or are you OK skipping that)?" || exit 1

rsync -avz --info=progress2 "$SOURCE:$DATA_ROOT/data/postgres_volumes/"        "$DATA_ROOT/data/postgres_volumes/"
rsync -avz --info=progress2 "$SOURCE:$DATA_ROOT/data/milvus_volumes/"          "$DATA_ROOT/data/milvus_volumes/"
rsync -avz --info=progress2 "$SOURCE:$REPO_DIR/quraan-agent/data/golden_embeddings/" \
                                      "$REPO_DIR/quraan-agent/data/golden_embeddings/"

# ── 4. .env ───────────────────────────────────────────────────────────────
step ".env setup"

if [ ! -f "$REPO_DIR/.env" ]; then
  cat > "$REPO_DIR/.env" <<'EOF'
# Postgres password - must match whatever the copied postgres_volumes was
# initialized with, since it's now a real data directory, not a fresh one.
POSTGRES_PASSWORD=quran_dev_password

# LLM answer backend: "local" (Ollama, default, no cost/API key) or "openai".
ANSWER_BACKEND=local
OPENAI_API_KEY=

# Set to 1 to run retrieval/pronunciation/tajweed-service on CPU instead of
# GPU (much slower - only use this if no NVIDIA GPU is available).
FORCE_CPU=0

# JWT signing secret for account-service - MUST be changed to a real random
# value for anything beyond local testing (this default is intentionally
# insecure and only meant as an obvious placeholder).
ACCOUNT_JWT_SECRET=change-me-to-a-real-random-secret

# Hugging Face token with read access to the SedraRagaad org - needed to
# download the two private fine-tuned model repos in the next step.
# Create one at https://huggingface.co/settings/tokens (fine-grained,
# scoped to the SedraRagaad org, "Read" is enough) or reuse an existing one.
HF_TOKEN=
EOF
  echo "Wrote a starter .env - edit ACCOUNT_JWT_SECRET, HF_TOKEN (and"
  echo "OPENAI_API_KEY if you want the OpenAI backend) before continuing."
  confirm "Continue with the values as written?" || { echo "Edit .env, then re-run."; exit 1; }
else
  echo ".env already exists - leaving it as-is."
fi

# Load .env now so HF_TOKEN etc. are available to the steps below.
set -a
# shellcheck disable=SC1091
source "$REPO_DIR/.env"
set +a

# ── 5. Download the fine-tuned models + base dataset from Hugging Face ──
step "Downloading models + dataset from Hugging Face"

python3 -c "import huggingface_hub" 2>/dev/null || pip install -q --user huggingface_hub

mkdir -p "$DATA_ROOT"/models "$DATA_ROOT"/data

python3 <<PYEOF
import os
from huggingface_hub import snapshot_download, hf_hub_download

token = os.environ.get("HF_TOKEN") or None

print("- ${HF_QURAN_WHISPER_REPO} -> ${DATA_ROOT}/models/quran-whisper")
snapshot_download(
    "${HF_QURAN_WHISPER_REPO}", repo_type="model", token=token,
    local_dir="${DATA_ROOT}/models/quran-whisper",
)

print("- ${HF_TAJWEED_REPO} -> ${DATA_ROOT}/models/wav2vec2-tajweed")
snapshot_download(
    "${HF_TAJWEED_REPO}", repo_type="model", token=token,
    local_dir="${DATA_ROOT}/models/wav2vec2-tajweed",
)

print("- ${HF_DATASET_REPO} (public) -> ${DATA_ROOT}/data/quran-audio-text-dataset")
archive_path = hf_hub_download(
    "${HF_DATASET_REPO}", "quran_audio_data.tar.gz", repo_type="dataset",
)
print("  downloaded archive:", archive_path)
PYEOF

if [ ! -d "$DATA_ROOT/data/quran-audio-text-dataset" ] || [ -z "$(ls -A "$DATA_ROOT/data/quran-audio-text-dataset" 2>/dev/null)" ]; then
  echo "Extracting the Quran audio/text dataset archive (this is the ~69GB one - slow)..."
  mkdir -p "$DATA_ROOT/data/quran-audio-text-dataset"
  ARCHIVE=$(find ~/.cache/huggingface/hub -name "quran_audio_data.tar.gz" | head -1)
  # NOTE: not verified against the actual archive's internal layout (69GB,
  # wasn't downloaded to check while writing this script). Extracting
  # without assuming a wrapping top-level directory - after this runs,
  # confirm content-service's expected files (quran_.json, reciters.json,
  # per-reciter audio folders - see wiki/Data.md) land directly under
  # $DATA_ROOT/data/quran-audio-text-dataset, not one level deeper. If
  # they're nested under a subdirectory instead, re-run with
  # 'tar --strip-components=1' or move the files up manually.
  tar -xzf "$ARCHIVE" -C "$DATA_ROOT/data/quran-audio-text-dataset"
fi

# ── 6. Ollama (host service, not containerized) ─────────────────────────
step "Ollama"

if ! command -v ollama >/dev/null; then
  echo "Ollama not found."
  if confirm "Install Ollama now (curl | sh from ollama.com)?"; then
    curl -fsSL https://ollama.com/install.sh | sh
  else
    echo "generation-service needs Ollama reachable at host.docker.internal:11434"
    echo "unless ANSWER_BACKEND=openai. Install it, then re-run."
    exit 1
  fi
fi

sudo systemctl enable --now ollama
if ! ollama list 2>/dev/null | grep -q "qwen2.5:7b-instruct"; then
  echo "Pulling qwen2.5:7b-instruct (~4.7GB)..."
  ollama pull qwen2.5:7b-instruct
fi

# ── 7. Build + start everything ─────────────────────────────────────────
step "docker compose build (this takes a while the first time)"
cd "$REPO_DIR"
docker compose build

step "docker compose up -d"
docker compose up -d

# ── 8. Wait for each service to report healthy ──────────────────────────
step "Waiting for services to come up"

wait_for() {
  local name="$1" url="$2" tries=60
  echo -n "  $name "
  for _ in $(seq 1 "$tries"); do
    if curl -sf "$url" >/dev/null 2>&1; then echo "OK"; return 0; fi
    echo -n "."
    sleep 5
  done
  echo "TIMED OUT - check 'docker logs $name'"
  return 1
}

wait_for content-service        http://localhost:8101/health
wait_for retrieval-service      http://localhost:8102/health
wait_for generation-service     http://localhost:8103/health
wait_for pronunciation-service  http://localhost:8104/health
wait_for tajweed-service        http://localhost:8105/health
wait_for account-service        http://localhost:8106/health
wait_for gateway-service        http://localhost:8000/api/health

step "Done"
echo "App is live at http://localhost:8000/"
echo "Check 'docker compose ps' for container status and 'docker compose logs -f <service>' for any that failed."
