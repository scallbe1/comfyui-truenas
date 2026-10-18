#!/usr/bin/env python3
"""Generate an updated TrueNAS ComfyUI Dockerfile with Spark-H3 SM86 baked in.

Uses the existing repository Dockerfile without replacing its other customizations.
Does not change GitHub, start Docker, or modify a running container.
"""
import argparse
from pathlib import Path
import sys
import urllib.request

RAW_URL = "https://raw.githubusercontent.com/scallbe1/comfyui-truenas/main/Dockerfile"

BLOCK = r'''# -----------------------------------------------------------------------------
# Spark-H3 CUDA backend -- RTX 3090 SM86 / PyTorch CUDA 13.0 / ComfyUI 0.39.x
#
# The Spark custom node lives on a persistent custom_nodes bind mount, but
# comfy-kitchen is a Python package inside the image. Bake its Spark-enabled
# build into the image so TrueNAS container recreation cannot remove it.
#
# The bundled install.py checks for a live GPU and cannot run at image-build
# time. Install the verified official prebuilt wheel directly instead.
# Do this AFTER the other pip installs so no dependency replaces this wheel.
# -----------------------------------------------------------------------------
RUN set -eu; \
    SPARK_ZIP=/tmp/ComfyUI-Spark-H3-0.1.4-linux-x86_64-sm86-cu130.zip; \
    curl -fL --retry 5 --connect-timeout 20 -o "$SPARK_ZIP" \
      https://github.com/zechengtang/Spark-H3/releases/download/comfyui-v0.1.4/ComfyUI-Spark-H3-0.1.4-linux-x86_64-sm86-cu130.zip; \
    echo "b24d82127aa397c306c04b31bf9cc34df19129cb9374639fcd014a286a2c6759  $SPARK_ZIP" | sha256sum -c -; \
    python3 -c 'import zipfile; zipfile.ZipFile("/tmp/ComfyUI-Spark-H3-0.1.4-linux-x86_64-sm86-cu130.zip").extractall("/tmp/spark-h3-install")'; \
    WHEEL="$(find /tmp/spark-h3-install -type f -name 'comfy_kitchen-0.2.37+spark.h3.sm86.cu130.1-*.whl' -print -quit)"; \
    test -n "$WHEEL"; \
    python3 -m pip install --no-cache-dir --force-reinstall --no-deps "$WHEEL"; \
    rm -rf /tmp/spark-h3-install "$SPARK_ZIP"

# Build images have no NVIDIA GPU, so don't run Spark's GPU-dependent installer.
# Validate the correct installed wheel now; verify the CUDA symbol at runtime.
RUN python3 - <<'PYSPARK'
from importlib.metadata import version
actual = version('comfy-kitchen')
expected = '0.2.37+spark.h3.sm86.cu130.1'
assert actual == expected, f'Spark backend version mismatch: {actual}'
print('Spark-H3 backend installed:', actual)
PYSPARK

'''
ANCHOR = "# -----------------------------------------------------------------------------\n# Non-brittle build smoke test"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, help="Use a local Dockerfile instead of GitHub main")
    ap.add_argument("--output", type=Path,
                    default=Path("Dockerfile-ComfyUI-TrueNAS-Spark-Fixed"),
                    help="Destination for the replacement Dockerfile")
    args = ap.parse_args()

    if args.input:
        source = args.input.read_bytes().decode("utf-8")
    else:
        req = urllib.request.Request(RAW_URL, headers={"User-Agent": "ComfyUI-Spark-Dockerfile-Fix"})
        with urllib.request.urlopen(req, timeout=30) as response:
            source = response.read().decode("utf-8")

    newline = "\r\n" if "\r\n" in source else "\n"
    normalized = source.replace("\r\n", "\n")
    if "spark.h3.sm86.cu130.1" in normalized:
        sys.exit("Dockerfile already contains the Spark-H3 wheel; no changes made.")
    if "ARG COMFYUI_REF=v0.39.0" not in normalized:
        sys.exit("Unexpected ComfyUI version; not patching an unverified Dockerfile.")
    if "ARG TORCH_VERSION=2.13.0" not in normalized:
        sys.exit("Unexpected PyTorch version; not patching an unverified Dockerfile.")
    if normalized.count(ANCHOR) != 1:
        sys.exit("Could not locate unique smoke-test insertion point; no changes made.")
    replacement = normalized.replace(ANCHOR, BLOCK + ANCHOR)
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(replacement.replace("\n", newline).encode("utf-8"))
    print("Updated Dockerfile:", output)
    print("Added Spark-H3 0.1.4 SM86 CUDA 13.0 comfy-kitchen 0.2.37 backend")
    print("Original source kept unchanged. Upload the generated file to GitHub as Dockerfile.")


if __name__ == "__main__":
    main()
