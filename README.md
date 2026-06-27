ComfyUI for TrueNAS - 

This containerized ComfyUI implementation (updated May 2026) contains CUDA 12.6 support for NVIDIA driver 570.172.08 and python package support for major image, video, and music generation nodes.

Important Setup Notes:

In the YAML file below,  "pull_policy: always" ensures you are running the latest image version on every restart. This slows down startup but ensures your local installation will be updated when the Dockerfile changes.

Storage: Before deploying, create these 5 datasets and create SMB shares. Grant user 1000 and your user account write-permission to those datasets to facilitate uploads and downloads from other devices.
- comfyui-models
- comfyui-customnodes
- comfyui-input
- comfyu-output
- comfyui-user

Update the local paths (left side of the colon) to match your storage layout. Do not modify the container paths (right side).

YAML:
```
services:
  comfyui:
    container_name: comfyui-truenas
    user: "568:568"
    deploy:
      resources:
        reservations:
          devices:
            - capabilities:
                - gpu
              count: all
              driver: nvidia
    environment:
      - UID=568
      - GID=568
      - PORT=8188
    image: ghcr.io/scallbe1/comfyui-truenas:latest
    ports:
      - '8188:8188'
    privileged: True
    pull_policy: always
    volumes:
      - /mnt/pool1/comfyui-models:/app/ComfyUI/models
      - /mnt/pool1/comfyui-customnodes:/app/ComfyUI/custom_nodes
      - /mnt/pool1/comfyui-input:/app/ComfyUI/input
      - /mnt/pool1/comfyui-output:/app/ComfyUI/output
      - /mnt/pool1/comfyui-user:/app/ComfyUI/user
```
