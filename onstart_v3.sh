#!/bin/bash
# ============================================================================
# DURDOM UNIFIED V3 — provisioning под РЕАЛЬНЫЕ workflows (после анализа)
# ============================================================================
# Качает все публичные модели с HuggingFace через aria2c (8 потоков).
# CyberRealisticPony качает с Civitai через токен (если задан CIVITAI_TOKEN).
#
# Использование в Vast Template:
#   1. Image Path:   ghcr.io/ai-dock/comfyui
#   2. Version Tag:  latest-cuda
#   3. Open Ports:   8188:8188
#   4. Disk:         100 GB (или 150 если хочешь запас)
#   5. Launch Mode:  Docker ENTRYPOINT
#   6. Environment Variables:
#        CIVITAI_TOKEN=<твой_токен_с_civitai>
#        JUPYTER_ENABLE=false
#        CF_QUICK_TUNNELS=false
#   7. On-start Script: всё что ниже (от set -e до конца файла)
# ============================================================================

#!/bin/bash
# НЕ используем set -e — мы хотим продолжать даже если отдельные DL фейлятся

WORKSPACE=${WORKSPACE:-/workspace}
COMFY=$WORKSPACE/ComfyUI

if [ ! -d "$COMFY" ]; then
    echo "ComfyUI ещё не подготовлен ai-dock'ом, жду..."
    sleep 30
fi

# ─── Устанавливаем aria2c (для параллельной скачки больших файлов) ───────────
if ! command -v aria2c &>/dev/null; then
    echo "Устанавливаю aria2c..."
    apt-get update -qq 2>&1 | tail -3
    apt-get install -y -qq aria2 2>&1 | tail -3
fi

# Проверяем что есть aria2c, иначе будем использовать wget
HAS_ARIA2=$(command -v aria2c &>/dev/null && echo "yes" || echo "no")
echo "aria2c доступен: $HAS_ARIA2"

mkdir -p \
  $COMFY/models/diffusion_models \
  $COMFY/models/checkpoints \
  $COMFY/models/loras \
  $COMFY/models/vae \
  $COMFY/models/text_encoders \
  $COMFY/models/clip_vision \
  $COMFY/models/model_patches \
  $COMFY/models/depth_anything \
  $COMFY/models/detection \
  $COMFY/custom_nodes

cd $COMFY/custom_nodes

# Custom nodes
[ ! -d ComfyUI-VideoHelperSuite ]    && git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
[ ! -d ComfyUI-WanVideoWrapper ]     && git clone --depth=1 https://github.com/kijai/ComfyUI-WanVideoWrapper.git
[ ! -d ComfyUI-WanAnimatePreprocess ] && git clone --depth=1 https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git
[ ! -d ComfyUI-Manager ]             && git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git
[ ! -d comfyui_controlnet_aux ]      && git clone --depth=1 https://github.com/Fannovel16/comfyui_controlnet_aux.git
[ ! -d ComfyUI-DepthAnythingV2 ]     && git clone --depth=1 https://github.com/kijai/ComfyUI-DepthAnythingV2.git

for d in ComfyUI-VideoHelperSuite ComfyUI-WanVideoWrapper ComfyUI-WanAnimatePreprocess ComfyUI-Manager comfyui_controlnet_aux ComfyUI-DepthAnythingV2; do
    if [ -f $d/requirements.txt ]; then
        cd $d && pip install -q -r requirements.txt 2>/dev/null || true
        cd ..
    fi
done

# ─── Универсальная функция скачки ────────────────────────────────────────────
DL() {
    local url=$1
    local dest=$2
    if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null)" -gt 1000000 ]; then
        echo "  ✓ $(basename $dest) — уже есть"
        return 0
    fi
    echo "  ▼ $(basename $dest)..."
    local fname="$(basename $dest)"
    local fdir="$(dirname $dest)"
    mkdir -p "$fdir"

    if [ "$HAS_ARIA2" = "yes" ]; then
        aria2c -x 8 -s 8 -c -q --console-log-level=error --check-certificate=false \
            --auto-file-renaming=false --allow-overwrite=true \
            -o "$fname" -d "$fdir" "$url" && return 0
        echo "    aria2c упал, пробую wget..."
    fi

    # Fallback на wget
    wget -q --show-progress=no -O "$dest" "$url" && return 0
    echo "    ⚠ Не удалось скачать $fname"
    return 1
}

echo "════════════════════════════════════════════"
echo "PHOTO модели"
echo "════════════════════════════════════════════"

DL "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" \
   "$COMFY/models/diffusion_models/z_image_turbo_bf16.safetensors"

DL "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" \
   "$COMFY/models/text_encoders/qwen_3_4b.safetensors"

DL "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" \
   "$COMFY/models/vae/ae.safetensors"

DL "https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union-2.1/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union-2.1.safetensors" \
   "$COMFY/models/model_patches/Z-Image-Turbo-Fun-Controlnet-Union-2.1.safetensors"

DL "https://huggingface.co/Kijai/DepthAnythingV2-safetensors/resolve/main/depth_anything_v2_vitl_fp32.safetensors" \
   "$COMFY/models/depth_anything/depth_anything_v2_vitl_fp32.safetensors" || true

# Также скачиваем как da3_giant.safetensors (то имя что хочет workflow)
DL "https://huggingface.co/Kijai/DepthAnythingV2-safetensors/resolve/main/depth_anything_v2_vitl_fp32.safetensors" \
   "$COMFY/models/depth_anything/da3_giant.safetensors" || true

# ─── CyberRealisticPony — приватный, нужен Civitai токен ────────────────────
# Токен можно задать как Environment Variable CIVITAI_TOKEN в Vast template,
# или будет использован зашитый fallback ниже.
CIVITAI_TOKEN=${CIVITAI_TOKEN:-9daa38b4cd8688ff77a6a278c3ace462}

if [ -n "$CIVITAI_TOKEN" ]; then
    echo ""
    echo "  ⏳ CyberRealisticPony V16.0 через Civitai..."
    # Model 443821, version V16.0: modelVersionId 2581228
    DL "https://civitai.com/api/download/models/2581228?token=${CIVITAI_TOKEN}" \
       "$COMFY/models/checkpoints/CyberRealisticPony_V16.0_FP32.safetensors" || \
       echo "  ⚠ CyberRealisticPony скачать не удалось — проверь токен"
else
    echo "  ⚠ CIVITAI_TOKEN не задан — CyberRealisticPony пропущен"
fi

echo ""
echo "════════════════════════════════════════════"
echo "VIDEO/LIPSYNC модели (Wan2.2-Animate)"
echo "════════════════════════════════════════════"

DL "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors" \
   "$COMFY/models/diffusion_models/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors"

DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors" \
   "$COMFY/models/vae/wan_2.1_vae.safetensors" || \
DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/wan_2.1_vae.safetensors" \
   "$COMFY/models/vae/wan_2.1_vae.safetensors"

DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-bf16.safetensors" \
   "$COMFY/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

DL "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
   "$COMFY/models/clip_vision/clip_vision_h.safetensors" || \
DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/clip_vision_h.safetensors" \
   "$COMFY/models/clip_vision/clip_vision_h.safetensors"

DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors" \
   "$COMFY/models/loras/lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors"

DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Pusa/Wan21_PusaV1_LoRA_14B_rank512_bf16.safetensors" \
   "$COMFY/models/loras/Wan21_PusaV1_LoRA_14B_rank512_bf16.safetensors"

DL "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" \
   "$COMFY/models/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" || true

DL "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" \
   "$COMFY/models/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" || true

DL "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Fun/Wan2.2-Fun-A14B-InP-low-noise-HPS2.1.safetensors" \
   "$COMFY/models/loras/Wan2.2-Fun-A14B-InP-low-noise-HPS2.1.safetensors" || true

echo ""
echo "════════════════════════════════════════════"
echo "ONNX detection (для Wan-Animate preprocess)"
echo "════════════════════════════════════════════"

DL "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx" \
   "$COMFY/models/detection/yolov10m.onnx"

DL "https://huggingface.co/JunkyByte/easy_ViTPose/resolve/main/onnx/wholebody/vitpose-l-wholebody.onnx" \
   "$COMFY/models/detection/vitpose-l-wholebody.onnx"

echo ""
echo "════════════════════════════════════════════"
echo "ТВОЯ LORA: Kaya"
echo "════════════════════════════════════════════"

DL "https://huggingface.co/HermanLord777/Kaya/resolve/main/Kaya.safetensors" \
   "$COMFY/models/loras/Kaya.safetensors"

echo ""
echo "════════════════════════════════════════════"
echo "ИТОГ: что реально на диске"
echo "════════════════════════════════════════════"
for d in diffusion_models checkpoints loras vae text_encoders clip_vision model_patches depth_anything detection; do
  count=$(ls -1 $COMFY/models/$d 2>/dev/null | wc -l)
  size=$(du -sh $COMFY/models/$d 2>/dev/null | cut -f1)
  echo "  $d: $count файлов, $size"
done

echo ""
echo "Критические файлы:"
[ -f $COMFY/models/loras/Kaya.safetensors ] && echo "  ✓ Kaya.safetensors" || echo "  ✗ Kaya.safetensors ОТСУТСТВУЕТ"
[ -f $COMFY/models/checkpoints/CyberRealisticPony_V16.0_FP32.safetensors ] && echo "  ✓ CyberRealisticPony" || echo "  ✗ CyberRealisticPony ОТСУТСТВУЕТ — workflow упадёт"
[ -f $COMFY/models/diffusion_models/z_image_turbo_bf16.safetensors ] && echo "  ✓ Z-Image Turbo" || echo "  ✗ Z-Image Turbo ОТСУТСТВУЕТ"
[ -f $COMFY/models/diffusion_models/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors ] && echo "  ✓ Wan2.2-Animate" || echo "  ✗ Wan2.2-Animate ОТСУТСТВУЕТ"

echo ""
echo "════════════════════════════════════════════"
echo "Чиню SSH ключи (bad ownership/modes fix)"
echo "════════════════════════════════════════════"
chmod 700 /root/.ssh 2>/dev/null
chmod 600 /root/.ssh/authorized_keys 2>/dev/null
chown -R root:root /root/.ssh 2>/dev/null
echo "✓ SSH права исправлены"

echo ""
echo "════════════════════════════════════════════"
echo "Запускаю ComfyUI"
echo "════════════════════════════════════════════"

# Удаляем все маркеры provisioning'а — supervisor увидит что готово
rm -f /.provisioning /workspace/.provisioning 2>/dev/null
touch /workspace/.provisioning_done

# Если supervisor работает — пинаем его перезапустить comfyui сервис
if command -v supervisorctl &>/dev/null; then
    echo "Перезапускаю comfyui через supervisor..."
    supervisorctl restart comfyui 2>&1 | head -5 || \
    supervisorctl start comfyui 2>&1 | head -5 || true
fi

# Ждём 10 секунд и проверяем поднялся ли
sleep 10
if ! ss -tlnp 2>/dev/null | grep -q ":8188"; then
    echo "ComfyUI не стартовал через supervisor, запускаю вручную..."
    cd $COMFY
    nohup python main.py --listen 0.0.0.0 --port 8188 \
        > /workspace/comfyui_manual.log 2>&1 &
    echo "ComfyUI запущен вручную, PID: $!"
    sleep 5
fi

if ss -tlnp 2>/dev/null | grep -q ":8188"; then
    echo "✓ ComfyUI слушает на :8188"
else
    echo "⚠ ComfyUI всё ещё не слушает! Лог: /workspace/comfyui_manual.log"
fi

echo "✓ Provisioning завершён"
