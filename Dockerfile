FROM nvidia/cuda:12.6.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV PYTHONUNBUFFERED=1

# Build llama.cpp CUDA kernels for all RTX 30- and 40-series GPUs.
# RTX 30-series: compute capability 8.6
# RTX 40-series: compute capability 8.9
ENV CMAKE_BUILD_PARALLEL_LEVEL=4
ENV FORCE_CMAKE=1
ENV CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_CUDA_ARCHITECTURES=86;89"

# Persistent location inside the Docker image for Hugging Face models.
# Do not mount an empty TrueNAS dataset over /opt/huggingface,
# or it will hide the model stored in the image.
ENV HF_HOME=/opt/huggingface
ENV HF_HUB_CACHE=/opt/huggingface/hub
ENV HF_HUB_DOWNLOAD_TIMEOUT=300
ENV FASTER_WHISPER_MODEL_REPO=Systran/faster-whisper-large-v3

# Install system utilities, Python, CUDA build tools, and audio/vision libraries.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-pip \
    python3-dev \
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
    libsndfile1 \
    portaudio19-dev \
    libasound2-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Normalize Python and pip paths.
RUN ln -sf /usr/bin/pip3 /usr/bin/pip && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    mkdir -p /usr/local/bin && \
    ln -sf /usr/bin/pip3 /usr/local/bin/pip && \
    ln -sf /usr/bin/python3 /usr/local/bin/python

# Allow pip installations into the system Python used by this container.
RUN mkdir -p /etc && \
    printf '%s\n' \
        '[global]' \
        'break-system-packages = true' \
        > /etc/pip.conf

WORKDIR /app/ComfyUI

# Upgrade base Python tooling.
RUN python3 -m pip install --no-cache-dir --upgrade \
    pip \
    setuptools \
    wheel \
    cython \
    uv \
    numpy

# STEP 1: Install PyTorch CUDA 12.6.
RUN python3 -m pip install --no-cache-dir --upgrade \
    torch==2.11.0 \
    torchvision==0.26.0 \
    torchaudio==2.11.0 \
    --index-url https://download.pytorch.org/whl/cu126

# STEP 2: Pull the pinned ComfyUI release.
ARG COMFYUI_VERSION=v0.27.0

RUN git clone --depth 1 --branch "${COMFYUI_VERSION}" \
        https://github.com/comfyanonymous/ComfyUI.git . && \
    python3 -m pip install --no-cache-dir -r requirements.txt

# STEP 3: Core utilities and monitoring packages.
RUN python3 -m pip install --no-cache-dir \
    GitPython \
    py-cpuinfo \
    toml \
    nvidia-ml-py \
    color-matcher \
    deepdiff \
    piexif

# STEP 4: Vision, modeling, face, segmentation, and diffusion packages.
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
    onnxruntime-gpu \
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
    'bitsandbytes>=0.46.1' \
    glitch_this \
    mediapipe \
    diffusers \
    dynamicprompts \
    tiktoken

# STEP 5: Audio, math, document, and utility packages.
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

# STEP 6: Cloud, speech-to-text, LLM/API, and document helper packages.
RUN python3 -m pip install --no-cache-dir \
    fal-client \
    runwayml \
    openai \
    openai-whisper \
    stable-audio-tools \
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

# STEP 7: SAM2.
RUN python3 -m pip install --no-cache-dir \
    git+https://github.com/facebookresearch/sam2

# STEP 8: NVIDIA VFX bindings.
RUN python3 -m pip install \
    --no-cache-dir \
    --upgrade \
    --no-build-isolation \
    nvidia-vfx \
    --index-url https://pypi.nvidia.com

# STEP 9: Re-pin common numeric and data packages after large dependency installs.
RUN python3 -m pip install \
    --no-cache-dir \
    --upgrade \
    --force-reinstall \
    numpy \
    pandas \
    scikit-learn \
    PyWavelets

# STEP 10: Clean-build llama-cpp-python with CUDA support.
#
# CMAKE_ARGS is defined globally above and compiles kernels for:
#   sm_86: all RTX 30-series GPUs
#   sm_89: all RTX 40-series GPUs
#
# --no-binary forces a local source build instead of installing a cached
# or precompiled wheel made for a different CUDA architecture.
RUN python3 -m pip uninstall -y \
        llama-cpp-python \
        llama_cpp_python \
        llama-cpp \
        llama_cpp \
        llama-cpp-py || true && \
    python3 -m pip install \
        --no-cache-dir \
        --upgrade \
        --force-reinstall \
        --no-binary=llama-cpp-python \
        llama-cpp-python

# Confirm that the newly compiled Python package imports successfully.
RUN python3 -c "import llama_cpp; print('llama-cpp-python import successful:', llama_cpp.__version__)"

# STEP 11: Install faster-whisper for SCMVM.
RUN python3 -m pip install --no-cache-dir \
    faster-whisper \
    huggingface-hub

# STEP 12: Download faster-whisper large-v3 into the image.
#
# SCMVM uses the model name "large-v3", which faster-whisper maps to:
# Systran/faster-whisper-large-v3
RUN mkdir -p "${HF_HUB_CACHE}" && \
    python3 -c "import os; \
from huggingface_hub import snapshot_download; \
path = snapshot_download( \
    repo_id=os.environ['FASTER_WHISPER_MODEL_REPO'], \
    cache_dir=os.environ['HF_HUB_CACHE'] \
); \
print('Downloaded faster-whisper model to:', path)"

# STEP 13: Verify faster-whisper and confirm the model exists locally.
RUN python3 -c "import os; \
from faster_whisper import WhisperModel; \
from huggingface_hub import snapshot_download; \
path = snapshot_download( \
    repo_id=os.environ['FASTER_WHISPER_MODEL_REPO'], \
    cache_dir=os.environ['HF_HUB_CACHE'], \
    local_files_only=True \
); \
print('faster-whisper import successful'); \
print('Verified local model:', path)" && \
    chmod -R a+rX "${HF_HOME}"

EXPOSE 8188

CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
