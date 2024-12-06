#!/bin/bash

# wbaurixtool.sh - wolfBoot AURIX TC3xx Build Tool
#
# This tool provides a unified interface for building and signing wolfBoot images
# for the AURIX TC3xx platform. It handles:
#
# - Generating the appropriate wolfBoot configuration macros based on the selected
#   signature algorithm
# - Generating linker files (LCF) compatible with the selected build options
# - Key generation
# - Signing firmware images
# - Creating HSM NVM images when using wolfHSM
#
# This tool can be used with or without wolfHSM integration.
#
# Usage: ./wbaurixtool.sh <operation> [options]
# Operations: keygen, sign, macros, lcf, clean, target, nvm
# Run with -h for detailed help on available options


set -euo pipefail

# File paths (relative to project root)
WOLFBOOT_DIR="../../../"
PRVKEY_DER="$WOLFBOOT_DIR/priv.der"
PUBKEY_DER="$WOLFBOOT_DIR/priv_pub.der"
TARGET_H="$WOLFBOOT_DIR/include/target.h"
MACROS_IN="$WOLFBOOT_DIR/IDE/AURIX/wolfBoot-tc3xx-wolfHSM/wolfBoot_macros.in"
MACROS_OUT="$WOLFBOOT_DIR/IDE/AURIX/wolfBoot-tc3xx-wolfHSM/wolfBoot_macros.txt"
NVM_CONFIG="$WOLFBOOT_DIR/tools/scripts/tc3xx/wolfBoot-wolfHSM-keys.nvminit"
NVM_BIN="whNvmImage.bin"
NVM_HEX="whNvmImage.hex"

# Default algorithm configuration
DEFAULT_SIGN_ALGO="ecc256"
DEFAULT_HASH_ALGO="sha256"

# Default values
HSM=""
OPERATIONS=()

# Structure to hold command options
declare -A KEYGEN_OPTS=(
    [sign_algo]="$DEFAULT_SIGN_ALGO"
    [nolocalkeys]=""
)
declare -A SIGN_OPTS=(
    [sign_algo]="$DEFAULT_SIGN_ALGO"
    [hash_algo]="$DEFAULT_HASH_ALGO"
    [build_type]="Release"
)
declare -A MACROS_OPTS=(
    [sign_algo]=""
    [hash_algo]=""
)
CURRENT_OPTS=""

# Add the mapping dictionaries
declare -A HASH_ALGO_MAP=(
    ["sha256"]="WOLFBOOT_HASH_SHA256"
    ["sha384"]="WOLFBOOT_HASH_SHA384"
    ["sha3"]="WOLFBOOT_HASH_SHA3_384"
)

declare -A SIGN_ALGO_MAP=(
    ["ed25519"]="WOLFBOOT_SIGN_ED25519"
    ["ed448"]="WOLFBOOT_SIGN_ED448"
    ["ecc256"]="WOLFBOOT_SIGN_ECC256"
    ["ecc384"]="WOLFBOOT_SIGN_ECC384"
    ["ecc521"]="WOLFBOOT_SIGN_ECC521"
    ["rsa2048"]="WOLFBOOT_SIGN_RSA2048"
    ["rsa3072"]="WOLFBOOT_SIGN_RSA3072"
    ["rsa4096"]="WOLFBOOT_SIGN_RSA4096"
    ["lms"]="WOLFBOOT_SIGN_LMS"
    ["xmss"]="WOLFBOOT_SIGN_XMSS"
    ["ml_dsa"]="WOLFBOOT_SIGN_ML_DSA"
    ["none"]="WOLFBOOT_NO_SIGN"
)

# Add nested map for ML-DSA header sizes
declare -A ML_DSA_HEADER_SIZES=(
    [2]=8192
    [3]=8192
    [5]=12288
)

# Get the header size based on the selected public key algorithm
get_header_size() {
    local algo="$1"
    local pq_params="$2"

    case "$algo" in
        "ml_dsa")
            # Default to level 2 for ML-DSA if no params specified
            echo "${ML_DSA_HEADER_SIZES[${pq_params:-2}]}"
            ;;
        "ecc256") echo "256" ;;
        "ecc384"|"ecc521"|"rsa2048"|"rsa3072") echo "512" ;;
        "rsa4096") echo "1024" ;;
        "ed25519") echo "256" ;;
        "ed448") echo "512" ;;
        "lms"|"xmss") echo "0" ;;
        "none") echo "256" ;;
        *) echo "256" ;;  # Default
    esac
}

# Add to command options structure
declare -A COMMON_OPTS=(
    [sign_pq_params]=""
)

# Add LCF_OPTS to command options structure
declare -A LCF_OPTS=(
    [sign_algo]="$DEFAULT_SIGN_ALGO"
)

# Helper function to display usage
usage() {
    echo "Usage: $0 [global-options] COMMAND [command-options] [COMMAND [command-options]]"
    echo ""
    echo "Global Options:"
    echo "  --hsm                   Use wolfHSM version"
    echo ""
    echo "Commands and their options:"
    echo "  keygen"
    echo "    --sign-algo ALGO      Signing algorithm (default: ecc256)"
    echo "    --localkeys           Use local keys (only valid with --hsm)"
    echo ""
    echo "  sign"
    echo "    --sign-algo ALGO      Signing algorithm (inherits from keygen if not specified)"
    echo "    --hash-algo ALGO      Hash algorithm (default: sha256)"
    echo "    --debug               Use debug build (default: release)"
    echo ""
    echo "  target"
    echo "    No additional options"
    echo ""
    echo "  clean"
    echo "    No additional options"
    echo ""
    echo "  macros"
    echo "    --sign-algo ALGO      Signing algorithm (inherits from keygen/sign if not specified)"
    echo "    --hash-algo ALGO      Hash algorithm (inherits from sign if not specified)"
    echo ""
    echo "  nvm"
    echo "    No additional options"
    echo ""
    echo "  lcf"
    echo "    --sign-algo ALGO      Signing algorithm (inherits from keygen/sign if not specified)"
    echo ""
    echo "Examples:"
    echo "  $0 keygen --sign-algo ecc256"
    echo "  $0 sign --hash-algo sha256 --debug"
    echo "  $0 keygen --sign-algo ecc256 sign --hash-algo sha256"
    echo "  $0 --hsm keygen --sign-algo ecc256 --localkeys sign --debug"
    echo "  $0 target"
    echo "  $0 clean"
    echo "  $0 macros"
    echo "  $0 nvm"
    echo "  $0 lcf"
    exit 1
}

# Function to generate keys
do_keygen() {
    local base_dir="../../../"

    echo "Generating keys with algorithm: ${KEYGEN_OPTS[sign_algo]}"
    (cd $base_dir && tools/keytools/keygen --"${KEYGEN_OPTS[sign_algo]}" -g $(basename $PRVKEY_DER) --exportpubkey \
        ${KEYGEN_OPTS[nolocalkeys]:+--nolocalkeys} --der)
}

# Function to sign binaries
do_sign() {
    local base_path="../../../IDE/AURIX"
    local app_name="test-app${HSM:+-wolfHSM}"
    local sign_algo="${SIGN_OPTS[sign_algo]:-${KEYGEN_OPTS[sign_algo]}}"

    echo "Signing binaries with $sign_algo and ${SIGN_OPTS[hash_algo]}"
    local bin_path="$base_path/$app_name/TriCore ${SIGN_OPTS[build_type]} (GCC)/$app_name.bin"

    # Sign for both partition 1 and 2
    ../../keytools/sign --"$sign_algo" --"${SIGN_OPTS[hash_algo]}" "$bin_path" "$PRVKEY_DER" 1
    ../../keytools/sign --"$sign_algo" --"${SIGN_OPTS[hash_algo]}" "$bin_path" "$PRVKEY_DER" 2
}

# Function to generate target header
do_gen_target() {
    local target_h_template="${TARGET_H}.in"

    local wolfboot_sector_size=0x4000
    local wolfboot_partition_size=0x17E000
    local wolfboot_partition_boot_address=0xA0300000
    local wolfboot_partition_update_address=0xA047E000
    local wolfboot_partition_swap_address=0xA05FC000

    local wolfboot_dts_boot_address=""
    local wolfboot_dts_update_address=""
    local wolfboot_load_address=""
    local wolfboot_load_dts_address=""

    echo "Generating target header file"
    cat $target_h_template | \
        sed -e "s/@WOLFBOOT_PARTITION_SIZE@/$wolfboot_partition_size/g" | \
        sed -e "s/@WOLFBOOT_SECTOR_SIZE@/$wolfboot_sector_size/g" | \
        sed -e "s/@WOLFBOOT_PARTITION_BOOT_ADDRESS@/$wolfboot_partition_boot_address/g" | \
        sed -e "s/@WOLFBOOT_PARTITION_UPDATE_ADDRESS@/$wolfboot_partition_update_address/g" | \
        sed -e "s/@WOLFBOOT_PARTITION_SWAP_ADDRESS@/$wolfboot_partition_swap_address/g" | \
        sed -e "s/@WOLFBOOT_DTS_BOOT_ADDRESS@/$wolfboot_dts_boot_address/g" | \
        sed -e "s/@WOLFBOOT_DTS_UPDATE_ADDRESS@/$wolfboot_dts_update_address/g" | \
        sed -e "s/@WOLFBOOT_LOAD_ADDRESS@/$wolfboot_load_address/g" | \
        sed -e "s/@WOLFBOOT_LOAD_DTS_ADDRESS@/$wolfboot_load_dts_address/g" \
        > "$TARGET_H"
}

# Function to clean generated files
do_clean() {
    echo "Cleaning generated files"
    rm -f "$PRVKEY_DER"
    rm -f "$PUBKEY_DER"
    rm -f "$TARGET_H"
    rm -f "$MACROS_OUT"
    rm -f "$NVM_BIN"
    rm -f "$NVM_HEX"
}

# Function to generate macros
do_gen_macros() {
    # Use macros options first, then fall back to sign/keygen options
    local sign_algo="${MACROS_OPTS[sign_algo]:-${SIGN_OPTS[sign_algo]:-${KEYGEN_OPTS[sign_algo]:-$DEFAULT_SIGN_ALGO}}}"
    local hash_algo="${MACROS_OPTS[hash_algo]:-${SIGN_OPTS[hash_algo]}}"
    local pq_params="${COMMON_OPTS[sign_pq_params]}"

    # Get header size using the new function
    local image_header_size=$(get_header_size "$sign_algo" "$pq_params")

    local use_huge_stack=""
    local use_wolfhsm_pubkey_id=""
    local image_signature_size=""
    local ml_dsa_image_signature_size=""
    local ml_dsa_level=""

    # Map algorithms to their macro names
    local sign_macro="${SIGN_ALGO_MAP[${sign_algo,,}]:-}"
    local hash_macro="${HASH_ALGO_MAP[${hash_algo,,}]:-}"

    if [[ -z "$sign_macro" ]]; then
        echo "Error: Invalid or missing signing algorithm"
        exit 1
    fi
    if [[ -z "$hash_macro" ]]; then
        echo "Error: Invalid or missing hash algorithm"
        exit 1
    fi

    # Set huge stack for RSA4096
    if [[ "${sign_algo,,}" == "rsa4096" ]]; then
        use_huge_stack="-DWOLFBOOT_HUGE_STACK"
    fi

    # Set HSM pubkey ID if using HSM without local keys
    if [[ -n "$HSM" && -n "${KEYGEN_OPTS[nolocalkeys]}" ]]; then
        use_wolfhsm_pubkey_id="-DWOLFBOOT_USE_WOLFHSM_PUBKEY_ID"
    fi

    # Set image signature size and ML-DSA level only for ML-DSA
    if [[ "${sign_algo,,}" == ml_dsa* ]]; then
        image_signature_size="-DIMAGE_SIGNATURE_SIZE=2420"
        ml_dsa_image_signature_size="-DML_DSA_IMAGE_SIGNATURE_SIZE=2420"
        ml_dsa_level="-DML_DSA_LEVEL=2"
    fi

    echo "Generating macros file with sign_algo=$sign_algo, hash_algo=$hash_algo"
    sed -e "s/@HASH_ALGO@/${hash_macro#WOLFBOOT_HASH_}/g" \
        -e "s/@SIGN_ALGO@/${sign_macro#WOLFBOOT_SIGN_}/g" \
        -e "s/@IMAGE_HEADER_SIZE@/$image_header_size/g" \
        -e "s/@IMAGE_SIGNATURE_SIZE@/$image_signature_size/g" \
        -e "s/@ML_DSA_LEVEL@/$ml_dsa_level/g" \
        -e "s/@ML_DSA_IMAGE_SIGNATURE_SIZE@/$ml_dsa_image_signature_size/g" \
        -e "s/@WOLFBOOT_HUGE_STACK@/$use_huge_stack/g" \
        -e "s/@WOLFBOOT_USE_WOLFHSM_PUBKEY_ID@/$use_wolfhsm_pubkey_id/g" \
        "$MACROS_IN" > "$MACROS_OUT"

    # Remove empty lines from the output file, as they cause compiler errors
    sed -i '/^$/d' "$MACROS_OUT"
}

# Function to generate a wolfHSM NVM image
do_gen_nvm() {
    echo "Generating HSM NVM image"
    echo "Running: whnvmtool --image=$NVM_BIN --size=0x10000 --invert-erased-byte $NVM_CONFIG"
    whnvmtool --image="$NVM_BIN" --size=0x10000 --invert-erased-byte "$NVM_CONFIG"

    echo "Converting to Intel HEX format"
    echo "Running: objcopy -I binary -O ihex --change-address 0xAFC00000 $NVM_BIN $NVM_HEX"
    objcopy -I binary -O ihex --change-address 0xAFC00000 "$NVM_BIN" "$NVM_HEX"
}

# Function to generate LCF file
do_gen_lcf() {
    # Check LCF_OPTS first, then fall back to SIGN_OPTS and KEYGEN_OPTS, default to DEFAULT_SIGN_ALGO
    local sign_algo="${LCF_OPTS[sign_algo]:-${SIGN_OPTS[sign_algo]:-${KEYGEN_OPTS[sign_algo]:-$DEFAULT_SIGN_ALGO}}}"
    local pq_params="${COMMON_OPTS[sign_pq_params]}"
    local header_size

    # Determine target directory based on HSM flag
    local base_dir="$WOLFBOOT_DIR/IDE/AURIX"
    local app_dir="test-app${HSM:+-wolfHSM}"
    local lcf_template="$base_dir/$app_dir/Lcf_Gnuc_Tricore_Tc.lsl.in"
    local lcf_output="$base_dir/$app_dir/Lcf_Gnuc_Tricore_Tc.lsl"

    header_size=$(get_header_size "$sign_algo" "$pq_params")

    echo "Generating LCF file with header_size=$header_size"
    sed -e "s/@LCF_WOLFBOOT_HEADER_OFFSET@/$header_size/g" \
        "$lcf_template" > "$lcf_output"
}

# Parse global options first
while [[ $# -gt 0 ]]; do
    case $1 in
        --hsm)
            HSM="1"
            KEYGEN_OPTS[nolocalkeys]="1"
            shift
            ;;
        keygen|sign|target|clean|macros|nvm|lcf)
            break
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown global option: $1"
            usage
            ;;
    esac
done

# Now parse commands and their options
while [[ $# -gt 0 ]]; do
    case $1 in
        keygen)
            OPERATIONS+=("keygen")
            CURRENT_OPTS="KEYGEN_OPTS"
            shift
            ;;
        sign)
            OPERATIONS+=("sign")
            CURRENT_OPTS="SIGN_OPTS"
            shift
            ;;
        target)
            OPERATIONS+=("target")
            CURRENT_OPTS=""
            shift
            ;;
        clean)
            OPERATIONS+=("clean")
            CURRENT_OPTS=""
            shift
            ;;
        macros)
            OPERATIONS+=("macros")
            CURRENT_OPTS="MACROS_OPTS"
            shift
            ;;
        nvm)
            OPERATIONS+=("nvm")
            CURRENT_OPTS=""
            shift
            ;;
        lcf)
            OPERATIONS+=("lcf")
            CURRENT_OPTS="LCF_OPTS"
            shift
            ;;
        --sign-algo)
            if [ -z "$CURRENT_OPTS" ]; then
                echo "Error: --sign-algo must follow a command"
                exit 1
            fi
            declare -n opts=$CURRENT_OPTS
            # Update all command options that use sign_algo
            KEYGEN_OPTS[sign_algo]="$2"
            SIGN_OPTS[sign_algo]="$2"
            MACROS_OPTS[sign_algo]="$2"
            LCF_OPTS[sign_algo]="$2"
            shift 2
            ;;
        --hash-algo)
            if [ -z "$CURRENT_OPTS" ]; then
                echo "Error: --hash-algo must follow a command"
                exit 1
            fi
            declare -n opts=$CURRENT_OPTS
            opts[hash_algo]="$2"
            shift 2
            ;;
        --localkeys)
            if [ "$CURRENT_OPTS" != "KEYGEN_OPTS" ]; then
                echo "Error: --localkeys only valid for keygen command"
                exit 1
            fi
            if [ -z "$HSM" ]; then
                echo "Error: --localkeys can only be used with --hsm"
                exit 1
            fi
            KEYGEN_OPTS[nolocalkeys]=""
            shift
            ;;
        --debug)
            if [ "$CURRENT_OPTS" != "SIGN_OPTS" ]; then
                echo "Error: --debug only valid for sign command"
                exit 1
            fi
            SIGN_OPTS[build_type]="Debug"
            shift
            ;;
        --sign-pq-params)
            if [[ -z "$CURRENT_OPTS" ]]; then
                echo "Error: --sign-pq-params must follow a command"
                exit 1
            fi

            # Validate the parameter value for ml_dsa
            if [[ "${KEYGEN_OPTS[sign_algo]}" == "ml_dsa" || "${SIGN_OPTS[sign_algo]}" == "ml_dsa" ]]; then
                if [[ ! "$2" =~ ^(2|3|5)$ ]]; then
                    echo "Error: --sign-pq-params must be 2, 3, or 5 for ML-DSA"
                    exit 1
                fi
            fi

            COMMON_OPTS[sign_pq_params]="$2"
            shift 2
            ;;
        *)
            echo "Unknown option for ${CURRENT_OPTS:-global options}: $1"
            usage
            ;;
    esac
done

# Validate that we have at least one operation
if [ ${#OPERATIONS[@]} -eq 0 ]; then
    echo "Error: Must specify at least one command (keygen, sign, or target)"
    usage
fi

# Execute requested operations in order
for op in "${OPERATIONS[@]}"; do
    case $op in
        "keygen")
            do_keygen
            ;;
        "sign")
            do_sign
            ;;
        "target")
            do_gen_target
            ;;
        "clean")
            do_clean
            ;;
        "macros")
            do_gen_macros
            ;;
        "nvm")
            do_gen_nvm
            ;;
        "lcf")
            do_gen_lcf
            ;;
    esac
done
