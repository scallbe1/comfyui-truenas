This is an implementation of ComfyUI designed to be deployed as a custom TrueNAS app.

It contains python packages for most of the major nodes for image, video and music generation. It deploys CUDA 12.6, which works with the NVIDIA driver in TrueNAS (NVIDIA-SMI 570.172.08).

A sample YAML to deploy ComfyUI onto your TrueNAS deployment is below. One note and one warning:

Note: The line "pull_policy: always" tells TrueNAS to force-download the newest version of the container image from the registry (e.g., Docker Hub) every time you deploy or restart the application. It overrides local caches to ensure your app is strictly running the latest available build

Warning: change the volume mount points (left of the colon) to align to your local storage layout. Build the 5 datasets below before deploying this app. Do not change the local paths (right side of the colon), these are baked into the ComfyUI image.

YAML:



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
    image: ghcr.io/scallbe1/cui-tn:latest
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
