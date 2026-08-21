# ComfyUI for TrueNAS

This repository provides a containerized ComfyUI environment for TrueNAS SCALE. The image was updated in August 2026 and is based on Ubuntu 24.04 with CUDA 13.0.3 and cuDNN support.

It includes Python and system dependencies for a broad range of ComfyUI image, video, audio, music, speech-to-text, local-LLM, and utility custom nodes.

## Included Platform

- ComfyUI pinned to Git commit `e01fb4c`
  - Includes the native MiniMax H3 arbitrary-guide / MultiRef support introduced by ComfyUI PR #15439
  - Required by current `ComfyUI-H3-Motion-Context-MultiRef` workflows that combine Ref2VA references, H3 guide/keyframe conditioning, continuation video latents, and audio latents
- Python 3.12
- PyTorch 2.11.0 with CUDA 13.0
- Torchvision 0.26.0
- Torchaudio 2.11.0
- xFormers 0.0.35
- SageAttention 1.0.6
- ONNX Runtime GPU 1.28.x
- llama-cpp-python 0.3.34 with CUDA GPU offload
- faster-whisper with the `large-v3` model included in the image
- FFmpeg
- Google Chrome
- OpenGL, audio, vision, document-processing, and LLM dependencies
- Integrated ComfyUI Manager support

The image includes CUDA support for:

- NVIDIA RTX 3090 and other SM 8.6 GPUs
- NVIDIA RTX 4090 and other SM 8.9 GPUs
- NVIDIA RTX 5090-class SM 12.0 GPUs

TrueNAS must have a working NVIDIA driver that supports the CUDA 13.0 container stack and the installed GPU.

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

When this mount is enabled, the TrueNAS dataset becomes the container's persistent Hugging Face cache. This is useful for large model downloads because downloaded models survive container replacement.

Because a host mount replaces the contents of the same path inside the image, an initially empty `comfyui-huggingface` dataset will hide any Hugging Face cache that was baked into the container image. Models can then be downloaded into the persistent dataset as they are required.

If you prefer to use only the Hugging Face files baked into the image, remove the `/opt/huggingface` volume mapping.

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

### Persistent Custom Nodes

The `/app/ComfyUI/custom_nodes` directory is mounted from TrueNAS:

```yaml
- /mnt/pool1/comfyui-customnodes:/app/ComfyUI/custom_nodes
```

Custom nodes installed through ComfyUI Manager or manually added to this dataset therefore survive container replacement.

The container supervises the ComfyUI process so that **Restart Manager** can restart ComfyUI without stopping the TrueNAS application itself.

If an old standalone `ComfyUI-Manager` clone exists in the persistent `custom_nodes` dataset, the container prints a warning because this build uses ComfyUI's integrated Manager support.

### MiniMax H3 Support

This image is intentionally pinned to ComfyUI commit:

```text
e01fb4c
```

This commit contains the native MiniMax H3 guide and MultiRef functionality required by current H3 Motion Context workflows.

It supports workflows that combine:

- Ref2VA character/reference images
- H3 image/keyframe guides
- previous-video continuation context
- MiniMax H3 video latents
- MiniMax H3 audio latents
- reference-aware guide merging

This is required by current versions of:

```text
ComfyUI-H3-Motion-Context-MultiRef
```

Older ComfyUI builds such as `v0.33.1` do not contain the required native H3 guide/MultiRef implementation.

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
