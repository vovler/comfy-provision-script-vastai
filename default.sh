#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI
COMFYUI_MANAGER_CLI_DIR=${COMFYUI_DIR}/custom_nodes/ComfyUI-Manager/cm-cli.py

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# Path to the ComfyUI‑Manager configuration file that controls the security level.
# This script guarantees that the security level is forced to **low** before any
# other provisioning steps run, as requested.
CONFIG_FILE="/workspace/ComfyUI/user/default/ComfyUI-Manager/config.ini"

# Packages are installed after nodes so we can fix them if needed.
APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
)

# -----------------------------------------------------------------------------
# Node, workflow and model definitions
# -----------------------------------------------------------------------------
# PLEASE USE https://api.comfy.org/nodes?page=1&limit=300&comfyui_version=0&form_factor=
# and iterate through the pages until you find your node to get the correct node_id.
# If you want to double‑check whether the node_id is correct open
# https://api.comfy.org/nodes/NODE_ID_GOES_HERE/install . If it doesn’t say
# "node not found", you’re good. IT'S NOT ALWAYS THE PACKAGE'S GITHUB NAME OR THE
# NAME IN THE Manager's GUI AND YOU WILL NOT FIND THE ID USING INPECT ELEMENT EITHER!!!
# LOST 3 HOURS DEBUGGING ComfyUI‑Manager FOR THIS SHIT.
NODES=(
    "comfyui-impact-pack"
    "comfyui-impact-subpack"
    "ComfyUI-Crystools"
    "comfyui_tensorrt"
    "efficiency-nodes-comfyui"
    "https://github.com/vovler/ComfyUI-vovlerTools"
)

WORKFLOWS=(
    "https://raw.githubusercontent.com/vovler/comfy-provision-script-vastai/refs/heads/main/adetailer.json"
)

CHECKPOINT_MODELS=(
    "https://huggingface.co/Ine007/waiNSFWIllustrious_v140/resolve/main/waiNSFWIllustrious_v140.safetensors"
)

UNET_MODELS=(
)

LORA_MODELS=(
  "https://huggingface.co/tianweiy/DMD2/resolve/main/dmd2_sdxl_4step_lora_fp16.safetensors"
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

YOLO_MODELS=(
    # face_yolo8m.pt is automatically installed with impact‑subpack
    "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8s.pt"
    "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8n.pt"
)

### --------------------------------------------------------------------------
### FUNCTIONS
### --------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Guarantee low security level BEFORE anything else happens
#------------------------------------------------------------------------------
function provisioning_set_security_level() {
    local cfg="$CONFIG_FILE"
    # Ensure directory exists
    mkdir -p "$(dirname "$cfg")"

    if [[ ! -f "$cfg" ]]; then
        # Fresh file: create the section and setting
        printf "[general]\nsecurity_level = weak\n" > "$cfg"
    else
        # Existing file: replace or append the setting
        if grep -qE "^\s*security_level\s*=" "$cfg"; then
            sed -i 's/^\s*security_level\s*=.*/security_level = weak/' "$cfg"
        else
            echo "security_level = weak" >> "$cfg"
        fi
    fi

    printf "Configured security_level=weak in %s\n" "$cfg"
}

function provisioning_start() {
    provisioning_print_header

    # *** Set security level first ***
    provisioning_set_security_level

    provisioning_get_apt_packages
    provisioning_get_pip_packages
    provisioning_update_comfy
    provisioning_get_nodes
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/loras" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/ultralytics/bbox" \
        "${YOLO_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/user/default/workflows" \
        "${WORKFLOWS[@]}"

    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
        sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_update_comfy(){
    python "${COMFYUI_MANAGER_CLI_DIR}" update all --mode=remote
    python -m pip install -r /workspace/ComfyUI/requirements.txt
}

function provisioning_get_pip_packages() {
    pip install --upgrade pip
    if [[ -n $PIP_PACKAGES ]]; then
        pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    python "${COMFYUI_MANAGER_CLI_DIR}" install "${NODES[@]}"
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif 
        [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]];then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
