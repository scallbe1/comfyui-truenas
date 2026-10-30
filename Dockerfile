FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04

# Use the official ComfyUI release tag for reproducible GitHub Actions / GHCR
# builds. ComfyUI's own requirements.txt controls its Python dependencies.
ARG COMFYUI_REF=v0.39.0
ARG TORCH_VERSION=2.13.0
ARG TORCHVISION_VERSION=0.28.0
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
    TORCH_EXTENSIONS_DIR=/app/ComfyUI/user/.cache/torch_extensions \
    HF_HOME=/opt/huggingface \
    HF_HUB_CACHE=/opt/huggingface/hub \
    HF_HUB_DOWNLOAD_TIMEOUT=300 \
    HF_HUB_DISABLE_TELEMETRY=1 \
    CUDA_HOME=/usr/local/cuda \
    CUDACXX=/usr/local/cuda/bin/nvcc \
    PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    CMAKE_BUILD_PARALLEL_LEVEL=2 \
    MAX_JOBS=2

WORKDIR /app/ComfyUI

# -----------------------------------------------------------------------------
# OS dependencies
# -----------------------------------------------------------------------------
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

# Ubuntu 24.04 protects its system Python with PEP 668. We intentionally use the
# container's system Python and tell pip that this is an isolated container.
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

# Keep only the critical compute stack pinned. Do NOT pin transitive packages
# such as ONNX Runtime here; doing so made the previous image unnecessarily
# fragile when another package legitimately installed a newer release.
RUN printf '%s\n' \
        'numpy==1.26.4' \
        'torch==2.13.0' \
        'torchvision==0.28.0' \
        'torchaudio==2.11.0' \
        > /opt/pip-constraints.txt

ENV PIP_CONSTRAINT=/opt/pip-constraints.txt

# -----------------------------------------------------------------------------
# Python build tooling and CUDA PyTorch
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# ComfyUI core + integrated Manager
#
# --filter=blob:none keeps the Git checkout much smaller than a normal full
# clone while retaining commit history, allowing the release tag to be checked
# out reliably.
# -----------------------------------------------------------------------------
RUN git clone --filter=blob:none \
        https://github.com/Comfy-Org/ComfyUI.git . \
    && git checkout --detach "${COMFYUI_REF}" \
    && git rev-parse HEAD | tee /opt/comfyui-git-commit.txt \
    && python3 -m pip install --no-cache-dir -r requirements.txt \
    && python3 -m pip install --no-cache-dir -r manager_requirements.txt

# -----------------------------------------------------------------------------
# General custom-node dependencies
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir \
    GitPython \
    dill \
    toml \
    nvidia-ml-py \
    chardet \
    piexif \
    requirements-parser \
    rich \
    rich-argparse \
    diskcache

RUN python3 -m pip install --no-cache-dir \
    gguf \
    opencv-python-headless \
    imageio-ffmpeg \
    matplotlib \
    soundfile \
    transformers \
    accelerate \
    einops \
    scikit-image \
    ultralytics \
    onnx \
    safetensors \
    insightface \
    segment-anything \
    "bitsandbytes>=0.50.0" \
    diffusers

RUN python3 -m pip install --no-cache-dir \
    openai

# Dependencies used by the mounted custom-node collection.
# color-matcher and mss are required by comfyui-kjnodes (restored 2026-10-28).
RUN python3 -m pip install --no-cache-dir \
    jsonschema \
    color-matcher \
    mss

# rembg is imported by comfyui_tinyterranodes and Dance_Movie_Automation.
# It may pull the CPU onnxruntime wheel; the onnxruntime-gpu resolution step
# later in this file settles that once at the end.
RUN python3 -m pip install --no-cache-dir "rembg==2.0.67"

RUN python3 -m pip install --no-cache-dir \
    tensorboard

# -----------------------------------------------------------------------------
# SAM2 and NVIDIA VFX
# -----------------------------------------------------------------------------
RUN python3 -m pip install --no-cache-dir \
    git+https://github.com/facebookresearch/sam2.git

# -----------------------------------------------------------------------------
# Re-establish the critical numerical / PyTorch stack after broad dependencies.
# This is intentional: custom-node packages are allowed to resolve their own
# dependencies, then the known-good compute stack is restored once at the end.
# -----------------------------------------------------------------------------
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

# Build SageAttention 2.2.0 CUDA kernels for the RTX 3090 (SM 8.6).
# The upstream 2.2.0 PyPI publication failed, so install the official Git tag.
# This requires the CUDA development base image already used above.
RUN TORCH_CUDA_ARCH_LIST="8.6" python3 -m pip install --no-cache-dir --no-build-isolation --no-deps \
    "git+https://github.com/thu-ml/SageAttention.git@v2.2.0"

# -----------------------------------------------------------------------------
# ONNX Runtime
#
# Some custom-node dependencies (including face/InsightFace-related nodes) can
# install the CPU `onnxruntime` distribution, while others expect
# `onnxruntime-gpu`. Both provide the same Python import name and installing
# both can overwrite files unpredictably.
#
# Resolve that once, at the END of dependency installation. ORT 1.30.0 is the
# CUDA-capable build verified with this CUDA 13 / Python 3.12 image and ZenID.
# Keep only the GPU distribution so CUDAExecutionProvider cannot be shadowed by
# the CPU wheel.
# -----------------------------------------------------------------------------
RUN python3 -m pip uninstall -y onnxruntime onnxruntime-gpu || true \
    && python3 -m pip install --no-cache-dir \
        "onnxruntime-gpu==1.30.0"

# -----------------------------------------------------------------------------
# llama-cpp-python built for CUDA 13 / SM86 (comfyui-llama-cpp imports llama_cpp)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Spark-H3 GPU attention backend: RTX 3090 (SM86), CUDA 13.0, ComfyUI 0.39.x.
#
# TrueNAS bind-mounts custom_nodes, but the Python comfy-kitchen package is
# image-owned. Install Spark's compatible native CUDA wheel AFTER all other
# Python dependency installation so it survives app/container recreation.
# This is the official signed-off release ZIP; checksum is release metadata.
# Spark-H3's own install.py requires a live GPU, which Docker builds lack.
# -----------------------------------------------------------------------------
RUN set -eu; \
    SPARK_ZIP=/tmp/ComfyUI-Spark-H3-0.1.4-linux-x86_64-sm86-cu130.zip; \
    curl --fail --location --retry 5 --connect-timeout 20 \
      --output "$SPARK_ZIP" \
      https://github.com/zechengtang/Spark-H3/releases/download/comfyui-v0.1.4/ComfyUI-Spark-H3-0.1.4-linux-x86_64-sm86-cu130.zip; \
    echo "b24d82127aa397c306c04b31bf9cc34df19129cb9374639fcd014a286a2c6759  $SPARK_ZIP" | sha256sum --check -; \
    python3 -c 'import zipfile; zipfile.ZipFile("/tmp/ComfyUI-Spark-H3-0.1.4-linux-x86_64-sm86-cu130.zip").extractall("/tmp/spark-h3-install")'; \
    SPARK_WHEEL="$(find /tmp/spark-h3-install -type f -name 'comfy_kitchen-0.2.37+spark.h3.sm86.cu130.1-*.whl' -print -quit)"; \
    test -n "$SPARK_WHEEL"; \
    python3 -m pip install --no-cache-dir --force-reinstall --no-deps "$SPARK_WHEEL"; \
    rm -rf /tmp/spark-h3-install "$SPARK_ZIP"

# The import is deliberately run in a fresh interpreter after pip installation.
# Importing the extension and inspecting its exported callable does not require
# actually launching a Spark kernel on a GPU at Docker build time.
RUN python3 - <<'PYSPARK'
from importlib.metadata import version
from comfy_kitchen.backends import cuda
expected = '0.2.37+spark.h3.sm86.cu130.1'
actual = version('comfy-kitchen')
assert actual == expected, f'comfy-kitchen mismatch: {actual} != {expected}'
assert callable(getattr(cuda, 'spark_attn', None)), 'comfy-kitchen Spark Python symbol missing'
assert callable(getattr(getattr(cuda, '_C', None), 'spark_attn', None)), 'comfy-kitchen native Spark symbol missing'
print('Spark-H3 SM86 CUDA 13.0 backend installed:', actual)
PYSPARK

# -----------------------------------------------------------------------------
# Non-brittle build smoke test
#
# This intentionally checks only that the core Python packages can be imported
# and reports versions. It does NOT fail because a transitive dependency moved
# from x.y.0 to x.y.1, and it does NOT assume package files live at a hard-coded
# Python path.
# -----------------------------------------------------------------------------
RUN python3 - <<'PY'
from importlib.metadata import PackageNotFoundError, version

import av
import diskcache
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
    "sageattention",
    "llama-cpp-python",
):
    try:
        print(f"{package}: {version(package)}")
    except PackageNotFoundError:
        print(f"{package}: package metadata not found")
PY

# -----------------------------------------------------------------------------
# Runtime entrypoint
# -----------------------------------------------------------------------------
# Install the latest H3 Continuum main into the image (not underneath the
# persistent custom_nodes mount). The patch is embedded in this Dockerfile,
# so the GitHub repository only needs a replacement Dockerfile.
RUN cat > /usr/local/bin/patch_h3_continuum_longrun.py <<'H3PATCH'
#!/usr/bin/env python3
"""Apply the H3 Continuum long-run change to a current repository checkout.
This edits node source; it is NOT a ComfyUI workflow node.
"""
from pathlib import Path
import argparse
import ast
import sys

REPLACEMENTS = {'v2/prompts.py': [('if not 1<=chunks<=16: raise PromptPlanError("chunks must be between 1 and 16")', 'if not 1<=chunks<=256: raise PromptPlanError("chunks must be between 1 and 256")'), ('if not 1<=chunks<=16: raise PromptPlanError("prompt-plan chunks are invalid")', 'if not 1<=chunks<=256: raise PromptPlanError("prompt-plan chunks are invalid")')], 'v2/nodes.py': [('"chunks": (\n                    "INT",\n                    {"default": 3, "min": 1, "max": 16, "step": 1},', '"chunks": (\n                    "INT",\n                    {"default": 3, "min": 1, "max": 256, "step": 1},'), ('"reroll_from_chunk": (\n                    "INT",\n                    {\n                        "default": 0,\n                        "min": 0,\n                        "max": 16,', '"reroll_from_chunk": (\n                    "INT",\n                    {\n                        "default": 0,\n                        "min": 0,\n                        "max": 256,')], 'v3/nodes.py': [('f"Chunk {index}" for index in range(1, 17)', 'f"Chunk {index}" for index in range(1, 257)'), ('{"default": 0, "min": 0, "max": 16, "step": 1}', '{"default": 0, "min": 0, "max": 256, "step": 1}'), ('("INT", {"default": 3, "min": 1, "max": 16, "step": 1})', '("INT", {"default": 3, "min": 1, "max": 256, "step": 1})'), ('"chunks": (\n                    "INT",\n                    {\n                        "default": 3,\n                        "min": 1,\n                        "max": 16,', '"chunks": (\n                    "INT",\n                    {\n                        "default": 3,\n                        "min": 1,\n                        "max": 256,'), ('                "reference_audio_vae": (\n                    "VAE",\n                    {"tooltip": "Audio VAE used only by the legacy single Reference Audio input."},\n                ),\n            },', '                "reference_audio_vae": (\n                    "VAE",\n                    {"tooltip": "Audio VAE used only by the legacy single Reference Audio input."},\n                ),\n                "storage_subfolder": (\n                    "STRING",\n                    {\n                        "default": "video",\n                        "display_name": "Run Storage Subfolder",\n                        "advanced": False,\n                        "tooltip": "Subfolder of the ComfyUI output directory that holds this run\'s project storage (project.json, revisions, AV chunks).",\n                    },\n                ),\n            },'), ('        with run_storage_scope(\n            storage_name, prompt=prompt, unique_id=unique_id\n        ) as storage:', '        with run_storage_scope(\n            storage_name, prompt=prompt, unique_id=unique_id,\n            subfolder=str(storage_subfolder or "video"),\n        ) as storage:'), ('        run_name="",\n        reference_size="Match Output",', '        run_name="",\n        storage_subfolder="video",\n        reference_size="Match Output",')], 'v3/driving_nodes.py': [('"max": 16,\n                "step": 1,\n                "advanced": True,\n                "display_name": "Selected Take Group"', '"max": 256,\n                "step": 1,\n                "advanced": True,\n                "display_name": "Selected Take Group"')], 'web/project_id.js': [('Math.min(16, Number.parseInt(chunks, 10) || 1)', 'Math.min(256, Number.parseInt(chunks, 10) || 1)'), ('const RUN_STORAGE_WIDGET = "run_storage";\nconst REFERENCE_SIZE_WIDGET = "reference_size";', 'const RUN_STORAGE_WIDGET = "run_storage";\nconst STORAGE_SUBFOLDER_WIDGET = "storage_subfolder";\nconst storageSubfolderOf = (node) => String(findWidget(node, STORAGE_SUBFOLDER_WIDGET)?.value ?? "").trim() || "video";\nconst REFERENCE_SIZE_WIDGET = "reference_size";'), ('subfolder=${encodeURIComponent(`h3_continuum/runs/${storageName}`)}', 'subfolder=${encodeURIComponent(`${storageSubfolderOf(node)}/${storageName}`)}'), ('const subfolder = `h3_continuum/runs/${runName}`;', 'const subfolder = `${storageSubfolderOf(node)}/${runName}`;')], 'run_storage.py': [('class RunStorageController:\n    def __init__(self, run_name: str):\n        self.run_name = sanitize_run_name(run_name)\n        self.run_root = _output_root() / "h3_continuum" / "runs" / self.run_name', 'def _clean_storage_subfolder(value: str) -> str:\n    text = str(value or "").strip().strip("/\\\\")\n    parts = [p for p in text.replace("\\\\", "/").split("/") if p and p != "."]\n    return "/".join(parts) or "video"\n\n\nclass RunStorageController:\n    def __init__(self, run_name: str, subfolder: str = "video"):\n        self.run_name = sanitize_run_name(run_name)\n        self.storage_subfolder = _clean_storage_subfolder(subfolder)\n        self.run_root = _output_root() / self.storage_subfolder / self.run_name'), ('def run_storage_scope(\n    run_name: str, *, prompt: Any = None, unique_id: Any = None\n) -> RunStorageController:\n    controller = RunStorageController(run_name)', 'def run_storage_scope(\n    run_name: str, *, prompt: Any = None, unique_id: Any = None,\n    subfolder: str = "video",\n) -> RunStorageController:\n    controller = RunStorageController(run_name, subfolder=subfolder)')], 'project_manager_api.py': [('Path(folder_paths.get_output_directory()) / "h3_continuum" / "runs")', 'Path(folder_paths.get_output_directory()) / "video")')]}

def apply(root: Path):
    paths = {}
    for relative, replacements in REPLACEMENTS.items():
        path = root / relative
        original = path.read_bytes().decode("utf-8")
        newline = "\r\n" if "\r\n" in original else "\n"
        changed = original.replace("\r\n", "\n")
        for old, new in replacements:
            count = changed.count(old)
            if count == 1:
                changed = changed.replace(old, new, 1)
            elif count == 0 and changed.count(new) == 1:
                continue  # already applied
            else:
                raise ValueError(
                    f"{relative}: incompatible source (old={count}, patched={changed.count(new)}): {old!r}"
                )
        paths[path] = changed.replace("\n", newline)

    # Validate all source text before writing anything.
    for path, content in paths.items():
        if path.suffix == ".py":
            ast.parse(content, filename=str(path))

    for path, content in paths.items():
        path.write_bytes(content.encode("utf-8"))
        print(f"Updated: {path.relative_to(root)}")
    print("Patch complete. Restart/rebuild ComfyUI before loading the v10 workflow.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path, help="Path to ComfyUI-H3-Continuum checkout")
    args = parser.parse_args()
    apply(args.repo.resolve())
H3PATCH

RUN git clone --depth 1 --branch main \
        https://github.com/ukr8b3g-cmyk/ComfyUI-H3-Continuum.git \
        /opt/ComfyUI-H3-Continuum \
    && python3 /usr/local/bin/patch_h3_continuum_longrun.py /opt/ComfyUI-H3-Continuum \
    && git -C /opt/ComfyUI-H3-Continuum rev-parse HEAD | tee /opt/h3-continuum-git-commit.txt

RUN cat > /usr/local/bin/comfyui-entrypoint <<'SHENTRY'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
    "${XDG_CONFIG_HOME}" \
    "${YOLO_CONFIG_DIR}" \
    "${MPLCONFIGDIR}" \
    "${TORCH_EXTENSIONS_DIR}"

mkdir -p /app/ComfyUI/custom_nodes

# The custom_nodes directory is a persistent bind mount. Expose the image-owned,
# already patched Continuum checkout through a symlink.
CONTINUUM_IMAGE_DIR=/opt/ComfyUI-H3-Continuum
CONTINUUM_NODE_DIR=/app/ComfyUI/custom_nodes/ComfyUI-H3-Continuum
if [[ ! -L "${CONTINUUM_NODE_DIR}" ]] || [[ "$(readlink "${CONTINUUM_NODE_DIR}")" != "${CONTINUUM_IMAGE_DIR}" ]]; then
    if [[ -e "${CONTINUUM_NODE_DIR}" || -L "${CONTINUUM_NODE_DIR}" ]]; then
        CONTINUUM_BACKUP_ROOT=/app/ComfyUI/user/custom-node-backups
        mkdir -p "${CONTINUUM_BACKUP_ROOT}"
        CONTINUUM_BACKUP="${CONTINUUM_BACKUP_ROOT}/ComfyUI-H3-Continuum-$(date -u +%Y%m%dT%H%M%SZ)-$$"
        mv "${CONTINUUM_NODE_DIR}" "${CONTINUUM_BACKUP}"
        echo "[INFO] Previous H3 Continuum checkout backed up to ${CONTINUUM_BACKUP}"
    fi
    ln -s "${CONTINUUM_IMAGE_DIR}" "${CONTINUUM_NODE_DIR}"
fi
echo "[INFO] H3 Continuum ready: $(cat /opt/h3-continuum-git-commit.txt); 256-chunk patch applied"

# Compile JIT extensions only for CUDA architectures actually visible to the
# container. This supports homogeneous or mixed visible GPU sets and avoids
# compiling unused architectures.
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

# Point WAS Node Suite at the system ffmpeg binary if the node is mounted.
# Failure to update this optional config must never prevent ComfyUI from booting.
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

# Warn about an old Manager clone in the persistent custom_nodes dataset.
# Do not delete or rename user data automatically.
for legacy_manager in \
    /app/ComfyUI/custom_nodes/ComfyUI-Manager \
    /app/ComfyUI/custom_nodes/comfyui-manager
do
    if [[ -d "${legacy_manager}" ]]; then
        echo "[WARN] Old ComfyUI-Manager custom-node clone detected: ${legacy_manager}"
        echo "[WARN] This ComfyUI build uses the integrated Manager package; remove the old clone if it causes duplicate/blocked Manager messages."
    fi
done

# Keep the TrueNAS application alive across Manager-requested ComfyUI restarts.
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

# Git / Windows editors may save this Dockerfile with CRLF. Strip CRLF from the
# generated entrypoint, validate shell syntax, and make it executable.
RUN sed -i 's/\r$//' /usr/local/bin/comfyui-entrypoint \
    && chmod +x /usr/local/bin/comfyui-entrypoint \
    && bash -n /usr/local/bin/comfyui-entrypoint

EXPOSE 8188

ENTRYPOINT ["/usr/local/bin/comfyui-entrypoint"]

# --enable-manager-legacy-ui implies Manager support in current ComfyUI, but
# keeping --enable-manager explicitly makes the intent obvious.
CMD ["--listen", "0.0.0.0", "--port", "8188", "--enable-dynamic-vram", "--enable-manager", "--enable-manager-legacy-ui"]
