FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04

# v0.33.1 does NOT contain the native arbitrary-guide / Ref2VA merge support
# required by ComfyUI-H3-Motion-Context-MultiRef. PR #15439 landed as e01fb4c.
# Pin the exact commit for a reproducible build.
ARG COMFYUI_REF=e01fb4c
ARG TORCH_VERSION=2.11.0
ARG TORCHVISION_VERSION=0.26.0
ARG TORCHAUDIO_VERSION=2.11.0
ARG LLAMA_CPP_PYTHON_VERSION=0.3.34

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_DEFAULT_TIMEOUT=300 \
    PIP_RETRIES=10 \
    UV_BREAK_SYSTEM_PACKAGES=true \
    UV_SYSTEM_PYTHON=true \
    UV_NO_PROGRESS=true \
    UV_CONFIG_FILE=/etc/uv/uv.toml \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app/ComfyUI \
    PYTHONWARNINGS=ignore::FutureWarning,ignore::SyntaxWarning \
    XDG_CONFIG_HOME=/app/ComfyUI/user/.config \
    YOLO_CONFIG_DIR=/app/ComfyUI/user/.config/Ultralytics \
    MPLCONFIGDIR=/app/ComfyUI/user/.cache/matplotlib \
    CHROME_BIN=/usr/bin/google-chrome \
    TORCH_EXTENSIONS_DIR=/app/ComfyUI/user/.cache/torch_extensions \
    HF_HOME=/opt/huggingface \
    HF_HUB_CACHE=/opt/huggingface/hub \
    HF_HUB_DOWNLOAD_TIMEOUT=300 \
    HF_HUB_DISABLE_TELEMETRY=1 \
    FASTER_WHISPER_MODEL_REPO=Systran/faster-whisper-large-v3 \
    CUDA_HOME=/usr/local/cuda \
    CUDACXX=/usr/local/cuda/bin/nvcc \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    CMAKE_BUILD_PARALLEL_LEVEL=2 \
    MAX_JOBS=2

WORKDIR /app/ComfyUI

# -----------------------------------------------------------------------------
# OS dependencies
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    wget \
    python3 \
    python3-dev \
    python3-pip \
    python-is-python3 \
    ffmpeg \
    libgl1 \
    libglx-mesa0 \
    libopengl0 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libegl1 \
    libgles2 \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    gfortran \
    rustc \
    cargo \
    libopenblas-dev \
    liblapack-dev \
    libjpeg-dev \
    libpng-dev \
    zlib1g-dev \
    libraw-dev \
    libopenexr-dev \
    libimath-dev \
    rsync \
    libsndfile1 \
    libsndfile1-dev \
    portaudio19-dev \
    libasound2-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 protects its system Python with PEP 668. We intentionally use the
# container's system Python and tell pip that this is an isolated container.
RUN printf '%s\n' \
        '[global]' \
        'break-system-packages = true' \
        'timeout = 300' \
        'retries = 10' \
        > /etc/pip.conf \
    && mkdir -p /etc/uv \
    && printf '%s\n' \
        '[pip]' \
        'system = true' \
        'break-system-packages = true' \
        > /etc/uv/uv.toml

# Keep only the critical compute stack pinned. Do NOT pin transitive packages
# such as ONNX Runtime here; doing so made the previous image unnecessarily
# fragile when another package legitimately installed a newer release.
RUN printf '%s\n' \
        'numpy==1.26.4' \
        'torch==2.11.0' \
        'torchvision==0.26.0' \
        'torchaudio==2.11.0' \
        > /opt/pip-constraints.txt

ENV PIP_CONSTRAINT=/opt/pip-constraints.txt

# -----------------------------------------------------------------------------
# Python build tooling and CUDA PyTorch
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir --ignore-installed \
    "setuptools<81" \
    wheel \
    cython \
    uv \
    "numpy==1.26.4"

RUN python3 -m pip install --no-cache-dir \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" \
    --index-url https://download.pytorch.org/whl/cu130

# -----------------------------------------------------------------------------
# ComfyUI core + integrated Manager
#
# IMPORTANT:
# ComfyUI-H3-Motion-Context-MultiRef requires the native MiniMax H3 arbitrary
# guide / MultiRef merge support introduced by ComfyUI PR #15439.
# v0.33.1 does not contain that commit, so use the exact H3-capable commit.
#
# --filter=blob:none keeps the Git checkout much smaller than a normal full
# clone while retaining commit history, which lets an exact commit be checked
# out reliably.
# -----------------------------------------------------------------------------
RUN git clone --filter=blob:none \
        https://github.com/Comfy-Org/ComfyUI.git . \
    && git checkout --detach "${COMFYUI_REF}" \
    && git rev-parse HEAD | tee /opt/comfyui-git-commit.txt \
    && python3 -m pip install --no-cache-dir -r requirements.txt \
    && python3 -m pip install --no-cache-dir -r manager_requirements.txt

# Fail the Docker build immediately if the checked-out source does not contain
# the H3 capability required by ComfyUI-H3-Motion-Context-MultiRef.
#
# IMPORTANT: this intentionally parses the source with Python's AST instead of
# importing comfy_extras.nodes_minimax_h3. Importing that module during image
# construction initializes a large part of ComfyUI and can produce unrelated
# build-time failures even when the required H3 code is present.
RUN python3 - <<'PYH3'
import ast
from pathlib import Path

model_path = Path("/app/ComfyUI/comfy/ldm/minimax/model.py")
nodes_path = Path("/app/ComfyUI/comfy_extras/nodes_minimax_h3.py")
base_path = Path("/app/ComfyUI/comfy/model_base.py")

for path in (model_path, nodes_path, base_path):
    if not path.is_file():
        raise RuntimeError(f"Required ComfyUI source file missing: {path}")

model_tree = ast.parse(model_path.read_text(encoding="utf-8"), filename=str(model_path))
nodes_tree = ast.parse(nodes_path.read_text(encoding="utf-8"), filename=str(nodes_path))

# PR #15439 changes PackedLayout.__init__ so arbitrary guides no longer depend
# on the old frame_count/first-or-last-only keyframe implementation.
packed_init = None
for node in model_tree.body:
    if isinstance(node, ast.ClassDef) and node.name == "PackedLayout":
        for item in node.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)) and item.name == "__init__":
                packed_init = item
                break
        break

if packed_init is None:
    raise RuntimeError("Could not find PackedLayout.__init__ in MiniMax H3 model.py")

args = [a.arg for a in packed_init.args.args]
if "frame_count" in args:
    raise RuntimeError(
        "MiniMax H3 PR #15439 capability is missing: "
        "PackedLayout.__init__ still contains legacy frame_count."
    )

for required in ("keyframes", "refs"):
    if required not in args:
        raise RuntimeError(
            f"MiniMax H3 PackedLayout.__init__ is missing required argument: {required}"
        )

node_classes = {
    node.name
    for node in nodes_tree.body
    if isinstance(node, ast.ClassDef)
}
if "MiniMaxH3AddGuide" not in node_classes:
    raise RuntimeError(
        "MiniMaxH3AddGuide is missing from comfy_extras/nodes_minimax_h3.py"
    )

# PR #15439 also fixes Ref2VA + guide merging. Check the source contains the
# append/merge behavior rather than overwriting guide conditioning.
base_source = base_path.read_text(encoding="utf-8")
required_fragments = (
    'payload.get("cond_video_latents", []) +',
    'payload.get("cond_audio_latents", []) +',
)
for fragment in required_fragments:
    if fragment not in base_source:
        raise RuntimeError(
            "MiniMax H3 Ref2VA/guide merge support is incomplete; "
            f"missing source fragment: {fragment}"
        )

print("MiniMax H3 PR #15439 source capability check: PASS")
print("PackedLayout args:", args)
print("MiniMaxH3AddGuide: present")
print("Ref2VA + guide latent merge: present")
PYH3

# -----------------------------------------------------------------------------
# General custom-node dependencies
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir \
    GitPython \
    dill \
    py-cpuinfo \
    toml \
    nvidia-ml-py \
    color-matcher \
    chardet \
    deepdiff \
    piexif \
    requirements-parser \
    rich \
    rich-argparse \
    cachetools \
    qrcode[pil] \
    google-cloud-storage \
    "PyOpenGL==3.1.10" \
    "PyOpenGL-accelerate==3.1.10"

RUN python3 -m pip install --no-cache-dir \
    gguf \
    opencv-python-headless \
    imageio-ffmpeg \
    PyWavelets \
    matplotlib \
    soundfile \
    sentencepiece \
    transformers \
    accelerate \
    av \
    einops \
    scikit-image \
    peft \
    supervision \
    glfw \
    ultralytics \
    timm \
    fvcore \
    onnx \
    safetensors \
    facexlib \
    basicsr \
    insightface \
    segment-anything \
    open-clip-torch \
    "bitsandbytes>=0.50.0" \
    glitch_this \
    mediapipe \
    diffusers \
    kornia \
    "ninja~=1.11.1.4" \
    dynamicprompts \
    tiktoken

RUN python3 -m pip install --no-cache-dir \
    scipy \
    librosa \
    pedalboard \
    pyloudnorm \
    noisereduce \
    demucs \
    reportlab \
    PyPDF2 \
    PyMuPDF \
    rotary_embedding_torch

RUN python3 -m pip install --no-cache-dir \
    fal-client \
    runwayml \
    openai \
    "openai-whisper==20250625" \
    ollama \
    gdown \
    google-generativeai \
    google-genai \
    langchain-community \
    langchain-openai \
    markdownify \
    neo4j \
    docx2txt \
    openpyxl \
    pdfplumber \
    xlrd \
    wikipedia \
    streamlit \
    websocket-client

# Dependencies used by the mounted custom-node collection.
RUN python3 -m pip install --no-cache-dir \
    python-bidi \
    PyYAML \
    Shapely \
    pyclipper \
    jsonschema \
    pooch \
    pymatting \
    lark \
    deep-translator \
    googletrans-py \
    "git+https://github.com/argosopentech/argos-translate.git@08f017c324628434d671cf4d191ce681c620ff33" \
    "stanza==1.10.1" \
    sacremoses \
    spacy \
    html2image==2.0.3 \
    srt \
    pydub \
    ffmpeg-python \
    "py-cord[voice]" \
    llama-index \
    feedparser \
    selenium \
    mdtex2html \
    keyboard \
    "moviepy==1.0.3" \
    sounddevice \
    "colour-science==0.4.6" \
    "rawpy==0.25.1" \
    "OpenEXR==3.4.12"

# These packages otherwise try to replace large parts of the already-working
# CUDA / ONNX / image stack. Their required runtime dependencies are installed
# explicitly elsewhere in this image.
RUN python3 -m pip install --no-cache-dir --no-deps \
    easyocr \
    "rembg==2.0.67"

# General segmentation / CV dependencies.
# Detectron2 / DensePose are intentionally omitted.
RUN python3 -m pip install --no-cache-dir \
    cloudpickle \
    future \
    hydra-core \
    iopath \
    omegaconf \
    pycocotools \
    pydot \
    tensorboard \
    termcolor \
    yacs

# Multilingual sentence splitter used by AlekPet translation nodes.
RUN python3 -m spacy download xx_sent_ud_sm

# -----------------------------------------------------------------------------
# Chrome for html2image / Selenium nodes
# -----------------------------------------------------------------------------
RUN wget -q -O /tmp/google-chrome.deb \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/google-chrome.deb \
    && rm -f /tmp/google-chrome.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# SAM2 and NVIDIA VFX
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir \
    git+https://github.com/facebookresearch/sam2.git

RUN python3 -m pip install --no-cache-dir --upgrade \
    --extra-index-url https://pypi.nvidia.com \
    nvidia-vfx

# -----------------------------------------------------------------------------
# Re-establish the critical numerical / PyTorch stack after broad dependencies.
# This is intentional: custom-node packages are allowed to resolve their own
# dependencies, then the known-good compute stack is restored once at the end.
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir --upgrade --force-reinstall \
    "numpy==1.26.4" \
    "pandas<3" \
    "scikit-learn<2" \
    PyWavelets

RUN python3 -m pip install --no-cache-dir --force-reinstall --no-deps \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" \
    --index-url https://download.pytorch.org/whl/cu130

# xFormers 0.0.35 uses the PyTorch stable ABI for PyTorch 2.10+.
RUN python3 -m pip install --no-cache-dir --no-deps \
    "xformers==0.0.35" \
    --index-url https://download.pytorch.org/whl/cu130

# SageAttention V1 is Triton based and works without compiling an image-specific
# CUDA extension at Docker build time.
RUN python3 -m pip install --no-cache-dir --no-deps \
    "sageattention==1.0.6"

# -----------------------------------------------------------------------------
# llama-cpp-python
#
# Prefer the project's official CUDA 13 wheel. If pip cannot find that wheel,
# --prefer-binary still permits a source fallback using the CUDA build flags
# below rather than depending on a hard-coded installed-library path.
# -----------------------------------------------------------------------------
RUN CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_CUDA_ARCHITECTURES=86;89;120" \
    FORCE_CMAKE=1 \
    python3 -m pip install --no-cache-dir --upgrade --force-reinstall \
        --prefer-binary \
        "llama-cpp-python==${LLAMA_CPP_PYTHON_VERSION}" \
        --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cu130

# -----------------------------------------------------------------------------
# faster-whisper / CTranslate2
#
# CTranslate2 currently relies on CUDA 12 user-space libraries. Those can live
# alongside the CUDA 13 ComfyUI/PyTorch stack. The entrypoint discovers their
# actual site-packages paths dynamically at runtime.
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir \
    faster-whisper \
    huggingface-hub \
    nvidia-cublas-cu12 \
    "nvidia-cudnn-cu12==9.*"

# Ensure the correct OpenAI Whisper distribution owns `import whisper`.
RUN python3 -m pip uninstall -y \
        whisper \
        openai-whisper \
        PyOpenGL \
        PyOpenGL-accelerate || true \
    && python3 -m pip install --no-cache-dir --no-deps \
        "openai-whisper==20250625" \
        "PyOpenGL==3.1.10" \
    && python3 -m pip install --no-cache-dir --no-deps \
        --force-reinstall \
        "PyOpenGL-accelerate==3.1.10"

# -----------------------------------------------------------------------------
# ONNX Runtime
#
# Some custom-node dependencies install the CPU `onnxruntime` distribution,
# while others expect `onnxruntime-gpu`. Both provide the same Python import
# name and installing both can overwrite files unpredictably.
#
# Resolve that once, at the END of dependency installation. We intentionally
# use a compatible range rather than asserting one exact transitive version.
# -----------------------------------------------------------------------------
RUN python3 -m pip uninstall -y onnxruntime onnxruntime-gpu || true \
    && python3 -m pip install --no-cache-dir \
        "onnxruntime-gpu>=1.28,<1.30"

# -----------------------------------------------------------------------------
# Bake faster-whisper large-v3 into the image
# -----------------------------------------------------------------------------
RUN mkdir -p "${HF_HUB_CACHE}" \
    && python3 - <<'PY'
import os
from huggingface_hub import snapshot_download

path = snapshot_download(
    repo_id=os.environ["FASTER_WHISPER_MODEL_REPO"],
    cache_dir=os.environ["HF_HUB_CACHE"],
)
print("Downloaded faster-whisper model to:", path)
PY

RUN chmod -R a+rX "${HF_HOME}"

# -----------------------------------------------------------------------------
# Non-brittle build smoke test
#
# This intentionally checks only that the core Python packages can be imported
# and reports versions. It does NOT fail because a transitive dependency moved
# from x.y.0 to x.y.1, and it does NOT assume package files live at a hard-coded
# Python path.
# -----------------------------------------------------------------------------
RUN python3 - <<'PY'
from importlib.metadata import PackageNotFoundError, version

import numpy
import torch
import torchaudio
import torchvision
from pathlib import Path
from comfyui_version import __version__ as comfyui_version

commit_file = Path("/opt/comfyui-git-commit.txt")
comfyui_commit = commit_file.read_text(encoding="utf-8").strip() if commit_file.exists() else "unknown"

print("ComfyUI reported version:", comfyui_version)
print("ComfyUI git commit:", comfyui_commit)
print("PyTorch:", torch.__version__)
print("Torchvision:", torchvision.__version__)
print("Torchaudio:", torchaudio.__version__)
print("PyTorch CUDA build:", torch.version.cuda)
print("NumPy:", numpy.__version__)

for package in (
    "comfyui_manager",
    "onnxruntime-gpu",
    "xformers",
    "sageattention",
    "llama-cpp-python",
    "faster-whisper",
    "openai-whisper",
    "PyOpenGL-accelerate",
):
    try:
        print(f"{package}: {version(package)}")
    except PackageNotFoundError:
        print(f"{package}: package metadata not found")
PY

# -----------------------------------------------------------------------------
# Runtime entrypoint
# -----------------------------------------------------------------------------
RUN cat > /usr/local/bin/comfyui-entrypoint <<'SHENTRY'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
    "${XDG_CONFIG_HOME}" \
    "${YOLO_CONFIG_DIR}" \
    "${MPLCONFIGDIR}" \
    "${TORCH_EXTENSIONS_DIR}"

# Find NVIDIA CUDA 12 user-space libraries installed by pip without hard-coding
# the Python minor version or site-packages directory.
PY_SITE="$(python3 - <<'PY'
import site
paths = site.getsitepackages()
print(paths[0] if paths else "")
PY
)"

if [[ -n "${PY_SITE}" ]]; then
    for cuda_lib_dir in \
        "${PY_SITE}/nvidia/cublas/lib" \
        "${PY_SITE}/nvidia/cudnn/lib"
    do
        if [[ -d "${cuda_lib_dir}" ]]; then
            export LD_LIBRARY_PATH="${cuda_lib_dir}:${LD_LIBRARY_PATH:-}"
        fi
    done
fi

# Compile JIT extensions only for CUDA architectures actually visible to the
# container. This supports homogeneous or mixed visible GPU sets and avoids
# compiling unused architectures.
RUNTIME_CUDA_ARCH="$(python3 - <<'PY' 2>/dev/null || true
import torch

if torch.cuda.is_available():
    caps = sorted({
        torch.cuda.get_device_capability(i)
        for i in range(torch.cuda.device_count())
    })
    print(";".join(f"{major}.{minor}" for major, minor in caps))
PY
)"

if [[ -n "${RUNTIME_CUDA_ARCH}" ]]; then
    export TORCH_CUDA_ARCH_LIST="${RUNTIME_CUDA_ARCH}"
    echo "[INFO] Runtime CUDA architectures: ${TORCH_CUDA_ARCH_LIST}"
fi

# Point WAS Node Suite at the system ffmpeg binary if the node is mounted.
# Failure to update this optional config must never prevent ComfyUI from booting.
python3 - <<'PYWAS' || true
import json
from pathlib import Path

path = Path("/app/ComfyUI/custom_nodes/was-ns/was_suite_config.json")

if path.parent.is_dir():
    try:
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except (json.JSONDecodeError, OSError):
        data = {}

    data["ffmpeg_bin_path"] = "/usr/bin/ffmpeg"

    try:
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    except OSError as exc:
        print(f"[WARN] Could not update WAS ffmpeg path: {exc}")
PYWAS

# Warn about an old Manager clone in the persistent custom_nodes dataset.
# Do not delete or rename user data automatically.
for legacy_manager in \
    /app/ComfyUI/custom_nodes/ComfyUI-Manager \
    /app/ComfyUI/custom_nodes/comfyui-manager
do
    if [[ -d "${legacy_manager}" ]]; then
        echo "[WARN] Old ComfyUI-Manager custom-node clone detected: ${legacy_manager}"
        echo "[WARN] This ComfyUI build uses the integrated Manager package; remove the old clone if it causes duplicate/blocked Manager messages."
    fi
done

# Keep the TrueNAS application alive across Manager-requested ComfyUI restarts.
COMFY_SESSION=/tmp/comfyui-cli-session
export __COMFY_CLI_SESSION__="${COMFY_SESSION}"

child_pid=""

stop_child() {
    if [[ -n "${child_pid}" ]] && kill -0 "${child_pid}" 2>/dev/null; then
        kill -TERM "${child_pid}" 2>/dev/null || true
        wait "${child_pid}" 2>/dev/null || true
    fi
    exit 143
}

trap stop_child TERM INT

while true; do
    rm -f "${COMFY_SESSION}.reboot"

    (
        cd /app/ComfyUI
        exec python3 /app/ComfyUI/main.py "$@"
    ) &
    child_pid=$!

    set +e
    wait "${child_pid}"
    status=$?
    set -e
    child_pid=""

    if [[ -f "${COMFY_SESSION}.reboot" ]]; then
        rm -f "${COMFY_SESSION}.reboot"
        echo "[INFO] ComfyUI Manager requested a restart; relaunching ComfyUI."
        continue
    fi

    exit "${status}"
done
SHENTRY

# Git / Windows editors may save this Dockerfile with CRLF. Strip CRLF from the
# generated entrypoint, validate shell syntax, and make it executable.
RUN sed -i 's/\r$//' /usr/local/bin/comfyui-entrypoint \
    && chmod +x /usr/local/bin/comfyui-entrypoint \
    && bash -n /usr/local/bin/comfyui-entrypoint

EXPOSE 8188

ENTRYPOINT ["/usr/local/bin/comfyui-entrypoint"]

# --enable-manager-legacy-ui implies Manager support in current ComfyUI, but
# keeping --enable-manager explicitly makes the intent obvious.
CMD ["--listen", "0.0.0.0", "--port", "8188", "--enable-dynamic-vram", "--enable-manager", "--enable-manager-legacy-ui"]
