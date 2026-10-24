# ComfyUI for TrueNAS

This repository provides a containerized ComfyUI environment for TrueNAS SCALE. The current image targets **ComfyUI v0.39.0** on Ubuntu 24.04 with CUDA 13.0.3 and cuDNN support.

It includes Python and system dependencies for the image, video, and utility custom nodes in the installed set, with particular support for current MiniMax H3 workflows. The dependency layers were pruned on 2026-10-22 to what the active custom-node collection actually imports; anything that only served now-quarantined nodes was dropped (Chrome, the faster-whisper install and its baked `large-v3` model, spacy, xformers, easyocr, nvidia-vfx, the audio/document-processing stacks, and the SeedVR2 and MiniMax-H3-PDD-Acc image-owned node clones).

## Included Platform

- **ComfyUI v0.39.0**
  - Includes the native MiniMax H3 guide / MultiRef support required by current H3 Motion Context workflows
  - Uses the current integrated ComfyUI Manager
- Python 3.12
- PyTorch 2.13.0 with CUDA 13.0
- Torchvision 0.28.0
- Torchaudio 2.11.0
- SageAttention 2.2.0 (official Git tag, built for SM 8.6)
- ONNX Runtime GPU 1.30.0
- llama-cpp-python 0.3.49 (JamePeng fork), built from source against CUDA 13 with GPU offload
- FFmpeg
- OpenCV (headless), insightface, segment-anything / SAM2, rembg, and the other dependencies imported by the installed custom-node set
- ComfyUI-H3-Continuum (image-owned, patched for 256-chunk long runs)

The base CUDA/PyTorch image includes CUDA support for:

- NVIDIA RTX 3090 and other SM 8.6 GPUs
- NVIDIA RTX 4090 and other SM 8.9 GPUs
- NVIDIA RTX 5090-class SM 12.0 GPUs

The `llama-cpp-python` backend in this build is deliberately compiled for **SM 8.6 / RTX 3090**, matching the current TrueNAS host and avoiding unnecessary multi-architecture compile time. If this image is moved to a different GPU architecture, change `CMAKE_CUDA_ARCHITECTURES` in the llama-cpp build block.

The current TrueNAS host configuration used with this image is an RTX 3090 with NVIDIA driver `580.173.02`, which reports CUDA 13.0 support.

## Important Setup Notes

### Image Updates

The Compose configuration uses:

```yaml
pull_policy: always
```

This instructs TrueNAS to pull the current `latest` image whenever the application is deployed or recreated.

This keeps the application current, but deployment or recreation can take longer when a newer image must be downloaded.

### Persistent Storage

The example configuration uses six persistent TrueNAS datasets:

- `comfyui-models`
- `comfyui-customnodes`
- `comfyui-input`
- `comfyui-output`
- `comfyui-user`
- `comfyui-huggingface`

The datasets used by ComfyUI must be writable by UID `1000` and GID `1000`.

Update the host paths on the left side of each volume mapping to match your TrueNAS storage layout. The container paths on the right side should normally remain unchanged.

For example:

```yaml
- /mnt/pool1/comfyui-models:/app/ComfyUI/models
```

The persistent Hugging Face cache is mapped as:

```yaml
- /mnt/pool1/comfyui-huggingface:/opt/huggingface
```

When this mount is enabled, the TrueNAS dataset becomes the container's persistent Hugging Face cache. Downloaded models therefore survive container replacement.

Because a host mount replaces the contents of the same path inside the image, an initially empty `comfyui-huggingface` dataset hides any Hugging Face cache baked into the container image. Models can then be downloaded into the persistent dataset as required.

If you prefer to use only Hugging Face files baked into the image, remove the `/opt/huggingface` volume mapping.

### Hugging Face Configuration

The current Compose configuration sets:

```yaml
environment:
  - UID=1000
  - GID=1000
  - PORT=8188
  - HF_TOKEN=<your-huggingface-token>
  - HF_HOME=/opt/huggingface
  - HF_HUB_CACHE=/opt/huggingface/hub
  - HF_HUB_DOWNLOAD_TIMEOUT=600
```

`HF_TOKEN` is optional for public Hugging Face repositories but may be required for gated or authenticated model downloads.

The remaining Hugging Face variables keep downloaded files under the persistent `/opt/huggingface` cache and increase the download timeout for large model files.

## Persistent Custom Nodes

The `/app/ComfyUI/custom_nodes` directory is mounted from TrueNAS:

```yaml
- /mnt/pool1/comfyui-customnodes:/app/ComfyUI/custom_nodes
```

Custom nodes installed through ComfyUI Manager or manually added to this dataset survive container replacement.

Some custom nodes are intentionally shipped as **image-owned code under `/opt`** and exposed into the mounted `custom_nodes` directory with runtime symlinks. This allows a rebuilt container image to update those nodes without overwriting the rest of the persistent custom-node dataset.

The image currently manages one node this way:

- `ComfyUI-H3-Continuum` (with the long-run patch applied at build time; the build records its commit in `/opt/h3-continuum-git-commit.txt`)

If a normal directory with the same name already exists in the persistent `custom_nodes` dataset, the entrypoint moves it into:

```text
/app/ComfyUI/user/custom-node-backups/
```

and then creates the image-owned symlink.

The container supervises the ComfyUI process so that **Restart Manager** can restart ComfyUI without stopping the TrueNAS application itself.

If an old standalone `ComfyUI-Manager` clone exists in the persistent `custom_nodes` dataset, the container prints a warning because this build uses ComfyUI's integrated Manager support.

## Local LLM / llama-cpp-python

The local LLM custom node uses `llama-cpp-python` to run GGUF models directly inside ComfyUI. The current backend is **JamePeng llama-cpp-python 0.3.49**, built from source against the CUDA 13 toolkit in this image.

The build uses JamePeng commit:

```text
34c1bfbce3ad485d31e67039fa9200e6ab49882e
```

with:

```text
GGML_CUDA=ON
GGML_BACKEND_DL=OFF
CMAKE_CUDA_ARCHITECTURES=86
```

This replaces the previous prebuilt-wheel approach. That wheel could resolve CUDA 12 runtime libraries inside the CUDA 13 container and resulted in:

```text
GPU offload: False
```

The source-built backend was validated on the RTX 3090 with:

```text
llama_cpp: 0.3.49
GPU offload: True
```

The CUDA 12 user-space packages that used to accompany faster-whisper / CTranslate2 were removed in the 2026-10-22 pruning; they were never the llama-cpp workaround. No `GGML_BACKEND_PATH` override or CUDA-12 llama patch is required.

The custom-node source itself remains on the persistent TrueNAS `custom_nodes` dataset. The compiled Python backend lives in the container image, so recreating the application from the newly built image restores the known-good CUDA build automatically. A normal Docker/container restart does not discard its writable layer, but a container recreation does; baking the backend into the image removes that dependency on temporary container state.

### Runtime verification

After deploying the new image, verify the installed package from a neutral working directory:

```bash
C=$(docker ps --format '{{.Names}}' | grep -i comfyui | head -1)

docker exec "$C" bash -lc '
cd /
python - <<'"'"'PY'"'"'
import llama_cpp

print("llama_cpp:", llama_cpp.__version__)
print("module file:", llama_cpp.__file__)
print("GPU offload:", llama_cpp.llama_supports_gpu_offload())
PY
'
```

Expected result:

```text
llama_cpp: 0.3.49
module file: /usr/local/lib/python3.12/dist-packages/llama_cpp/...
GPU offload: True
```

For the current text-only Qwen3.8 workflow, use:

```text
model: Huihui-Qwen3.8-27B-abliterated-UD-Q5_K_XL.gguf
mmproj: None
chat_handler: None
n_ctx: 8192
vram_limit: -1
```

The model is stored on the persistent models dataset under:

```text
/app/ComfyUI/models/LLM/Huihui-Qwen3.8-27B-abliterated-UD-Q5_K_XL.gguf
```

If ComfyUI Manager is later used to reinstall or upgrade the llama-cpp custom node and its installer replaces `llama-cpp-python`, recreate the TrueNAS application from this image to restore the image-baked CUDA 13 backend.

## MiniMax H3 Support

ComfyUI v0.36.0 includes the native MiniMax H3 functionality used by current workflows, including the guide/MultiRef features introduced earlier in the H3 implementation and the newer v0.36 H3 VAE optimizations.

The image supports workflows that combine:

- Ref2VA character/reference images
- H3 image/keyframe guides
- previous-video continuation context
- MiniMax H3 video latents
- MiniMax H3 audio latents
- reference-aware guide merging
- LightX2V 8-step Ref2V acceleration

This supports current versions of:

```text
ComfyUI-H3-Motion-Context-MultiRef
ComfyUI-H3-Continuum
ComfyUI-Spark-H3
```

### Removed: MiniMax H3 PDD Acc

The `ComfyUI-MiniMax-H3-PDD-Acc` node and its image-owned `/opt` clone were
removed in the 2026-10-22 dependency pruning — no saved workflow used it. PDD
model files left in `/app/ComfyUI/models/pdd_acc/` are harmless; the node that
consumed them is gone from the image.

### Removed: SeedVR2

`ComfyUI-SeedVR2_VideoUpscaler` was also removed in the 2026-10-22 pruning for
the same reason (its entrypoint symlink logic is gone too). Model files remain
persistent under `/app/ComfyUI/models/SEEDVR2` if you ever re-add a node that
uses them.

## TrueNAS Custom App YAML

The following reflects the current TrueNAS configuration.

Replace `<your-huggingface-token>` with your private token if authenticated Hugging Face access is required. Do not store the real token in Git.

```yaml
services:
  comfyui:
    deploy:
      resources:
        reservations:
          devices:
            - capabilities:
                - gpu
              count: all
              driver: nvidia

    environment:
      - UID=1000
      - GID=1000
      - PORT=8188
      - HF_TOKEN=<your-huggingface-token>
      - HF_HOME=/opt/huggingface
      - HF_HUB_CACHE=/opt/huggingface/hub
      - HF_HUB_DOWNLOAD_TIMEOUT=600

    image: ghcr.io/scallbe1/comfyui-truenas:latest

    ports:
      - "8188:8188"

    privileged: true
    pull_policy: always

    volumes:
      - /mnt/pool1/comfyui-models:/app/ComfyUI/models
      - /mnt/pool1/comfyui-customnodes:/app/ComfyUI/custom_nodes
      - /mnt/pool1/comfyui-input:/app/ComfyUI/input
      - /mnt/pool1/comfyui-output:/app/ComfyUI/output
      - /mnt/pool1/comfyui-user:/app/ComfyUI/user
      - /mnt/pool1/comfyui-huggingface:/opt/huggingface
```

## Accessing ComfyUI

After deployment, open:

```text
http://<truenas-ip>:8188
```

## Updating the Container

Because the Compose configuration uses:

```yaml
pull_policy: always
```

recreating the TrueNAS application pulls the current `latest` image from:

```text
ghcr.io/scallbe1/comfyui-truenas:latest
```

Persistent models, custom nodes, input files, output files, user configuration, and the Hugging Face cache remain on the TrueNAS datasets across container replacement.

## Verifying the Running Version

The Docker build records the exact ComfyUI Git commit in:

```text
/opt/comfyui-git-commit.txt
```

The build smoke test also prints ComfyUI's reported version and Git commit during image construction.

After the container is running, you can verify the pinned release with:

```bash
docker exec -it $(docker ps --filter ancestor=ghcr.io/scallbe1/comfyui-truenas:latest -q | head -1) \
  python3 -c 'from comfyui_version import __version__; print(__version__)'
```

or inspect the saved commit:

```bash
docker exec -it $(docker ps --filter ancestor=ghcr.io/scallbe1/comfyui-truenas:latest -q | head -1) \
  cat /opt/comfyui-git-commit.txt
```
