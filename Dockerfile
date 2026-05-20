FROM nvidia/cuda:12.6.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Install system utilities, native Python 3 platform, compilers, and crucial Audio/Vision system backends
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
    libsndfile1 \
    portaudio19-dev \
    libasound2-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Hardlink the pip commands into both standard system binary locations and local user bins to satisfy validation scanners
RUN ln -sf /usr/bin/pip3 /usr/bin/pip && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    mkdir -p /usr/local/bin && \
    ln -sf /usr/bin/pip3 /usr/local/bin/pip && \
    ln -sf /usr/bin/python3 /usr/local/bin/python

# Force wide-open pip execution via a permanent system file for isolated sub-installers
RUN mkdir -p /etc && echo '[global]' > /etc/pip.conf && echo 'break-system-packages = true' >> /etc/pip.conf

WORKDIR /app/ComfyUI

# STEP 1: Fetch the optimized CUDA 12.6 core engine
RUN python3 -m pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# STEP 2: Pre-install mandatory compilation tools required by complex packages
RUN python3 -m pip install --no-cache-dir setuptools wheel cython numpy

# STEP 3: Pull the core ComfyUI architecture safely into the workspace root
RUN git clone https://github.com/comfyanonymous/ComfyUI.git . \
    && python3 -m pip install --no-cache-dir -r requirements.txt

# STEP 4: Install the stable, core Python utility and monitoring pack
RUN python3 -m pip install --no-cache-dir \
    GitPython py-cpuinfo toml pynvml color-matcher deepdiff piexif

# STEP 5: Install Vision, Modeling, and Face-Swap packages (Compiles Insightface safely)
RUN python3 -m pip install --no-cache-dir \
    gguf opencv-python imageio-ffmpeg PyWavelets matplotlib soundfile sentencepiece \
    transformers accelerate av einops scikit-image onnxruntime-gpu \
    ultralytics timm fvcore onnx safetensors facexlib basicsr insightface segment-anything

# STEP 6: Pre-install core audio signal processing math structures and document tools
RUN python3 -m pip install --no-cache-dir scipy librosa pedalboard pyloudnorm noisereduce reportlab PyPDF2

# STEP 7: Install specialized Cloud, Speech-to-Text, and Audio Production APIs cleanly
RUN python3 -m pip install --no-cache-dir \
    fal-client runwayml openai openai-whisper stable-audio-tools ollama gdown

# STEP 8: Inject the specialized SAM2 tracking binaries directly from Facebook Research
RUN python3 -m pip install --no-cache-dir git+https://github.com/facebookresearch/sam2

# STEP 9: Inject the proprietary NVIDIA VFX bindings 
RUN python3 -m pip install --no-cache-dir -U --no-build-isolation nvidia-vfx --index-url https://pypi.nvidia.com

# STEP 10: Clear caching errors and enforce absolute modern NumPy binary specifications globally
RUN python3 -m pip install --no-cache-dir -U --force-reinstall numpy

EXPOSE 8188

CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
