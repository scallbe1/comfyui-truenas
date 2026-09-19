FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04

ARG COMFYUI_REF=v0.36.0
ARG TORCH_VERSION=2.11.0
ARG TORCHVISION_VERSION=0.26.0
ARG TORCHAUDIO_VERSION=2.11.0
ARG LLAMA_CPP_PYTHON_REF=34c1bfbce3ad485d31e67039fa9200e6ab49882e

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

RUN printf '%s\n' \
        'numpy==1.26.4' \
        'torch==2.11.0' \
        'torchvision==0.26.0' \
        'torchaudio==2.11.0' \
        > /opt/pip-constraints.txt

ENV PIP_CONSTRAINT=/opt/pip-constraints.txt

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

RUN git clone --filter=blob:none \
        https://github.com/Comfy-Org/ComfyUI.git . \
    && git checkout --detach "${COMFYUI_REF}" \
    && git rev-parse HEAD | tee /opt/comfyui-git-commit.txt \
    && python3 -m pip install --no-cache-dir -r requirements.txt \
    && python3 -m pip install --no-cache-dir -r manager_requirements.txt

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
    diskcache \
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

RUN python3 -m pip install --no-cache-dir --no-deps \
    easyocr \
    "rembg==2.0.67"

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

RUN python3 -m spacy download xx_sent_ud_sm

RUN wget -q -O /tmp/google-chrome.deb \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/google-chrome.deb \
    && rm -f /tmp/google-chrome.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip install --no-cache-dir \
    git+https://github.com/facebookresearch/sam2.git

RUN python3 -m pip install --no-cache-dir --upgrade \
    --extra-index-url https://pypi.nvidia.com \
    nvidia-vfx

RUN git clone --depth 1 \
        https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git \
        /opt/ComfyUI-SeedVR2_VideoUpscaler \
    && sed 's/^opencv-python$/opencv-python-headless/' \
        /opt/ComfyUI-SeedVR2_VideoUpscaler/requirements.txt \
        > /opt/seedvr2-requirements.txt \
    && python3 -m pip install --no-cache-dir -r /opt/seedvr2-requirements.txt \
    && test -f /opt/ComfyUI-SeedVR2_VideoUpscaler/inference_cli.py

RUN git clone --depth 1 \
        https://github.com/Jalen-Brunson/ComfyUI-MiniMax-H3-PDD-Acc.git \
        /opt/ComfyUI-MiniMax-H3-PDD-Acc

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

RUN python3 -m pip install --no-cache-dir --no-deps \
    "xformers==0.0.35" \
    --index-url https://download.pytorch.org/whl/cu130

RUN python3 -m pip install --no-cache-dir --no-deps \
    "sageattention==1.0.6"

RUN python3 -m pip install --no-cache-dir \
    faster-whisper \
    huggingface-hub \
    nvidia-cublas-cu12 \
    "nvidia-cudnn-cu12==9.*"

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

RUN python3 -m pip uninstall -y onnxruntime onnxruntime-gpu || true \
    && python3 -m pip install --no-cache-dir \
        "onnxruntime-gpu==1.30.0"

RUN python3 -m pip uninstall -y llama-cpp-python llama_cpp_python || true \
    && rm -rf /tmp/llama-cpp-python \
    && git clone --filter=blob:none --no-checkout \
        https://github.com/JamePeng/llama-cpp-python.git \
        /tmp/llama-cpp-python \
    && cd /tmp/llama-cpp-python \
    && git checkout --detach "${LLAMA_CPP_PYTHON_REF}" \
    && git submodule update --init --recursive \
    && CMAKE_ARGS="-DGGML_CUDA=ON -DGGML_BACKEND_DL=OFF -DCMAKE_CUDA_ARCHITECTURES=86" \
       FORCE_CMAKE=1 \
       CUDACXX=/usr/local/cuda/bin/nvcc \
       python3 -m pip install --no-cache-dir --no-deps --force-reinstall . \
    && cd / \
    && rm -rf /tmp/llama-cpp-python

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

RUN python3 - <<'PY'
from importlib.metadata import PackageNotFoundError, version

import av
import diskcache
import llama_cpp
import numpy
import onnxruntime as ort
import torch
import torchaudio
import torchvision
from pathlib import Path
from comfyui_version import __version__ as comfyui_version

commit_file = Path("/opt/comfyui-git-commit.txt")
comfyui_commit = commit_file.read_text(encoding="utf-8").strip() if commit_file.exists() else "unknown"

print("ComfyUI reported version:", comfyui_version)
print("ComfyUI git commit:", comfyui_commit)
print("PyAV:", av.__version__)
print("PyTorch:", torch.__version__)
print("Torchvision:", torchvision.__version__)
print("Torchaudio:", torchaudio.__version__)
print("PyTorch CUDA build:", torch.version.cuda)
print("NumPy:", numpy.__version__)
print("ONNX Runtime:", ort.__version__)
print("ONNX Runtime providers:", ort.get_available_providers())

if "CUDAExecutionProvider" not in ort.get_available_providers():
    raise SystemExit("ERROR: ONNX Runtime CUDAExecutionProvider is unavailable")

try:
    cpu_ort = version("onnxruntime")
except PackageNotFoundError:
    cpu_ort = None

if cpu_ort is not None:
    raise SystemExit(
        f"ERROR: CPU onnxruntime distribution is installed ({cpu_ort}); "
        "only onnxruntime-gpu should remain"
    )

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

RUN cat > /usr/local/bin/comfyui-entrypoint <<'SHENTRY'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
    "${XDG_CONFIG_HOME}" \
    "${YOLO_CONFIG_DIR}" \
    "${MPLCONFIGDIR}" \
    "${TORCH_EXTENSIONS_DIR}"

SEEDVR2_IMAGE_DIR=/opt/ComfyUI-SeedVR2_VideoUpscaler
SEEDVR2_NODE_DIR=/app/ComfyUI/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler
mkdir -p /app/ComfyUI/custom_nodes /app/ComfyUI/models/SEEDVR2

if [[ ! -L "${SEEDVR2_NODE_DIR}" ]] || [[ "$(readlink "${SEEDVR2_NODE_DIR}")" != "${SEEDVR2_IMAGE_DIR}" ]]; then
    if [[ -e "${SEEDVR2_NODE_DIR}" || -L "${SEEDVR2_NODE_DIR}" ]]; then
        SEEDVR2_BACKUP_ROOT=/app/ComfyUI/user/custom-node-backups
        mkdir -p "${SEEDVR2_BACKUP_ROOT}"
        SEEDVR2_BACKUP="${SEEDVR2_BACKUP_ROOT}/ComfyUI-SeedVR2_VideoUpscaler-$(date -u +%Y%m%dT%H%M%SZ)-$$"
        mv "${SEEDVR2_NODE_DIR}" "${SEEDVR2_BACKUP}"
        echo "[INFO] Existing SeedVR2 installation backed up to ${SEEDVR2_BACKUP}"
    fi
    ln -s "${SEEDVR2_IMAGE_DIR}" "${SEEDVR2_NODE_DIR}"
fi

echo "[INFO] SeedVR2 ready at ${SEEDVR2_NODE_DIR}; models persist in /app/ComfyUI/models/SEEDVR2"

PDD_IMAGE_DIR=/opt/ComfyUI-MiniMax-H3-PDD-Acc
PDD_NODE_DIR=/app/ComfyUI/custom_nodes/ComfyUI-MiniMax-H3-PDD-Acc
mkdir -p /app/ComfyUI/models/pdd_acc

if [[ ! -L "${PDD_NODE_DIR}" ]] || [[ "$(readlink "${PDD_NODE_DIR}")" != "${PDD_IMAGE_DIR}" ]]; then
    if [[ -e "${PDD_NODE_DIR}" || -L "${PDD_NODE_DIR}" ]]; then
        PDD_BACKUP_ROOT=/app/ComfyUI/user/custom-node-backups
        mkdir -p "${PDD_BACKUP_ROOT}"
        PDD_BACKUP="${PDD_BACKUP_ROOT}/ComfyUI-MiniMax-H3-PDD-Acc-$(date -u +%Y%m%dT%H%M%SZ)-$$"
        mv "${PDD_NODE_DIR}" "${PDD_BACKUP}"
        echo "[INFO] Existing MiniMax H3 PDD Acc installation backed up to ${PDD_BACKUP}"
    fi
    ln -s "${PDD_IMAGE_DIR}" "${PDD_NODE_DIR}"
fi

echo "[INFO] MiniMax H3 PDD Acc ready at ${PDD_NODE_DIR}; PDD models persist in /app/ComfyUI/models/pdd_acc"

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

for legacy_manager in \
    /app/ComfyUI/custom_nodes/ComfyUI-Manager \
    /app/ComfyUI/custom_nodes/comfyui-manager
do
    if [[ -d "${legacy_manager}" ]]; then
        echo "[WARN] Old ComfyUI-Manager custom-node clone detected: ${legacy_manager}"
        echo "[WARN] This ComfyUI build uses the integrated Manager package; remove the old clone if it causes duplicate/blocked Manager messages."
    fi
done

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

RUN sed -i 's/\r$//' /usr/local/bin/comfyui-entrypoint \
    && chmod +x /usr/local/bin/comfyui-entrypoint \
    && bash -n /usr/local/bin/comfyui-entrypoint

EXPOSE 8188

ENTRYPOINT ["/usr/local/bin/comfyui-entrypoint"]

CMD ["--listen", "0.0.0.0", "--port", "8188", "--enable-dynamic-vram", "--enable-manager", "--enable-manager-legacy-ui"]
