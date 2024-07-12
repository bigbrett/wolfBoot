#!/bin/bash

set -euxo pipefail

# Check if OBJCOPY is set in the environment, otherwise use the default path
OBJCOPY="${OBJCOPY:-/mnt/c/Infineon/AURIX-Studio-1.9.12/tools/Compilers/tricore-gcc11/bin/tricore-elf-objcopy.exe}"

# Check if an ELF file is passed as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 path_to_elf_file"
    exit 1
fi

# Set the name of the input ELF file from the first command line argument
INPUT_ELF="$1"

# Use PowerShell to create a temporary file name for the modified and final ELF
MODIFIED_ELF=$(powershell.exe -Command "[System.IO.Path]::GetTempFileName()" | tr -d '\r\n')
FINAL_ELF=$(powershell.exe -Command "[System.IO.Path]::GetTempFileName()" | tr -d '\r\n')

# Derive the output binary filename from the input ELF filename
OUTPUT_BIN="${INPUT_ELF%.*}_coalesced.bin"

echo "Input ELF file: $INPUT_ELF"
echo "Temporary modified ELF: $MODIFIED_ELF"
echo "Temporary final ELF: $FINAL_ELF"
echo "Output Binary: $OUTPUT_BIN"

# Create temporary binary files for the sections
$OBJCOPY -O binary --only-section=.start_tc0 "$INPUT_ELF" start_tc0.bin
$OBJCOPY -O binary --only-section=.start_tc1 "$INPUT_ELF" start_tc1.bin
$OBJCOPY -O binary --only-section=.start_tc2 "$INPUT_ELF" start_tc2.bin

# Update the cached sections with the extracted binaries
$OBJCOPY --update-section .start_tc0_cached=start_tc0.bin \
         --update-section .start_tc1_cached=start_tc1.bin \
         --update-section .start_tc2_cached=start_tc2.bin \
         "$INPUT_ELF" "$MODIFIED_ELF"

# Remove the original sections from the modified ELF file
$OBJCOPY --remove-section=.start_tc0 \
         --remove-section=.start_tc1 \
         --remove-section=.start_tc2 \
         "$MODIFIED_ELF" "$FINAL_ELF"

# Convert final ELF file to binary and name it appropriately
$OBJCOPY -O binary "$FINAL_ELF" "$OUTPUT_BIN"

# Clean up temporary files
rm start_tc0.bin start_tc1.bin start_tc2.bin

