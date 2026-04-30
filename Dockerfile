# ============================================================================
# DURDOM ComfyUI Image — чистый, простой, быстрый
# ============================================================================
# База: nvidia/cuda с Python 3.11, без ai-dock и его supervisor-трюков
# Содержит: ComfyUI + 6 custom_nodes + все Python зависимости
# Модели качаются через onstart (или mount'ятся через volume)
#
# Сборка:
#   docker build -t hermanlord777/durdom-comfyui:v1 .
#   docker push hermanlord777/durdom-comfyui:v1
# ============================================================================

FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1
ENV PATH=/usr/local/bin:/usr/bin:/bin

# ─── Системные пакеты ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3-pip \
    git wget curl aria2 ffmpeg \
    openssh-server \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3

# pip upgrade
RUN python -m pip install --upgrade pip setuptools wheel

# ─── ComfyUI ────────────────────────────────────────────────────────────────
WORKDIR /workspace
RUN git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git ComfyUI

# PyTorch с CUDA 12.4
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# ComfyUI requirements
WORKDIR /workspace/ComfyUI
RUN pip install -r requirements.txt

# ─── Custom nodes ──────────────────────────────────────────────────────────
WORKDIR /workspace/ComfyUI/custom_nodes
RUN git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone --depth=1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git && \
    git clone --depth=1 https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git && \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth=1 https://github.com/Fannovel16/comfyui_controlnet_aux.git && \
    git clone --depth=1 https://github.com/kijai/ComfyUI-DepthAnythingV2.git

# Зависимости каждого custom_node
RUN for d in /workspace/ComfyUI/custom_nodes/*/; do \
        if [ -f "$d/requirements.txt" ]; then \
            echo "=== Installing for $(basename $d) ==="; \
            pip install -r "$d/requirements.txt" || echo "WARN: $(basename $d) requirements failed"; \
        fi; \
    done

# Дополнительные пакеты которые часто нужны
RUN pip install \
    matplotlib \
    av \
    einops \
    onnxruntime-gpu \
    sageattention \
    || echo "WARN: optional packages failed"

# ─── Папки моделей ─────────────────────────────────────────────────────────
RUN mkdir -p /workspace/ComfyUI/models/diffusion_models \
             /workspace/ComfyUI/models/checkpoints \
             /workspace/ComfyUI/models/loras \
             /workspace/ComfyUI/models/vae \
             /workspace/ComfyUI/models/text_encoders \
             /workspace/ComfyUI/models/clip_vision \
             /workspace/ComfyUI/models/model_patches \
             /workspace/ComfyUI/models/depth_anything \
             /workspace/ComfyUI/models/detection \
             /workspace/output

# ─── SSH (для отладки через Vast) ──────────────────────────────────────────
RUN mkdir -p /var/run/sshd && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config

# ─── Provisioning + entrypoint ─────────────────────────────────────────────
COPY onstart.sh /onstart.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /onstart.sh /entrypoint.sh

WORKDIR /workspace/ComfyUI
EXPOSE 8188 22

ENTRYPOINT ["/entrypoint.sh"]
