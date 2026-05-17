FROM nvidia/cuda:12.6.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

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

# Upgrade core build tools globally
RUN pip install --no-cache-dir --upgrade pip setuptools wheel --break-system-packages

# Match your TrueNAS host driver (found 12080): Fetch the optimized CUDA 12.6 engine
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126 --break-system-packages

# Move directly to the ComfyUI workspace root
WORKDIR /app/ComfyUI

# Pull the core ComfyUI architecture safely into the empty folder
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . \
    && pip install --no-cache-dir -r requirements.txt --break-system-packages

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
    onnxruntime-gpu \
    --break-system-packages

# Inject the proprietary NVIDIA VFX bindings 
RUN pip install --no-cache-dir -U --no-build-isolation nvidia-vfx --index-url https://pypi.nvidia.com --break-system-packages

EXPOSE 8188

CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
