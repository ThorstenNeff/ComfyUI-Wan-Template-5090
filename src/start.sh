#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# This is in case there's any special installs or overrides that needs to occur when starting the machine before starting ComfyUI
if [ -f "/workspace/additional_params.sh" ]; then
    chmod +x /workspace/additional_params.sh
    echo "Executing additional_params.sh..."
    /workspace/additional_params.sh
else
    echo "additional_params.sh not found in /workspace. Skipping..."
fi

# Set the network volume path
NETWORK_VOLUME="/workspace"

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$NETWORK_VOLUME/ComfyUI/user/default/workflows"

# Set the target directory
CUSTOM_NODES_DIR="$NETWORK_VOLUME/ComfyUI/custom_nodes"

if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

echo "Downloading CivitAI download script to /usr/local/bin"
git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
mv CivitAI_Downloader/download.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
chmod +x "/usr/local/bin/download.py" || { echo "Chmod failed"; exit 1; }
rm -rf CivitAI_Downloader  # Clean up the cloned repo
pip install huggingface_hub
pip install onnxruntime-gpu

# Change to the directory
cd "$CUSTOM_NODES_DIR" || exit 1

# Function to download a model using huggingface-cli
download_model() {
  local destination_dir="$1"
  local destination_file="$2"
  local repo_id="$3"
  local file_path="$4"

  mkdir -p "$destination_dir"

  if [ ! -f "$destination_dir/$destination_file" ]; then
    echo "Downloading $destination_file..."

    # First, download to a temporary directory
    local temp_dir=$(mktemp -d)
    huggingface-cli download "$repo_id" "$file_path" --local-dir "$temp_dir" --resume-download

    # Find the downloaded file in the temp directory (may be in subdirectories)
    local downloaded_file=$(find "$temp_dir" -type f -name "$(basename "$file_path")")

    # Move it to the destination directory with the correct name
    if [ -n "$downloaded_file" ]; then
      mv "$downloaded_file" "$destination_dir/$destination_file"
      echo "Successfully downloaded to $destination_dir/$destination_file"
    else
      echo "Error: File not found after download"
    fi

    # Clean up temporary directory
    rm -rf "$temp_dir"
  else
    echo "$destination_file already exists, skipping download."
  fi
}

# Define base paths
DIFFUSION_MODELS_DIR="$NETWORK_VOLUME/ComfyUI/models/diffusion_models"
TEXT_ENCODERS_DIR="$NETWORK_VOLUME/ComfyUI/models/text_encoders"
CLIP_VISION_DIR="$NETWORK_VOLUME/ComfyUI/models/clip_vision"
VAE_DIR="$NETWORK_VOLUME/ComfyUI/models/vae"

# Download 480p native models
if [ "$download_480p_native_models" == "true" ]; then
  echo "Downloading 480p native models..."

  download_model "$DIFFUSION_MODELS_DIR" "Wan2_1-I2V-14B-480P_fp8_e5m2.safetensors" \
    "Kijai/WanVideo_comfy" "Wan2_1-I2V-14B-480P_fp8_e5m2.safetensors"

  download_model "$DIFFUSION_MODELS_DIR" "wan2.1_t2v_14B_bf16.safetensors" \
    "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/diffusion_models/wan2.1_t2v_14B_bf16.safetensors"

  download_model "$DIFFUSION_MODELS_DIR" "wan2.1_t2v_1.3B_fp16.safetensors" \
    "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors"
fi

# Handle full download (with SDXL)
if [ "$download_wan_fun_and_sdxl_helper" == "true" ]; then
  echo "Downloading Wan Fun 1.3B Model"

  download_model "$DIFFUSION_MODELS_DIR" "Wan2.1-Fun-Control1.3B.safetensors" \
    "alibaba-pai/Wan2.1-Fun-1.3B-Control" "diffusion_pytorch_model.safetensors"

  echo "Downloading Wan Fun 14B Model"

  download_model "$DIFFUSION_MODELS_DIR" "Wan2.1-Fun-Control14B.safetensors" \
    "alibaba-pai/Wan2.1-Fun-14B-Control" "diffusion_pytorch_model.safetensors"

  UNION_DIR="$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0"
  mkdir -p "$UNION_DIR"
  if [ ! -f "$UNION_DIR/diffusion_pytorch_model_promax.safetensors" ]; then
    download_model "$UNION_DIR" "diffusion_pytorch_model_promax.safetensors" \
    "xinsir/controlnet-union-sdxl-1.0" "diffusion_pytorch_model_promax.safetensors"
  fi
fi

if [ "$download_vace" == "true" ]; then
  echo "Downloading Wan 1.3B"

  download_model "$DIFFUSION_MODELS_DIR" "wan2.1_t2v_1.3B_fp16.safetensors" \
    "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors"

  echo "Downloading VACE 1.3B Model"

  download_model "$DIFFUSION_MODELS_DIR" "Wan2_1_VACE_1_3B_preview_bf16.safetensors" \
    "Kijai/WanVideo_comfy" "Wan2_1_VACE_1_3B_preview_bf16.safetensors"

  echo "Downloading VACE text encoder"

  download_model "$TEXT_ENCODERS_DIR" "umt5-xxl-enc-bf16.safetensors" \
    "Kijai/WanVideo_comfy" "umt5-xxl-enc-bf16.safetensors"
fi

# Download 720p native models
if [ "$download_720p_native_models" == "true" ]; then
  echo "Downloading 720p native models..."

  download_model "$DIFFUSION_MODELS_DIR" "wan2.1_i2v_720p_14B_bf16.safetensors" \
    "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/diffusion_models/wan2.1_i2v_720p_14B_bf16.safetensors"

  download_model "$DIFFUSION_MODELS_DIR" "wan2.1_t2v_14B_bf16.safetensors" \
    "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/diffusion_models/wan2.1_t2v_14B_bf16.safetensors"

  download_model "$DIFFUSION_MODELS_DIR" "wan2.1_t2v_1.3B_fp16.safetensors" \
    "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors"
fi

# Download text encoders
echo "Downloading text encoders..."

download_model "$TEXT_ENCODERS_DIR" "umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
  "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

download_model "$TEXT_ENCODERS_DIR" "open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" \
  "Kijai/WanVideo_comfy" "open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors"

# Create CLIP vision directory and download models
mkdir -p "$CLIP_VISION_DIR"
download_model "$CLIP_VISION_DIR" "clip_vision_h.safetensors" \
  "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/clip_vision/clip_vision_h.safetensors"

# Download VAE
echo "Downloading VAE..."
download_model "$VAE_DIR" "Wan2_1_VAE_bf16.safetensors" \
  "Kijai/WanVideo_comfy" "Wan2_1_VAE_bf16.safetensors"

download_model "$VAE_DIR" "wan_2.1_vae.safetensors" \
  "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/vae/wan_2.1_vae.safetensors"

# Download upscale model
echo "Downloading upscale models"
mkdir -p "$NETWORK_VOLUME/ComfyUI/models/upscale_models"
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4x_foolhardy_Remacri.pt" ]; then
    wget -O "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4x_foolhardy_Remacri.pt" \
    https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth
fi
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xLSDIR.pth" ]; then
    if [ -f "/4xLSDIR.pth" ]; then
        mv "/4xLSDIR.pth" "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xLSDIR.pth"
        echo "Moved 4xLSDIR.pth to the correct location."
    else
        echo "4xLSDIR.pth not found in the root directory."
    fi
else
    echo "4xLSDIR.pth already exists. Skipping."
fi

# Download film network model
echo "Downloading film network model"
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/film_net_fp32.pt" ]; then
    wget -O "$NETWORK_VOLUME/ComfyUI/models/upscale_models/film_net_fp32.pt" \
    https://huggingface.co/nguu/film-pytorch/resolve/887b2c42bebcb323baf6c3b6d59304135699b575/film_net_fp32.pt
fi

echo "Finished downloading models!"


echo "Checking and copying workflow..."
mkdir -p "$WORKFLOW_DIR"

# Ensure the file exists in the current directory before moving it
cd /

SOURCE_DIR="/ComfyUI-Wan-Template-5090/workflows"

# Ensure destination directory exists
mkdir -p "$WORKFLOW_DIR"

# Loop over each file in the source directory
for file in "$SOURCE_DIR"/*; do
    # Skip if it's not a file
    [[ -f "$file" ]] || continue

    dest_file="$WORKFLOW_DIR/$(basename "$file")"

    if [[ -e "$dest_file" ]]; then
        echo "File already exists in destination. Deleting: $file"
        rm -f "$file"
    else
        echo "Moving: $file to $WORKFLOW_DIR"
        mv "$file" "$WORKFLOW_DIR"
    fi
done

declare -A MODEL_CATEGORIES=(
    ["$NETWORK_VOLUME/ComfyUI/models/checkpoints"]="CHECKPOINT_IDS_TO_DOWNLOAD"
    ["$NETWORK_VOLUME/ComfyUI/models/loras"]="LORAS_IDS_TO_DOWNLOAD"
)

# Ensure directories exist and download models
for TARGET_DIR in "${!MODEL_CATEGORIES[@]}"; do
    ENV_VAR_NAME="${MODEL_CATEGORIES[$TARGET_DIR]}"
    MODEL_IDS_STRING="${!ENV_VAR_NAME}"  # Get the value of the environment variable

    # Skip if the environment variable is set to "ids_here"
    if [ "$MODEL_IDS_STRING" == "replace_with_ids" ]; then
        echo "Skipping downloads for $TARGET_DIR ($ENV_VAR_NAME is 'ids_here')"
        continue
    fi

    mkdir -p "$TARGET_DIR"
    IFS=',' read -ra MODEL_IDS <<< "$MODEL_IDS_STRING"

    for MODEL_ID in "${MODEL_IDS[@]}"; do
        echo "Downloading model: $MODEL_ID to $TARGET_DIR"
        (cd "$TARGET_DIR" && download.py --model "$MODEL_ID")
    done
done

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc

if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanVideoWrapper" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git
else
    echo "Updating WanVideoWrapper"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanVideoWrapper
    git pull
fi
if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-KJNodes" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/kijai/ComfyUI-KJNodes.git
else
    echo "Updating KJ Nodes"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-KJNodes
    git pull
fi

# Install dependencies
pip install --no-cache-dir -r $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanVideoWrapper/requirements.txt
pip install --no-cache-dir -r $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-KJNodes/requirements.txt

# Start ComfyUI
echo "Starting ComfyUI"
if [ "$enable_optimizations" = "false" ]; then
    python "$NETWORK_VOLUME/ComfyUI/main.py" --listen --preview-method auto
else
    python "$NETWORK_VOLUME/ComfyUI/main.py" --listen --use-sage-attention --preview-method auto
    if [ $? -ne 0 ]; then
        echo "ComfyUI failed with --use-sage-attention. Retrying without it..."
        python "$NETWORK_VOLUME/ComfyUI/main.py" --listen --preview-method auto
    fi
fi

cd /workspace/diffusion-pipe

# Installiere zusätzliche Pakete
pip install ninja
pip install --upgrade setuptools

# Installiere FlashAttention (für PyTorch 2.8 + CUDA 12)
pip install https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.0.post2/flash_attn-2.8.0.post2+cu12torch2.7cxx11abiTRUE-cp312-cp312-linux_x86_64.whl

# Installiere Projektabhängigkeiten
pip install -r requirements.txt