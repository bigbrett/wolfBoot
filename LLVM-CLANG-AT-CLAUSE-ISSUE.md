# LLVM/Clang Linker Issue with AT Clause on AURIX TC3xx Platform

## Executive Summary

When building the same wolfBoot test application for AURIX TC3xx using HighTec GCC vs HighTec Clang, the Clang-generated ELF file produces a >2GB binary when processed with `objcopy -O binary`, while the GCC version produces a correctly sized binary. Analysis reveals that LLVM's LLD linker is not properly handling the `AT` clause in linker scripts, causing all program segments to have identical Virtual Memory Address (VMA) and Load Memory Address (LMA), rather than the intended separation where data sections should be loaded from flash but executed from RAM.

## Problem Description

The linker script uses the `AT` clause to specify that certain sections (particularly CPU-specific data sections and stacks) should be:
- **Virtual Address (VMA)**: Located in RAM regions (0x10000000-0x70000000 range)  
- **Load Address (LMA)**: Stored in flash (0x80300000+ range)

This is a standard pattern where initialization data is stored in non-volatile flash but copied to RAM at runtime for execution.

## Evidence from ELF File Analysis

### Program Headers Comparison

**GCC Build (`test-app/image-gcc.elf.old`):**
```
Program Headers:
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  LOAD           0x000240 0x10000000 0x10000000 0x00000 0x04000 RW  0x40
  LOAD           0x000588 0x10004000 0x80300388 0x00000 0x01000 RW  0x1
  LOAD           0x000588 0x70004000 0x80300388 0x00000 0x01000 RW  0x1
```

**Clang Build (`test-app/image.elf`):**
```
Program Headers:
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  LOAD           0x000800 0x10000000 0x10000000 0x00000 0x04000 RW  0x40
  LOAD           0x000800 0x10004000 0x10004000 0x00000 0x01000 RW  0x1
  LOAD           0x000800 0x70004000 0x70004000 0x00000 0x01000 RW  0x1
```

**Key Difference**: In the GCC build, segments for CPU stacks show `VirtAddr ≠ PhysAddr` (e.g., VirtAddr=0x10004000, PhysAddr=0x80300388), indicating proper `AT` clause handling. In the Clang build, `VirtAddr = PhysAddr` for all segments, indicating the `AT` clause is being ignored.

### Section Headers Analysis

**GCC Sections (key examples from `readelf -S`):**
```
[16] .CPU5.stack       NOBITS          10004000 000588 001000 00  WA  0   0  1
[17] .CPU0.clear_sec   PROGBITS        80300388 000588 000028 00  WA  0   0  1
```

**Clang Sections (key examples from `readelf -S`):**
```
[40] .CPU5.stack       NOBITS          10004000 000800 001000 00  WA  0   0  1
[41] .CPU0.clear_sec   PROGBITS        803003c8 000800 000028 00  WA  0   0  1
```

Both show similar section addresses, but the critical difference is in how these are mapped to program segments (as shown in the program headers above).

## Evidence from Map File Analysis

### Memory Layout in Map Files

**GCC Map File (`test-app/image-gcc.map.old`):**
The memory configuration shows proper usage:
```
Name             Origin             Length             Used               Free
dspr_cpu0        0x0000000070000000 0x000000000003c000 0x0000000000005000 0x0000000000037000
dspr_cpu5        0x0000000010000000 0x000000000003c000 0x0000000000005000 0x0000000000037000
```

**Clang Map File (`test-app/image.map`):**
Shows the same memory regions being used:
```
70000000 70000000     4000    64 .CPU0.csa
10000000 10000000     4000    64 .CPU5.csa
```

However, the critical difference is in how the linker assigns physical addresses to these sections.

### Section Assignment Evidence

**GCC Map File - Proper AT Clause Handling:**
```
80300388 80300388       28     1 .CPU0.clear_sec
803003b0 803003b0       48     1 .CPU0.copy_sec
```

**Clang Map File - Same LMA Assignment:**
```
803003c8 803003c8       28     1 .CPU0.clear_sec  
803003f0 803003f0       48     1 .CPU0.copy_sec
```

The sections themselves are placed correctly in both cases, but the program segment mapping differs.

## Root Cause: objcopy with --gap-fill Option

The issue occurs specifically when using `objcopy -O binary --gap-fill=0xFF` (or similar gap-fill options). This option fills all gaps between segments with the specified byte value, creating a continuous binary image from the lowest to highest physical address.

**Analysis of LOAD segments with FileSiz > 0 (actual file content):**

**GCC Case:**
- All segments with file content are in flash region (0x80300100 to ~0x80300600)
- Gap-fill creates: ~1KB binary
- Command: `tricore-objcopy -O binary --gap-fill=0xFF gcc.elf gcc.bin` → 1,236 bytes

**Clang Case:**  
- File content segments span from 0x80300100 to 0x803003c8 (flash)
- BUT program headers incorrectly include segments spanning 0x10000000 to 0xb0000000
- Gap-fill creates: >2.5GB binary (0x10000000 to 0xb0000000 range)
- Command: `tricore-objcopy -O binary --gap-fill=0xFF clang.elf clang.bin` → 2,684,354,560 bytes

**The core issue:** Even though NOBITS sections have FileSiz=0, they still create LOAD program headers that objcopy considers when using --gap-fill, because Clang's linker sets VirtAddr=PhysAddr for all segments instead of properly using the AT clause to separate load addresses.

## Linker Script Context

The issue stems from the linker script's use of the `AT` clause in `/wolf-startup-tc3xx/tc3/tc3/tc3tc_sections.ld`:

```ld
.CPU0.data : {
    *(SORT_BY_ALIGNMENT(.CPU0.data*))
} > DATA_DSPR_CPU0_ AT > RODATA_CPU0_

.CPU0.stack (NOLOAD) : {
    . = ALIGN(8);
    __STACK_BASE_CPU0_ = .;
    . += STACK_SIZE;
} > DATA_DSPR_CPU0_
```

The `AT > RODATA_CPU0_` clause should cause the linker to:
1. Place sections virtually in DATA_DSPR_CPU0_ (RAM at 0x70000000)
2. Store them physically in RODATA_CPU0_ (flash at 0x80300000+)

## Verification Steps for HighTec

To reproduce and verify this issue:

1. **Compare program headers:**
   ```bash
   readelf -l test-app/image-gcc.elf.old
   readelf -l test-app/image.elf
   ```
   Look for VirtAddr ≠ PhysAddr in GCC vs VirtAddr = PhysAddr in Clang

2. **Check binary sizes with gap-fill (this demonstrates the issue):**
   ```bash
   tricore-objcopy -O binary --gap-fill=0xFF test-app/image-gcc.elf.old gcc.bin
   tricore-objcopy -O binary --gap-fill=0xFF test-app/image.elf clang.bin
   ls -la *.bin
   ```
   Expected: GCC produces ~1KB, Clang produces >2GB

3. **Examine segment-to-section mapping:**
   ```bash
   readelf -l test-app/image-gcc.elf.old | grep -A20 "Section to Segment"
   readelf -l test-app/image.elf | grep -A20 "Section to Segment"  
   ```

This issue appears to be a fundamental difference in how LLVM's LLD linker interprets the `AT` clause compared to GNU LD, specifically affecting embedded applications that rely on load-time address translation for RAM-resident sections.
