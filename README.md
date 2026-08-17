# ComfyUI for TrueNAS

This containerized ComfyUI implementation was updated in August 2026. It is based on Ubuntu 24.04 with CUDA 13.0.3 and cuDNN support, and includes Python package support for major image, video, audio, music, speech-to-text, and local-LLM custom nodes.

## Included Platform

- ComfyUI 0.33.1
- Python 3.12
- PyTorch 2.11.0 with CUDA 13.0
- Torchvision 0.26.0
- Torchaudio 2.11.0
- xFormers 0.0.35
- SageAttention 1.0.6
- ONNX Runtime GPU 1.28.0
- llama-cpp-python 0.3.34 with CUDA GPU offload
- faster-whisper with the large-v3 model preloaded
- FFmpeg, Google Chrome, OpenGL, audio, vision, document, and LLM dependencies

The image includes CUDA builds for:

- NVIDIA RTX 3090 and other SM 8.6 GPUs
- NVIDIA RTX 4090 and other SM 8.9 GPUs
- NVIDIA RTX 5090-class SM 12.0 GPUs

TrueNAS must have a working NVIDIA driver that supports CUDA 13.0 and the installed GPU.

## Important Setup Notes

### Image Updates

The Compose configuration uses:

```yaml
pull_policy: always
```

This instructs TrueNAS Compose to pull the current `latest` image when the app is deployed or recreated. It can make deployment and some app restarts slower, but ensures the recreated container uses the newest published image.

### Persistent Storage

Before deploying the app, create these five datasets and, where required, SMB shares:

- `comfyui-models`
- `comfyui-customnodes`
- `comfyui-input`
- `comfyui-output`
- `comfyui-user`

The datasets must be writable by UID `1000` and GID `1000`.

Update the host paths on the left side of each volume mapping to match your TrueNAS storage layout. Do not change the container paths on the right side.

For example:

```yaml
- /mnt/pool1/comfyui-models:/app/ComfyUI/models
```

Do not mount an empty dataset over `/opt/huggingface`. The faster-whisper large-v3 model is stored there inside the image.

### Persistent Custom Nodes

The `/app/ComfyUI/custom_nodes` directory is mounted from TrueNAS, so installed custom nodes persist when the container is replaced.

At startup, the image applies compatibility fixes to certain mounted nodes when they are present:

- Replaces the mounted ComfyUI-LTXVideo files with the compatible version baked into the image.
- Patches the older CatVTON SCHP extension for the installed PyTorch version.
- Patches ComfyUI-Whisper to use the correct OpenAI Whisper tokenizer import.

One-time backups are stored under:

```text
/app/ComfyUI/user/backups
```

The first startup after installing or patching CatVTON can take longer while its CUDA extension compiles for the installed GPU.

The container also supervises the ComfyUI process so that **Restart Manager** can relaunch ComfyUI without stopping the TrueNAS app.

## TrueNAS Custom App YAML

```yaml
services:
  comfyui:
    container_name: comfyui-truenas
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
```

After deployment, open ComfyUI at:

```text
http://<truenas-ip>:8188
```

## Viewing the Full Container Log

From the TrueNAS system shell:

```bash
sudo docker logs --timestamps ix-comfyui-truenas-comfyui-1 2>&1
```

To show only recent startup output:

```bash
sudo docker logs --timestamps --since 30m ix-comfyui-truenas-comfyui-1 2>&1
```

The exact container name can be confirmed with:

```bash
sudo docker ps -a \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' \
  | grep -i comfy
```
