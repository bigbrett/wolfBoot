#!/bin/bash

set -euxo pipefail

# Set default value for OBJCOPY if not already set
OBJCOPY="/mnt/c/Infineon/AURIX-Studio-1.9.12/tools/Compilers/tricore-gcc11/bin/tricore-elf-objcopy.exe"

# Set the name of the input ELF file
INPUT_ELF="test-app.elf"

# Create temporary binary files for the sections
$OBJCOPY -O binary --only-section=.start_tc0 $INPUT_ELF start_tc0.bin
$OBJCOPY -O binary --only-section=.start_tc1 $INPUT_ELF start_tc1.bin
$OBJCOPY -O binary --only-section=.start_tc2 $INPUT_ELF start_tc2.bin

# Update the cached sections with the extracted binaries
$OBJCOPY --update-section .start_tc0_cached=start_tc0.bin \
         --update-section .start_tc1_cached=start_tc1.bin \
         --update-section .start_tc2_cached=start_tc2.bin \
         $INPUT_ELF modified.elf

# Remove the original sections from the modified ELF file
$OBJCOPY --remove-section=.start_tc0 \
         --remove-section=.start_tc1 \
         --remove-section=.start_tc2 \
         modified.elf final.elf

# Convert final elf file to binary
$OBJCOPY -O binary final.elf final.bin
du -h final.bin

# Clean up temporary files
rm start_tc0.bin start_tc1.bin start_tc2.bin

# Display the section headers of the final ELF file, showing only nonzero sections
readelf --sections final.elf | head -n 4 && readelf --sections final.elf | awk '/\[[ 0-9]+\]/{if ($6 != "000000") print}'

