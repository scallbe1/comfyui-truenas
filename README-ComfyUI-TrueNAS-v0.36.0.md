# ComfyUI for TrueNAS

This repository provides a containerized ComfyUI environment for TrueNAS SCALE. The current image targets **ComfyUI v0.36.0** on Ubuntu 24.04 with CUDA 13.0.3 and cuDNN support.

It includes Python and system dependencies for a broad range of ComfyUI image, video, audio, music, speech-to-text, local-LLM, and utility custom nodes, with particular support for current MiniMax H3 workflows.

## Included Platform

- **ComfyUI v0.36.0**
  - Includes the native MiniMax H3 guide / MultiRef support required by current H3 Motion Context workflows
  - Includes the v0.36 MiniMax H3 VAE optimizations and reduced H3 VAE memory usage
  - Uses the current integrated ComfyUI Manager
- Python 3.12
- PyTorch 2.11.0 with CUDA 13.0
- Torchvision 0.26.0
- Torchaudio 2.11.0
- xFormers 0.0.35
- SageAttention 1.0.6
- ONNX Runtime GPU 1.30.0
- llama-cpp-python 0.3.34 with CUDA GPU offload
- faster-whisper with the `large-v3` model included in the image
- FFmpeg
- Google Chrome
- OpenGL, audio, vision, document-processing, and LLM dependencies
- SeedVR2 Video Upscaler
- MiniMax H3 PDD Acc custom nodes

The image includes CUDA support for:

- NVIDIA RTX 3090 and other SM 8.6 GPUs
- NVIDIA RTX 4090 and other SM 8.9 GPUs
- NVIDIA RTX 5090-class SM 12.0 GPUs

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

Do **not** commit a real Hugging Face token to this repository. Keep the actual token in your private TrueNAS configuration or another appropriate secret-management mechanism.

The remaining Hugging Face variables keep downloaded files under the persistent `/opt/huggingface` cache and increase the download timeout for large model files.

## Persistent Custom Nodes

The `/app/ComfyUI/custom_nodes` directory is mounted from TrueNAS:

```yaml
- /mnt/pool1/comfyui-customnodes:/app/ComfyUI/custom_nodes
```

Custom nodes installed through ComfyUI Manager or manually added to this dataset survive container replacement.

Some custom nodes are intentionally shipped as **image-owned code under `/opt`** and exposed into the mounted `custom_nodes` directory with runtime symlinks. This allows a rebuilt container image to update those nodes without overwriting the rest of the persistent custom-node dataset.

The image currently manages these nodes this way:

- `ComfyUI-SeedVR2_VideoUpscaler`
- `ComfyUI-MiniMax-H3-PDD-Acc`

If a normal directory with either name already exists in the persistent `custom_nodes` dataset, the entrypoint moves it into:

```text
/app/ComfyUI/user/custom-node-backups/
```

and then creates the image-owned symlink.

The container supervises the ComfyUI process so that **Restart Manager** can restart ComfyUI without stopping the TrueNAS application itself.

If an old standalone `ComfyUI-Manager` clone exists in the persistent `custom_nodes` dataset, the container prints a warning because this build uses ComfyUI's integrated Manager support.

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
- MiniMax H3 PDD 8-step acceleration

This supports current versions of:

```text
ComfyUI-H3-Motion-Context-MultiRef
```

### MiniMax H3 PDD Acc

The image includes:

```text
ComfyUI-MiniMax-H3-PDD-Acc
```

The node code is stored inside the image at:

```text
/opt/ComfyUI-MiniMax-H3-PDD-Acc
```

and exposed at runtime as:

```text
/app/ComfyUI/custom_nodes/ComfyUI-MiniMax-H3-PDD-Acc
```

PDD weights are **not** baked into the container image. Put the matching PDD model file in the persistent models dataset under:

```text
/app/ComfyUI/models/pdd_acc/
```

For the Ref2VA workflow, use either the original Alibaba PAI file:

```text
MiniMax-H3-Ref2VA-Acc-8Step.safetensors
```

or the compatible pre-converted ComfyUI-key version:

```text
minimax_h3_ref2va_pdd_acc_8step_comfyui.safetensors
```

The PDD node supports both full and pruned INT8 ConvRot Ref2VA checkpoints through ComfyUI's quant-aware patch path.

The required PDD sampling recipe is:

- Euler sampler
- 8 PDD evaluations for the normal 8-step path
- BasicGuider / CFG 1.0 behavior
- MiniMax H3 sigma shift `12.0` video / `3.0` audio
- sigmas emitted by the PDD Apply node
- **do not stack LightX2V Turbo or other step-distillation LoRAs with PDD**

## SeedVR2

SeedVR2 is shipped as image-owned code under:

```text
/opt/ComfyUI-SeedVR2_VideoUpscaler
```

At container start, the entrypoint exposes it as:

```text
/app/ComfyUI/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler
```

SeedVR2 model files remain persistent under:

```text
/app/ComfyUI/models/SEEDVR2
```

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
