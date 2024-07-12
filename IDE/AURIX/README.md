# Important notes (TODO document): 
- BMDHx.STAD must point to the wolfBoot entrypoint, so note that apps compiled for the BOOT sector (+256B offset) will not run on their own without wolfBoot loading them
- App binary must be patched/processed (see below)

# App image binary processing
- Because the app linker file places symbols at both cacheable and non-cacheable load addresses in PFLASH (`0x8030_000` and `0xA030_0100`), this results in an extremely large (~512 MiB) binary file if you run `objcopy -O binary test-app.elf test-app.bin`. To make the binary file contiguous when viewed from the POV of the keytools/signing and the loader (lauterbach tooling), we need to make a binary that relocates the 0xA03X_XXXX addresses to 0x803X_XXXX. We do this by declare dummy sections in the linker file at 0x803X_XXXX to hold the `.start_tcX` contents (named `.start_tcX_cached`), and then run a script that copies the non-cacheable sections into the cacheable sections and deletes the non-cacheable sections before generating the binary. This makes the binary image one contiguous blob in the 0x803X_XXXX range, but with the contents of the sections preserved.
