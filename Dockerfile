# Shift to Ubuntu 24.04 to natively support Python 3.12 packages
FROM nvidia/cuda:12.6.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install system utilities, native Python 3 platform, and media codecs
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    ffmpeg \
    libgl1-mesa-glx \
    libglib2.0-0 \
    build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app/ComfyUI

# Establish the isolated environment using native Python (3.12)
RUN python3 -m venv /app/ComfyUI/.venv
ENV PATH="/app/ComfyUI/.venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install the matching PyTorch CUDA engine
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130

# Pull the core ComfyUI architecture
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . \
    && pip install --no-cache-dir -r requirements.txt

# Pre-bake all your custom node dependencies natively
RUN pip install --no-cache-dir \
    gguf \
    opencv-python \
    imageio-ffmpeg \
    PyWavelets \
    deepdiff \
    matplotlib \
    piexif \
    soundfile \
    sentencepiece \
    transformers \
    accelerate \
    av \
    einops \
    scikit-image \
    onnxruntime-gpu

# Inject the proprietary NVIDIA VFX bindings
RUN pip install --no-cache-dir -U --no-build-isolation nvidia-vfx --index-url https://pypi.nvidia.com

EXPOSE 8188

CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
