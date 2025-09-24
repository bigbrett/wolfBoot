# Helper commands for TC3xx wolfBoot using wolf-startup-tc3xx BSP. Uses the "just"
#  command runner to run various tasks.
#
# Prerequisites: Working rust installation (for just)
# First install just: `cargo install just`
#
# Run `just --list` to list available targets
#
# Run `just <target>` from the top level wolfBoot directory to build a given
# target. This simply executes the commands in this file, just like make
#
# Note: You need to ensure the following environment variables are set
#
# HT_TRICORE_PATH: path to your hightec GCC installation (only for tricore targets)
# WOLFHSM_PORT_DIR: path to the wolfHSM tc3xx port (wolfHSM-infineon-tc3xx-v1.3.0)
# TC3_DIR: path to the tc3 directory in the wolfSSL TC3 BSP layer (wolf-startup-tc3xx/tc3)

# TC375 wolfBoot tricore build
tc3:
    cp config/examples/aurix-tc375.config .config
    # Build wolfBoot
    make GCC=1
    # sign the update image
    tools/keytools/sign --ecc256 test-app/image.bin wolfboot_signing_private_key.der 2


# TC375 wolfBoot tricore build with elf scatter loading
tc3-elf:
    cp config/examples/aurix-tc375-elf.config .config
    # Build wolfBoot
    make GCC=1
    # sign the update image
    tools/keytools/sign --ecc256 test-app/image.elf wolfboot_signing_private_key.der 2


# TC375 wolfBoot tricore build with elf scatter loading and wolfHSM crypto offload
tc3-elf-wolfHSM:
    cp config/examples/aurix-tc375-elf-wolfHSM.config .config
    # Build wolfBoot
    make GCC=1
    # sign the update image
    tools/keytools/sign --ecc256 test-app/image.elf wolfboot_signing_private_key.der 2


# TC375 wolfBoot tricore build with elf scatter loading and cert chain images verification using wolfHSM
tc3-elf-certs-wolfHSM:
    cp config/examples/aurix-tc375-elf-wolfHSM-certs.config .config
    # Build wolfBoot
    make GCC=1
    ## sign the update image with the cert chain
    tools/keytools/sign --ecc256 --cert-chain test-dummy-ca/raw-chain.der test-app/image.elf test-dummy-ca/leaf-prvkey.der 2

# TC375 HSM ARM wolfBoot build
tc3-hsm:
    cp config/examples/aurix-tc375-hsm.config .config
    # build wolfBoot
    make GCC=1
    # sign the update image
    tools/keytools/sign --ecc256 test-app/image.bin wolfboot_signing_private_key.der 2

# TODO: TC375 HSM ARM wolfBoot build with server-local cert chain verification via wolfHSM server API
tc3-hsm-certs:
    # TODO
    #cp config/examples/aurix-tc375-hsm-wolfHSM-certs.config .config
    ## build wolfBoot
    #make GCC=1
    ## sign the update image with the private key corresponding to the leaf cert
    #tools/keytools/sign --ecc256 test-app/image.bin test-dummy-ca/leaf-prvkey.der 2


# Delete all wolfBoot build artifacts including keys and certificates
clean:
    make clean
    make keysclean
    find ../wolf-startup-tc3xx/tc3/src -type f -name "*.o" -delete
