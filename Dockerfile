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

# Pre-install uv to empower ComfyUI-Manager and prevent internal path loop crashes
RUN python3 -m pip install --no-cache-dir uv

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
# Added dynamicprompts here to fix the comfyui-dynamicprompts node boot failure
RUN python3 -m pip install --no-cache-dir \
    gguf opencv-python imageio-ffmpeg PyWavelets matplotlib soundfile sentencepiece \
    transformers accelerate av einops scikit-image onnxruntime-gpu \
    ultralytics timm fvcore onnx safetensors facexlib basicsr insightface segment-anything \
    open-clip-torch bitsandbytes>=0.46.1 kernels glitch_this mediapipe diffusers dynamicprompts

# STEP 6: Pre-install core audio signal processing math structures and document tools
RUN python3 -m pip install --no-cache-dir scipy librosa pedalboard pyloudnorm noisereduce reportlab PyPDF2 PyMuPDF rotary_embedding_torch

# STEP 7: Install specialized Cloud, Speech-to-Text, and Audio Production APIs cleanly
# Added pdfplumber here to finalize the comfyui_llm_party file ingestion module tracking
RUN python3 -m pip install --no-cache-dir \
    fal-client runwayml openai openai-whisper stable-audio-tools ollama gdown google-generativeai \
    langchain-community langchain-openai markdownify neo4j docx2txt openpyxl pdfplumber

# STEP 8: Inject the specialized SAM2 tracking binaries directly from Facebook Research
RUN python3 -m pip install --no-cache-dir git+https://github.com/facebookresearch/sam2

# STEP 9: Inject the proprietary NVIDIA VFX bindings 
RUN python3 -m pip install --no-cache-dir -U --no-build-isolation nvidia-vfx --index-url https://pypi.nvidia.com

# STEP 10: Clear caching errors and enforce matched library specifications globally across core wheels
RUN python3 -m pip install --no-cache-dir -U --force-reinstall numpy pandas scikit-learn PyWavelets

# STEP 11: Inject precompiled CUDA llama engines and patch the kernels validation bug across all module layers recursively
RUN python3 -m pip install --no-cache-dir -U --force-reinstall llama-cpp-python --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cu124 && \
    python3 -c "import os; d='/usr/local/lib/python3.10/dist-packages/kernels'; [open(os.path.join(r,f),'w').write(open(os.path.join(r,f)).read().replace('raise ValueError(\"Either a revision or a version must be specified.\")', 'revision=\"main\"')) for r,_,fs in os.walk(d) for f in fs if f.endswith('.py')]"

EXPOSE 8188

CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
