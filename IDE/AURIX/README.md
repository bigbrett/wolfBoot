# Overview


## Important notes
- In the UCBs, BMDHx.STAD must point to the wolfBoot entrypoint `0xA000_0000`. This is the default value of the TC375 and so need not be changed unless it has already been modified or you wish to rearrange the memory map.
- Because TC3xx PFLASH ECC prevents reading from erased flash, the `EXT_FLASH` option is used to redirect flash reads to a HAL API, where the flash pages requested to be read can be blank-checked by hardware before reading.
- TC3xx PFLASH is write-once (`NVM_FLASH_WRITEONCE`), however wolfBoot `NVM_FLASH_WRITEONCE` does not support `EXT_FLASH`. Therefore the write-once functionality is re-implemented in the `HAL` layer.

## Flash Partitioning

The TC3xx AURIX port of wolfBoot places all images in PFLASH, and uses both PFLASH0 and PFLASH1 banks. The wolfBoot executable code and the image swap sector are located in PFLASH0, with the remainder available for use. PFLASH1 is divided in half, with the first half holding the BOOT partition and the second half holding the UPDATE partion. User firmware images are directly executed in place from the BOOT partition in PFLASH1, and so must be linked to execute within this address space, with an offset of `IMAGE_HEADER_SIZE` to account for the wolfBoot image header.

```
+==========+
| PFLASH0  |
+==========+ <-- 0x8000_0000
| wolfBoot |        128K
+----------+ <-- 0x8002_0000
| SWAP     |        16K
+----------+ <-- 0x8002_4000
| Unused   |        ~2.86M
+----------+ <-- 0x8030_0000

+==========+
| PFLASH1  |
+==========+ <-- 0x8030_0000
| BOOT     |        1.5M
+----------+ <-- 0x8048_0000
| UPDATE   |        1.5M
+----------+ <-- 0x8060_0000
```

Please refer to the [wolfBoot](wolfBoot-tc3xx/Lcf_Gnu_Tricore_Tc.lsl) and [test-app](test-app/Lcf_Gnu_Tricore_Tc.lsl) linker scripts for the exact memory configuration.


## Building and running the wolfBoot demo

### Prerequisites

- A Windows 10 computer
- A WSL2 distro (tested on Ubuntu 22.04) with the `build-essential` package installed (`sudo apt install build-essential`)
- A cloned instance of wolfBoot (this repository)
- A TC375 AURIX Lite-Kit V2

### Build wolfBoot keytools

1. Open a WSL2 terminal and navigate to the top level `wolfBoot` directory
2. Compile the keytools by running `make keytools`

### Build wolfBoot

1. Install the AURIX IDE
2. Create a new workspace directory, if you do not already have a workspace you wish to use
3. Import the wolfBoot project
    1. Click "File" -> Open Projects From File System"
    2. Click "Directory" to select an import source, and choose the wolfBoot/IDE/AURIX/wolfBoot-tc3xx directory in the system file explorer
    3. Click "Finish" to import the project
4. Build the wolfBoot Project
    1. Right-click the wolfBoot-tc3xx project and choose "Set active project"
    2. Right-click the wolfBoot-tc3xx project, and from the "Build Configurations" -> "Set Active" menu, select either the "TriCore Debug (GCC)" or "TriCore Release (GCC)" build configuration
    3. Click the hammer icon to build the active project. This will compile wolfBoot.
5. Import the test-app project using the same procedure as in step (3), except using `wolfBoot/IDE/AURIX/test-app` as the directory
6. Build the test-app project using the same procedure as in step (4), except choosing the `test-app` eclipse project. Note that the build process contains a custom post-build step that converts the application `elf` file into a `.bin` file using `tricore-elf-objcopy`, which can then be signed by the wolfBoot key tools in the following step
7. Sign the generated test-app binary using the wolfBoot keytools
    1. Open a WSL terminal and navigate to `wolfBoot/tools/scripts/tc3xx`
    2. Run `./gen-tc3xx-signed-test-apps-debug.sh` or `gen-tc3xx-signed-test-apps-release.sh` to sign either the debug or release build, respectively. This creates the signed image files `test-app_v1_signed.bin` and `test-app_v2_signed.bin` in the test-app output build directory. The v1 image is the initial image that will be loaded to the `BOOT` partition, and the v2 image is the update image that will be loaded to the `UPDATE` partition.

### Load and run the wolfBoot demo

8. Load wolfBoot and the firmware application images to the tc3xx device using Trace32 and a Lauterbach probe
    1. Ensure the Lauterbach probe is connected to the debug port of the tc375 LiteKit
    2. Open Trace32 Power View for Tricore
    3. Open the SYStem menu and click "DETECT" to detect the tc375 device. Click "CONTINUE" in the pop-up window, and then choose "Set TC375xx" when the device is detected
    4. Click "File" -> "ChangeDir and Run Script" and choose the `wolfBoot/tools/scripts/tc3xx/wolfBoot-loadAll-$BUILD.cmm` script, where $BUILD should be either "debug" or "release" depending on your build type in (4) and (6).

wolfBoot and the demo applications are now loaded into flash, and core0 will be halted at the wolfBoot entry point (`core0_main()`).

9. Run the application by clicking "Go" to release the core. This will run wolfBoot which will eventually boot into the application in the `BOOT` partition. You should see LED2 on the board blink once per second.

10. Reset the application to trigger the firmware update. Click "System Down", "System Up", then "Go" to reset the tc3xx. If the device halts again at `core0_main`, click "Go" one more time to release the core. You should see LED2 turn on for ~5sec while wolfBoot swaps the images between `UPDATE` and `BOOT` partitions, then you should see LED2 blink rapidly (~3x/sec) indicating that the firmware update was successful and the new image has booted. Subsequent resets should continue to boot into to the new image.

To rerun the demo, simply rerun the loader script in Trace32 and repeat the above steps


