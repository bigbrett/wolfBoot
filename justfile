# TC375 wolfBoot build
tc3:
    cp config/examples/aurix-tc375.config .config
    # Build wolfBoot
    RLM_LICENSE=localhost@6004 \
        make \
            GCC=1 \
            HT_TRICORE_PATH=/opt/hightec/gnutri_v4.9.4.1-11fcedf-lin64/ \
            WOLFHSM_PORT_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolfhsm-private/infineon/tc3xx/ \
            TC3_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolf-startup-tc3xx/tc3
    # sign the update image
    tools/keytools/sign --ecc256 test-app/image.bin wolfboot_signing_private_key.der 2


# TC375 wolfBoot build with elf scatter loading
tc3-elf:
    cp config/examples/aurix-tc375-elf.config .config
    # Build wolfBoot
    RLM_LICENSE=localhost@6004 \
        make \
            GCC=1 \
            HT_TRICORE_PATH=/opt/hightec/gnutri_v4.9.4.1-11fcedf-lin64/ \
            WOLFHSM_PORT_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolfhsm-private/infineon/tc3xx/ \
            TC3_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolf-startup-tc3xx/tc3
    # sign the update image
    tools/keytools/sign --ecc256 test-app/image.elf wolfboot_signing_private_key.der 2


# TC375 wolfBoot build with elf scatter loading with wolfHSM crypto offload
tc3-elf-wolfHSM:
    cp config/examples/aurix-tc375-elf-wolfHSM.config .config
    # Build wolfBoot
    RLM_LICENSE=localhost@6004 \
        make \
            GCC=1 \
            HT_TRICORE_PATH=/opt/hightec/gnutri_v4.9.4.1-11fcedf-lin64/ \
            WOLFHSM_PORT_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolfhsm-private/infineon/tc3xx/ \
            TC3_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolf-startup-tc3xx/tc3
    # sign the update image
    tools/keytools/sign --ecc256 test-app/image.elf wolfboot_signing_private_key.der 2


# TC375 wolfBoot b uild with elf scatter loading with certc chain images verification using wolfHSM
tc3-elf-certs-wolfHSM:
    cp config/examples/aurix-tc375-elf-wolfHSM-certs.config .config
    # Build wolfBoot
    RLM_LICENSE=localhost@6004 \
        make \
            V=1 \
            GCC=1 \
            HT_TRICORE_PATH=/opt/hightec/gnutri_v4.9.4.1-11fcedf-lin64/ \
            WOLFHSM_PORT_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolfhsm-private/infineon/tc3xx/ \
            TC3_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolf-startup-tc3xx/tc3
    ## sign the update image with the cert chain
    #tools/keytools/sign --ecc256 test-app/image.elf test-dummy-ca/leaf-prvkey.der 2
    tools/keytools/sign --ecc256 --cert-chain test-dummy-ca/raw-chain.der test-app/image.elf test-dummy-ca/leaf-prvkey.der 2

# TC375 HSM core wolfBoot build
tc3-hsm:
    cp config/examples/aurix-tc375-hsm.config .config
    # build wolfBoot
    make \
        V=1 \
        GCC=1 \
        TC3_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolf-startup-tc3xx/tc3
    # sign the update image
    tools/keytools/sign --ecc256 test-app/image.bin wolfboot_signing_private_key.der 2

# TC375 HSM core wolfBoot build with server-local cert chain verification via wolfHSM
tc3-hsm-certs:
    # TODO
    #cp config/examples/aurix-tc375-hsm-wolfHSM-certs.config .config
    ## build wolfBoot
    #make \
    #    GCC=1 \
    #    WOLFHSM_PORT_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolfhsm-private/infineon/tc3xx/ \
    #    TC3_DIR=/home/brett/workspace/wolfssl/wolfssl-repos/wolf-startup-tc3xx/tc3
    ## sign the update image with the private key corresponding to the leaf cert
    #tools/keytools/sign --ecc256 test-app/image.elf test-dummy-ca/leaf-prvkey.der 2


# Utilities
clean:
    make clean
    make keysclean
    find ../wolf-startup-tc3xx/tc3/src -type f -name "*.o" -delete
