FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_DEFAULT_TIMEOUT=300 \
    PIP_RETRIES=10 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# CUDA build/runtime paths.
ENV CUDA_HOME=/usr/local/cuda \
    CUDACXX=/usr/local/cuda/bin/nvcc \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Build CUDA kernels for RTX 30-series (sm_86) and RTX 40-series (sm_89).
ENV CMAKE_BUILD_PARALLEL_LEVEL=4 \
    MAX_JOBS=4 \
    FORCE_CMAKE=1 \
    TORCH_CUDA_ARCH_LIST="8.6;8.9" \
    CMAKE_ARGS="-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86;89"

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
        > /etc/pip.conf

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
    py-cpuinfo \
    toml \
    nvidia-ml-py \
    color-matcher \
    deepdiff \
    piexif

# Vision, modeling, face, segmentation, diffusion, and GPU inference packages.
RUN python3 -m pip install --no-cache-dir \
    gguf \
    opencv-python \
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

# Clean-build llama-cpp-python against the CUDA 13 toolkit in this image.
RUN python3 -m pip uninstall -y \
        llama-cpp-python \
        llama_cpp_python \
        llama-cpp \
        llama_cpp \
        llama-cpp-py || true && \
    python3 -m pip install --no-cache-dir --upgrade --force-reinstall \
        --no-binary=llama-cpp-python \
        "llama-cpp-python==${LLAMA_CPP_PYTHON_VERSION}"

# faster-whisper currently uses CTranslate2 CUDA 12 binaries. Install its
# required CUDA 12 cuBLAS/cuDNN libraries alongside the CUDA 13 ComfyUI stack.
RUN python3 -m pip install --no-cache-dir \
    faster-whisper \
    huggingface-hub \
    nvidia-cublas-cu12 \
    "nvidia-cudnn-cu12==9.*"

# Register the CUDA 12 library directories used by CTranslate2 without
# replacing the primary CUDA 13 toolkit paths used by PyTorch and ComfyUI.
RUN python3 - <<'PY'
import os
import nvidia.cublas.lib
import nvidia.cudnn.lib

paths = [
    os.path.dirname(nvidia.cublas.lib.__file__),
    os.path.dirname(nvidia.cudnn.lib.__file__),
]

with open('/etc/ld.so.conf.d/ctranslate2-cu12.conf', 'w', encoding='utf-8') as f:
    for path in paths:
        f.write(path + '\n')

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

# Build-time verification. GPU availability itself is checked only when the
# container runs because Docker builds normally have no GPU attached.
RUN python3 - <<'PY'
import os
import torch
import torchvision
import torchaudio
import onnxruntime
import ctranslate2
import llama_cpp
from huggingface_hub import snapshot_download

assert torch.version.cuda == '13.0', torch.version.cuda
assert onnxruntime.__version__.startswith('1.28.'), onnxruntime.__version__

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
print('llama-cpp-python import: successful')
print('Verified faster-whisper model:', model_path)
PY

RUN chmod -R a+rX "${HF_HOME}"

EXPOSE 8188

# Dynamic VRAM and NVIDIA async offload are normally enabled automatically;
# --enable-dynamic-vram makes the intended configuration explicit.
CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--enable-dynamic-vram"]
