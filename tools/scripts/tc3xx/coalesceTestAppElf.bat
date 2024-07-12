@echo off
setlocal enabledelayedexpansion

REM Check if OBJCOPY is set in the environment, otherwise use the default path
if "%OBJCOPY%"=="" (
    set OBJCOPY=tricore-elf-objcopy.exe
)

REM Check if an ELF file is passed as an argument
if "%~1"=="" (
    echo Usage: %0 path_to_elf_file
    exit /b 1
)

REM Set the name of the input ELF file from the first command line argument
set INPUT_ELF=%~1

REM Generate a temporary file name for the modified and final ELF
set MODIFIED_ELF=%TEMP%\modified.elf
set FINAL_ELF=%TEMP%\final.elf

REM Derive the output binary filename from the input ELF filename
set OUTPUT_BIN=%~dpn1_coalesced.bin

REM Create temporary binary files for the sections
"%OBJCOPY%" -O binary --only-section=.start_tc0 "%INPUT_ELF%" start_tc0.bin
"%OBJCOPY%" -O binary --only-section=.start_tc1 "%INPUT_ELF%" start_tc1.bin
"%OBJCOPY%" -O binary --only-section=.start_tc2 "%INPUT_ELF%" start_tc2.bin

REM Update the cached sections with the extracted binaries
"%OBJCOPY%" --update-section .start_tc0_cached=start_tc0.bin ^
             --update-section .start_tc1_cached=start_tc1.bin ^
             --update-section .start_tc2_cached=start_tc2.bin ^
             "%INPUT_ELF%" "%MODIFIED_ELF%"

REM Remove the original sections from the modified ELF file
"%OBJCOPY%" --remove-section=.start_tc0 ^
             --remove-section=.start_tc1 ^
             --remove-section=.start_tc2 ^
             "%MODIFIED_ELF%" "%FINAL_ELF%"

REM Convert final ELF file to binary and name it appropriately
"%OBJCOPY%" -O binary "%FINAL_ELF%" "%OUTPUT_BIN%"

REM Clean up temporary files
del start_tc0.bin start_tc1.bin start_tc2.bin
del "%MODIFIED_ELF%"
del "%FINAL_ELF%"

