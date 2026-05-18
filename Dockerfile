FROM nvidia/cuda:12.6.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Install system utilities, native Python 3 platform, compilers, and graphics tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-pip \
    python3-dev \
    python-is-python3 \
    ffmpeg \
    libgl1 \
    libglx-mesa0 \
    libglib2.0-0 \
    build-essential \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Hardlink the pip commands so ComfyUI-Manager's subprocess scanner can always find them
RUN ln -sf /usr/bin/pip3 /usr/bin/pip && ln -sf /usr/bin/python3 /usr/bin/python

# 🌟 CRITICAL FIX: Force wide-open pip execution via a permanent system file.
# This stops sub-shells and standalone install.py scripts from losing the bypass environment variable.
RUN mkdir -p /etc && echo '[global]' > /etc/pip.conf && echo 'break-system-packages = true' >> /etc/pip.conf

WORKDIR /app/ComfyUI

# Fetch the optimized CUDA 12.6 engine matching your hardware layout
RUN python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# Pull the core ComfyUI architecture safely into the workspace root
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . \
    && python3 -m pip install --no-cache-dir -r requirements.txt

# Pre-bake your complete custom node dependency pack
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
    onnxruntime-gpu \
    GitPython \
    py-cpuinfo \
    toml \
    pynvml \
    color-matcher \
    ultralytics \
    timm \
    fvcore \
    onnx \
    safetensors \
    facexlib \
    basicsr \
    pedalboard \
    openai-whisper \
    insightface \
    segment-anything \
    fal-client

# Inject the proprietary NVIDIA VFX bindings 
RUN python3 -m pip install --no-cache-dir -U --no-build-isolation nvidia-vfx --index-url https://pypi.nvidia.com

EXPOSE 8188

CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
