FROM nvidia/cuda:12.6.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
# Globally bypasses the Ubuntu system package lock for both Docker and ComfyUI-Manager
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Install system utilities, native Python 3 platform, and graphics tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-pip \
    python3-dev \
    ffmpeg \
    libgl1 \
    libglx-mesa0 \
    libglib2.0-0 \
    build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app/ComfyUI

# Pull the core ComfyUI architecture safely into the empty folder
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . \
    && python3 -m pip install --no-cache-dir -r requirements.txt

# Pre-bake all your custom node dependencies natively
RUN python3 -m pip install --no-cache-dir \
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
RUN python3 -m pip install --no-cache-dir -U --no-build-isolation nvidia-vfx --index-url https://pypi.nvidia.com

EXPOSE 8188

CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
