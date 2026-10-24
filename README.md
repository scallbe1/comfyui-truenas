# ComfyUI for TrueNAS

A containerized ComfyUI environment for TrueNAS SCALE, built for the
persistent-dataset deployment described below. The dependency set covers the
custom-node collection actually installed on the server: current MiniMax H3
video workflows, local-LLM inference through llama-cpp-python, and the
face/segmentation support those workflows use.

## Included Platform

- ComfyUI v0.39.0 with the integrated ComfyUI Manager
- Python 3.12 on Ubuntu 24.04, CUDA 13.0.3 with cuDNN
- PyTorch 2.13.0, Torchvision 0.28.0, Torchaudio 2.11.0 (CUDA 13 builds)
- SageAttention 2.2.0 for SM 8.6
- ONNX Runtime GPU 1.30.0 (GPU distribution only)
- llama-cpp-python 0.3.49 (JamePeng fork), built from source against CUDA 13
  with GPU offload, compiled for SM 8.6
- FFmpeg
- OpenCV (headless), insightface, segment-anything / SAM2, rembg, and the
  Python dependencies of the installed custom nodes
- ComfyUI-H3-Continuum — image-owned, patched at build time for 256-chunk
  long runs

The compute stack supports SM 8.6 (RTX 3090), SM 8.9 (RTX 4090), and
SM 12.0 (RTX 5090-class) GPUs. The reference deployment host is an RTX 3090
on NVIDIA driver 580.173.02. llama-cpp-python is compiled for SM 8.6 only;
change `CMAKE_CUDA_ARCHITECTURES` in its build block for other hardware.

## Architecture

Persistent state lives on TrueNAS datasets bind-mounted into the container:

| Dataset | Container path |
| --- | --- |
| `comfyui-models` | `/app/ComfyUI/models` |
| `comfyui-customnodes` | `/app/ComfyUI/custom_nodes` |
| `comfyui-input` | `/app/ComfyUI/input` |
| `comfyui-output` | `/app/ComfyUI/output` |
| `comfyui-user` | `/app/ComfyUI/user` |
| `comfyui-huggingface` | `/opt/huggingface` |

The datasets must be writable by UID/GID 1000. Custom nodes installed through
the Manager live on the mounted dataset and survive container replacement. The
Hugging Face cache mount overrides any cache baked into the image, so
downloads persist across replacements.

`ComfyUI-H3-Continuum` is the exception to dataset-resident nodes: the image
keeps its own patched checkout under `/opt/ComfyUI-H3-Continuum` and exposes
it into `custom_nodes` as a symlink at container start (the build records its
commit in `/opt/h3-continuum-git-commit.txt`). If a real directory of that
name exists in the mounted dataset, the entrypoint moves it to
`/app/ComfyUI/user/custom-node-backups/` and creates the symlink. A warning
is printed for any old standalone `ComfyUI-Manager` clone left in the dataset;
this build uses ComfyUI's integrated Manager.

The container supervises the ComfyUI process so the Manager's restart button
restarts ComfyUI without stopping the TrueNAS application.

## MiniMax H3

The image supports workflows combining Ref2VA character/reference images,
H3 image/keyframe guides, previous-video continuation context, MiniMax H3
video and audio latents, reference-aware guide merging, and LightX2V 8-step
Ref2V acceleration. It works with the current versions of:

- ComfyUI-H3-Motion-Context-MultiRef
- ComfyUI-H3-Continuum
- ComfyUI-Spark-H3

## Local LLM (llama-cpp-python)

The build uses the JamePeng fork at commit
`34c1bfbce3ad485d31e67039fa9200e6ab49882e`, compiled with:

```text
GGML_CUDA=ON
GGML_BACKEND_DL=OFF
CMAKE_CUDA_ARCHITECTURES=86
```

Expected runtime result, verified from a neutral directory inside the
container:

```text
llama_cpp: 0.3.49
GPU offload: True
```

The compiled backend lives in the image, so recreating the application always
restores the known-good CUDA 13 build — including after the Manager reinstalls
the node package.

## TrueNAS Custom App YAML

Replace `<your-huggingface-token>` if authenticated Hugging Face access is
required. Adjust host paths to your storage layout; keep the container paths.

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

After deployment, open `http://<truenas-ip>:8188`.

## Updating the Container

`pull_policy: always` means recreating the application pulls the current
`latest` image; models, custom nodes, input/output, user configuration, and
the Hugging Face cache persist on the datasets across replacement.

The build records the exact ComfyUI Git commit in
`/opt/comfyui-git-commit.txt`. Verify the running version with:

```bash
docker exec -it <container> \
  python3 -c 'from comfyui_version import __version__; print(__version__)'
```
