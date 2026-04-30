#!/bin/bash
# ============================================================================
# DURDOM onstart — качает модели при первом запуске контейнера
# ============================================================================
# Если volume переиспользуется (persistent), модели уже на диске — пропускаются.
# Если первый запуск, качает ~78GB через aria2c (8 потоков).
# ============================================================================

COMFY=/workspace/ComfyUI

# ─── Универсальная функция скачки ──────────────────────────────────────────
DL() {
    local url=$1
    local dest=$2
    local fname=$(basename $dest)
    local fdir=$(dirname $dest)
    mkdir -p "$fdir"

    if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null)" -gt 1000000 ]; then
        echo "  ✓ $fname — уже есть"
        return 0
    fi

    echo "  ▼ $fname..."
    aria2c -x 8 -s 8 -c -q --console-log-level=error --check-certificate=false \
        --auto-file-renaming=false --allow-overwrite=true \
        -o "$fname" -d "$fdir" "$url" 2>&1 | tail -2 \
        || wget -q -O "$dest" "$url" \
        || { echo "    ⚠ Не удалось скачать $fname"; return 1; }
}

echo "═══════════════════════════════════════════"
echo "Provisioning: скачиваю модели"
echo "═══════════════════════════════════════════"

# ─── PHOTO модели (Z-Image Turbo) ──────────────────────────────────────────
echo ""
echo "[PHOTO]"

DL "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" \
   "$COMFY/models/diffusion_models/z_image_turbo_bf16.safetensors"

DL "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" \
   "$COMFY/models/text_encoders/qwen_3_4b.safetensors"

DL "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" \
   "$COMFY/models/vae/ae.safetensors"

DL "https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union-2.1/resolve/main/Z-Image-Turbo-Fun-Controlnet-Union-2.1.safetensors" \
   "$COMFY/models/model_patches/Z-Image-Turbo-Fun-Controlnet-Union-2.1.safetensors"

DL "https://huggingface.co/Kijai/DepthAnythingV2-safetensors/resolve/main/depth_anything_v2_vitl_fp32.safetensors" \
   "$COMFY/models/depth_anything/depth_anything_v2_vitl_fp32.safetensors"

# Дублируем под именем что хочет workflow
[ ! -f "$COMFY/models/depth_anything/da3_giant.safetensors" ] && \
   cp "$COMFY/models/depth_anything/depth_anything_v2_vitl_fp32.safetensors" \
      "$COMFY/models/depth_anything/da3_giant.safetensors" 2>/dev/null

# CyberRealisticPony через Civitai
CIVITAI_TOKEN=${CIVITAI_TOKEN:-9daa38b4cd8688ff77a6a278c3ace462}
echo ""
echo "[Civitai]"
DL "https://civitai.com/api/download/models/2581228?token=${CIVITAI_TOKEN}" \
   "$COMFY/models/checkpoints/CyberRealisticPony_V16.0_FP32.safetensors"

# ─── VIDEO/LIPSYNC (Wan2.2-Animate) ────────────────────────────────────────
echo ""
echo "[VIDEO/LIPSYNC]"

DL "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors" \
   "$COMFY/models/diffusion_models/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors"

DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors" \
   "$COMFY/models/vae/wan_2.1_vae.safetensors"

DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-bf16.safetensors" \
   "$COMFY/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

DL "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
   "$COMFY/models/clip_vision/clip_vision_h.safetensors"

DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors" \
   "$COMFY/models/loras/lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors"

DL "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Pusa/Wan21_PusaV1_LoRA_14B_rank512_bf16.safetensors" \
   "$COMFY/models/loras/Wan21_PusaV1_LoRA_14B_rank512_bf16.safetensors"

DL "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors" \
   "$COMFY/models/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"

DL "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors" \
   "$COMFY/models/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"

# ─── ONNX detection ────────────────────────────────────────────────────────
echo ""
echo "[ONNX]"

DL "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx" \
   "$COMFY/models/detection/yolov10m.onnx"

DL "https://huggingface.co/JunkyByte/easy_ViTPose/resolve/main/onnx/wholebody/vitpose-l-wholebody.onnx" \
   "$COMFY/models/detection/vitpose-l-wholebody.onnx"

# ─── ТВОЯ LORA: Kaya ───────────────────────────────────────────────────────
echo ""
echo "[Kaya]"

DL "https://huggingface.co/HermanLord777/Kaya/resolve/main/Kaya.safetensors" \
   "$COMFY/models/loras/Kaya.safetensors"

# ─── Итог ──────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "ИТОГ"
echo "═══════════════════════════════════════════"
for d in diffusion_models checkpoints loras vae text_encoders clip_vision model_patches depth_anything detection; do
    count=$(ls -1 $COMFY/models/$d 2>/dev/null | wc -l)
    size=$(du -sh $COMFY/models/$d 2>/dev/null | cut -f1)
    echo "  $d: $count файлов, $size"
done

echo ""
[ -f $COMFY/models/loras/Kaya.safetensors ] && echo "✓ Kaya.safetensors" || echo "✗ Kaya.safetensors ОТСУТСТВУЕТ"
[ -f $COMFY/models/checkpoints/CyberRealisticPony_V16.0_FP32.safetensors ] && echo "✓ CyberRealisticPony" || echo "✗ CyberRealisticPony ОТСУТСТВУЕТ"
[ -f $COMFY/models/diffusion_models/z_image_turbo_bf16.safetensors ] && echo "✓ Z-Image Turbo" || echo "✗ Z-Image Turbo"
[ -f $COMFY/models/diffusion_models/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors ] && echo "✓ Wan2.2-Animate" || echo "✗ Wan2.2-Animate"

echo ""
echo "═══════════════════════════════════════════"
echo "Provisioning ОК. ComfyUI стартует..."
echo "═══════════════════════════════════════════"
