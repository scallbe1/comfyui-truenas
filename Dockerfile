FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04

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
    PYTHONWARNINGS=ignore::FutureWarning,ignore::SyntaxWarning \
    XDG_CONFIG_HOME=/app/ComfyUI/user/.config \
    YOLO_CONFIG_DIR=/app/ComfyUI/user/.config/Ultralytics \
    MPLCONFIGDIR=/app/ComfyUI/user/.cache/matplotlib \
    CHROME_BIN=/usr/bin/google-chrome

# CUDA build/runtime paths.
ENV CUDA_HOME=/usr/local/cuda \
    CUDACXX=/usr/local/cuda/bin/nvcc \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Limit compiler parallelism for GitHub-hosted runners while producing a
# portable CUDA build for RTX 3090 (SM 8.6), RTX 4090 (SM 8.9), and
# RTX 5090-class Blackwell GPUs (SM 12.0).
ENV CMAKE_BUILD_PARALLEL_LEVEL=2 \
    MAX_JOBS=2 \
    FORCE_CMAKE=1 \
    TORCH_CUDA_ARCH_LIST="8.6;8.9;12.0" \
    CMAKE_ARGS="-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86;89;120"

# Persistent location inside the image for Hugging Face models.
# Do not mount an empty dataset over /opt/huggingface or it will hide
# the model downloaded into the image during the build.
ENV HF_HOME=/opt/huggingface \
    HF_HUB_CACHE=/opt/huggingface/hub \
    HF_HUB_DOWNLOAD_TIMEOUT=300 \
    FASTER_WHISPER_MODEL_REPO=Systran/faster-whisper-large-v3

ARG COMFYUI_VERSION=v0.30.0
ARG TORCH_VERSION=2.11.0
ARG TORCHVISION_VERSION=0.26.0
ARG TORCHAUDIO_VERSION=2.11.0
ARG ONNXRUNTIME_VERSION=1.28.0
ARG LLAMA_CPP_PYTHON_VERSION=0.3.34

# System tools, Python, build dependencies, audio libraries, and vision libraries.
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
    libegl1 \
    libgles2 \
    rsync \
    libsndfile1 \
    libsndfile1-dev \
    portaudio19-dev \
    libasound2-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Allow pip installations into Ubuntu's system Python without attempting to
# replace Debian's pip package. All pip-installed packages go under /usr/local.
RUN printf '%s\n' \
        '[global]' \
        'break-system-packages = true' \
        'timeout = 300' \
        'retries = 10' \
        > /etc/pip.conf && \
    mkdir -p /etc/uv && \
    printf '%s\n' \
        '[pip]' \
        'system = true' \
        'break-system-packages = true' \
        > /etc/uv/uv.toml && \
    printf '%s\n' \
        'numpy==1.26.4' \
        'torch==2.11.0' \
        'torchvision==0.26.0' \
        'torchaudio==2.11.0' \
        'onnxruntime-gpu==1.28.0' \
        > /opt/pip-constraints.txt

ENV PIP_CONSTRAINT=/opt/pip-constraints.txt \
    UV_CONSTRAINT=/opt/pip-constraints.txt

WORKDIR /app/ComfyUI

# Base Python tooling. Do not upgrade pip itself: Ubuntu installed pip through
# apt, and replacing that Debian-managed package causes a missing RECORD error.
# --ignore-installed places current build tooling under /usr/local without
# uninstalling the Ubuntu packages under /usr/lib.
RUN python3 -m pip install --no-cache-dir --ignore-installed \
    "setuptools<81" \
    wheel \
    cython \
    uv \
    "numpy==1.26.4"

# PyTorch CUDA 13.0 stack. The three versions are kept as a matched set.
RUN python3 -m pip install --no-cache-dir \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" \
    --index-url https://download.pytorch.org/whl/cu130

# ComfyUI v0.30.0 and its pinned dependencies, including comfy-aimdo.
RUN git clone --depth 1 --branch "${COMFYUI_VERSION}" \
        https://github.com/Comfy-Org/ComfyUI.git . && \
    python3 -m pip install --no-cache-dir -r requirements.txt

# Core utilities and monitoring packages.
RUN python3 -m pip install --no-cache-dir \
    GitPython \
    dill \
    py-cpuinfo \
    toml \
    nvidia-ml-py \
    color-matcher \
    chardet==5.2.0 \
    deepdiff \
    piexif \
    requirements-parser \
    rich \
    rich-argparse \
    cachetools \
    qrcode[pil] \
    google-cloud-storage \
    PyOpenGL \
    PyOpenGL-accelerate

# Vision, modeling, face, segmentation, diffusion, and GPU inference packages.
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
    "onnxruntime-gpu==${ONNXRUNTIME_VERSION}" \
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

# Audio, math, document, and utility packages.
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

# Cloud, speech-to-text, LLM/API, and document helper packages.
# stable-audio-tools is intentionally omitted because it pins pandas 2.0.2,
# which has no Python 3.12 wheel and fails while building from source.
RUN python3 -m pip install --no-cache-dir \
    fal-client \
    runwayml \
    openai \
    openai-whisper \
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

# Dependencies reported missing by the mounted custom-node collection.
# EasyOCR and rembg are installed without dependencies so they reuse the existing
# CUDA PyTorch, ONNX Runtime GPU, headless OpenCV, NumPy, SciPy and image stack.
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

# Bake the multilingual sentence splitter used by AlekPet translation nodes.
RUN python3 -m spacy download xx_sent_ud_sm

# Install Chrome so html2image and Selenium nodes have an actual browser.
RUN wget -q -O /tmp/google-chrome.deb \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends /tmp/google-chrome.deb && \
    rm -f /tmp/google-chrome.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# SAM2.
RUN python3 -m pip install --no-cache-dir \
    git+https://github.com/facebookresearch/sam2.git

# NVIDIA Video Effects SDK Python bindings.
RUN python3 -m pip install --no-cache-dir --upgrade \
    --extra-index-url https://pypi.nvidia.com \
    nvidia-vfx

# Re-pin common numeric/data packages after broad dependency installation.
RUN python3 -m pip install --no-cache-dir --upgrade --force-reinstall \
    "numpy==1.26.4" \
    "pandas<3" \
    "scikit-learn<2" \
    PyWavelets

# Re-pin the CUDA 13.0 PyTorch stack in case another package attempted to
# replace it with a CPU or different-CUDA build.
RUN python3 -m pip install --no-cache-dir --force-reinstall --no-deps \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" \
    --index-url https://download.pytorch.org/whl/cu130

# CUDA 13 xFormers wheel. xFormers 0.0.34+ uses the stable PyTorch ABI for
# PyTorch 2.10 and later, so the wheel is compatible with PyTorch 2.11.
RUN python3 -m pip install --no-cache-dir --no-deps \
    "xformers==0.0.35" \
    --index-url https://download.pytorch.org/whl/cu130

# SageAttention V1 is Triton based and supports Ampere without compiling a
# GPU-specific extension during the image build.
RUN python3 -m pip install --no-cache-dir --no-deps \
    "sageattention==1.0.6"

# NVIDIA Apex is intentionally omitted. ComfyUI inference uses PyTorch and
# xFormers directly, and nodes that optionally support Apex fall back to
# standard PyTorch normalization. Removing Apex avoids the largest and most
# memory-intensive CUDA compilation step in GitHub Actions.

# Keep a current LTXVideo custom-node overlay in the image. The actual
# custom_nodes directory is mounted from TrueNAS, so the entrypoint applies
# this compatible copy at container startup.
ARG LTXVIDEO_REF=master
RUN git clone --depth 1 --branch "${LTXVIDEO_REF}" \
        https://github.com/Lightricks/ComfyUI-LTXVideo.git \
        /opt/custom-node-overlays/ComfyUI-LTXVideo && \
    python3 -m pip install --no-cache-dir \
        -r /opt/custom-node-overlays/ComfyUI-LTXVideo/requirements.txt

# Install llama-cpp-python's runtime dependencies explicitly, then build it
# once against CUDA 13 for SM 8.6, 8.9, and 12.0. The upstream project does
# not publish a CUDA 13 wheel, so source compilation is required for GPU offload.
# This is much smaller than the removed Apex build. Do not allow pip to replace
# NumPy or other shared packages.
RUN python3 -m pip install --no-cache-dir \
    "diskcache>=5.6.1" \
    "jinja2>=2.11.3" \
    "typing-extensions>=4.5.0"

RUN python3 -m pip uninstall -y \
        llama-cpp-python \
        llama_cpp_python \
        llama-cpp \
        llama_cpp \
        llama-cpp-py || true && \
    python3 -m pip install --no-cache-dir --upgrade --force-reinstall \
        --no-deps \
        --no-binary=llama-cpp-python \
        "llama-cpp-python==${LLAMA_CPP_PYTHON_VERSION}"

# faster-whisper currently uses CTranslate2 CUDA 12 binaries. Install its
# required CUDA 12 cuBLAS/cuDNN libraries alongside the CUDA 13 ComfyUI stack.
RUN python3 -m pip install --no-cache-dir \
    faster-whisper \
    huggingface-hub \
    nvidia-cublas-cu12 \
    "nvidia-cudnn-cu12==9.*"

# Register the CUDA 12 library directories used by CTranslate2. The nvidia.*
# packages are namespace packages, so their module __file__ values may be None.
# Locate the actual library directories through their package search paths.
RUN python3 - <<'PY'
import os
from importlib.util import find_spec

paths = []
for package in ('nvidia.cublas', 'nvidia.cudnn'):
    spec = find_spec(package)
    if spec is None or not spec.submodule_search_locations:
        raise RuntimeError(f'Could not locate {package}')

    found = False
    for package_dir in spec.submodule_search_locations:
        library_dir = os.path.join(package_dir, 'lib')
        if os.path.isdir(library_dir):
            paths.append(library_dir)
            found = True

    if not found:
        raise RuntimeError(f'Could not locate the lib directory for {package}')

paths = sorted(set(paths))
with open('/etc/ld.so.conf.d/ctranslate2-cu12.conf', 'w', encoding='utf-8') as file:
    for path in paths:
        file.write(path + '\n')

print('Registered CTranslate2 CUDA 12 libraries:')
for path in paths:
    print(path)
PY
RUN ldconfig

# Download faster-whisper large-v3 into the image.
RUN mkdir -p "${HF_HUB_CACHE}" && \
    python3 - <<'PY'
import os
from huggingface_hub import snapshot_download

path = snapshot_download(
    repo_id=os.environ['FASTER_WHISPER_MODEL_REPO'],
    cache_dir=os.environ['HF_HUB_CACHE'],
)
print('Downloaded faster-whisper model to:', path)
PY

# Build-time verification. GPU-linked extensions are checked by package and
# shared-library presence because libcuda.so.1 is injected only at runtime.
RUN python3 - <<'PYVERIFY'
import importlib.util
import os
from importlib.metadata import version
from pathlib import Path

import ctranslate2
import numpy as np
import onnxruntime
import torch
import torchaudio
import torchvision
from huggingface_hub import snapshot_download

assert torch.version.cuda == '13.0', torch.version.cuda
assert onnxruntime.__version__.startswith('1.28.'), onnxruntime.__version__
assert np.__version__ == '1.26.4', np.__version__

required_modules = [
    'OpenEXR', 'OpenGL_accelerate', 'chardet', 'colour', 'cv2', 'dill', 'easyocr', 'feedparser',
    'ffmpeg', 'google.cloud.storage', 'html2image', 'keyboard', 'llama_index',
    'mdtex2html', 'moviepy', 'pydub', 'rawpy', 'rembg', 'selenium', 'srt',
]
missing = [name for name in required_modules if importlib.util.find_spec(name) is None]
assert not missing, f'Missing required modules: {missing}'

for distribution in (
    'chardet', 'opencv-python-headless', 'xformers', 'sageattention',
    'llama-cpp-python',
):
    print(distribution + ':', version(distribution))

llama_library = Path('/usr/local/lib/python3.12/dist-packages/llama_cpp/lib/libllama.so')
assert llama_library.is_file(), f'Missing llama.cpp shared library: {llama_library}'

model_path = snapshot_download(
    repo_id=os.environ['FASTER_WHISPER_MODEL_REPO'],
    cache_dir=os.environ['HF_HUB_CACHE'],
    local_files_only=True,
)

print('PyTorch:', torch.__version__)
print('Torchvision:', torchvision.__version__)
print('Torchaudio:', torchaudio.__version__)
print('PyTorch CUDA build:', torch.version.cuda)
print('ONNX Runtime:', onnxruntime.__version__)
print('ONNX providers compiled in:', onnxruntime.get_available_providers())
print('CTranslate2:', ctranslate2.__version__)
print('Verified llama.cpp library:', llama_library)
print('Verified faster-whisper model:', model_path)
PYVERIFY
RUN chmod -R a+rX "${HF_HOME}" /opt/custom-node-overlays

# Runtime initialization fixes configuration stored in mounted TrueNAS datasets.
RUN cat > /usr/local/bin/comfyui-entrypoint <<'SHENTRY'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
    "${YOLO_CONFIG_DIR}" \
    "${MPLCONFIGDIR}" \
    /app/ComfyUI/user/backups

# Replace the stale mounted LTXVideo custom node with the current compatible
# copy. Create a one-time backup before the first replacement.
LTX_SOURCE=/opt/custom-node-overlays/ComfyUI-LTXVideo
LTX_TARGET=/app/ComfyUI/custom_nodes/ComfyUI-LTXVideo
LTX_BACKUP=/app/ComfyUI/user/backups/ComfyUI-LTXVideo-before-v0.30.0.tar.gz
if [[ -d "${LTX_TARGET}" && -d "${LTX_SOURCE}" ]]; then
    if [[ ! -f "${LTX_BACKUP}" ]]; then
        tar -czf "${LTX_BACKUP}" -C "$(dirname "${LTX_TARGET}")" "$(basename "${LTX_TARGET}")"
    fi
    rsync -a --delete --exclude='.git/' "${LTX_SOURCE}/" "${LTX_TARGET}/"
    find "${LTX_TARGET}" -type d -name __pycache__ -prune -exec rm -rf {} +
fi

# Point WAS Node Suite at the system ffmpeg binary without discarding its
# existing configuration.
python3 - <<'PYWAS'
import json
from pathlib import Path

path = Path('/app/ComfyUI/custom_nodes/was-ns/was_suite_config.json')
if path.parent.is_dir():
    try:
        data = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    except (json.JSONDecodeError, OSError):
        data = {}
    data['ffmpeg_bin_path'] = '/usr/bin/ffmpeg'
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
PYWAS

cd /app/ComfyUI
exec python3 main.py "$@"
SHENTRY
# Git/Windows may save this Dockerfile with CRLF. The heredoc preserves those
# carriage returns, which would make the shebang resolve as 'bash\r'.
RUN sed -i 's/\r$//' /usr/local/bin/comfyui-entrypoint && \
    chmod +x /usr/local/bin/comfyui-entrypoint

EXPOSE 8188
ENTRYPOINT ["/usr/local/bin/comfyui-entrypoint"]
CMD ["--listen", "0.0.0.0", "--port", "8188", "--enable-dynamic-vram"]
