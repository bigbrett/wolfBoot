/* wolfBoot CSRM bootloader linker script for AURIX TC4xx (CPU6).
 * Derived from the wolfHSM tc4xx server LSL (Lcf_Gcc_Tricore_TcCs.lsl).
 * Differences from the application script:
 *  - pfls6 is restricted to the 96KB bootloader region ending below the
 *    wolfBoot BOOT partition (0x84018000)
 *  - the interrupt vector table moves inside that region
 *  - the start stub links at the cached alias so the binary image is
 *    contiguous (the CS_BMHD STAD 0xA4000000 executes the same flash
 *    through the non-cached alias; the stub only performs absolute jumps)
 *  - a .ramcode output section (CSRM PSPR, copied by the SSW via the
 *    auto-generated __copy_table) holds the RAMFUNCTION flash drivers:
 *    wolfBoot and the partitions share the single CSRM flash bank, so
 *    nothing may fetch from it while a program/erase sequence runs
 * Processed by the wolfBoot Makefile into config/target.ld. */

/* Default linker script, for normal executables */
OUTPUT_FORMAT("elf32-tricore")
OUTPUT_ARCH(tricore)
ENTRY(_START6)

__TRICORE_DERIVATE_MEMORY_MAP__ = 0x390;

LCF_CSA6_SIZE = 8k;
/* 16k CSRM stack. Sized for the cert-manager verify frame
 * (root_cert[MAX_CERT_SIZE] = 4 KiB + DecodedCert ~4 KiB on the stack).
 * The CSRM-data-flash NVM backend (TCHSM_CFG_NVM_BACKEND_CSRM_DF) keeps
 * the 8 KiB RAMSIM array (tchsmFlashMem) out of DSPR6 .bss, leaving room.
 * .heap stays fixed 128k (load-bearing for ML-DSA-87 keygen). If .bss
 * ever pushes .heap back into .ustack, trim to 12-15k or apply a heap
 * lever below. */
LCF_USTACK6_SIZE = 16k;
LCF_ISTACK6_SIZE = 1k;

/* 128 KiB heap on a 240 KiB DSPR6.
 *
 * Current invariants (re-derive before changing):
 *   - HEAP must be ≥ ML-DSA-87 keygen working-set under
 *     WOLFSSL_MLDSA_DYNAMIC_KEYS + WOLFSSL_MLDSA_MAKE_KEY_SMALL_MEM.
 *     128 KiB clears it; 120 KiB does not (measured: MEMORY_E from
 *     wc_MlDsaKey_MakeKey).
 *   - KEYCACHE_BIG_COUNT must be ≥ 2 - SignDma's internal re-import
 *     path can't evict an uncommitted prior import; a single BIG
 *     slot deadlocks.
 *   - WOLFSSL_MLDSA_DYNAMIC_KEYS + the three MLDSA SMALL_MEM flags
 *     are what makes "BIG_COUNT=2 AND heap=128 KiB" fit together;
 *     dropping any of them re-opens the MEMORY_E failure.
 *
 * If static allocations grow further (new PQ flavor, COMM_DATA_LEN
 * bumped again, extra cache slot), the cheap levers in order are:
 *   1. WOLFSSL_MLDSA_SIGN_SMALL_MEM_PRECALC (one alloc per sign
 *      instead of per-iteration - may also fix the SIGN-DMA
 *      latency variance).
 *   2. KEYCACHE_COUNT 16 → 12  (-1.3 KiB static).
 *   3. USTACK6 16 → 12 KiB     (-4 KiB; DYNAMIC_KEYS made the
 *                               keygen frame small enough). */
LCF_HEAP_SIZE = 128k;

LCF_DSPR6_START = 0x10000000;
LCF_DSPR6_SIZE = 240k;

LCF_CSA6_OFFSET =    (LCF_DSPR6_SIZE - 1k - LCF_CSA6_SIZE);
LCF_ISTACK6_OFFSET = (LCF_CSA6_OFFSET - 256 - LCF_ISTACK6_SIZE);
LCF_USTACK6_OFFSET = (LCF_ISTACK6_OFFSET - 256 - LCF_USTACK6_SIZE);

/* NOTE: there is intentionally no LCF_HEAP6_OFFSET. The .heap section is
 * NOT placed top-anchored at a fixed offset; it grows bottom-up right
 * after .bss (see the `.heap` section below, which sets __HEAP / __HEAP_END
 * from the current location counter). A precomputed heap offset would have
 * been dead - the runtime heap top is __HEAP_END, and the ASSERT after the
 * .heap section checks it against the ustack low edge __USTACK6_END. */

LCF_INTVEC6_START = 0x84016000;

__INTTAB_CPU6 = LCF_INTVEC6_START;

LCF_TRAPVEC6_START = 0x84000100;

LCF_STARTPTR_CPU0 = 0x80000000;
LCF_STARTPTR_CPU1 = 0x80400100;
LCF_STARTPTR_CPU2 = 0x80800100;
LCF_STARTPTR_CPU3 = 0x80A00100;
LCF_STARTPTR_CPU4 = 0x80E00100;
LCF_STARTPTR_CPU5 = 0x81200100;
LCF_STARTPTR_CPU6 = 0x84000000;

LCF_STARTPTR_NC_CPU0 = 0xA0000000;
LCF_STARTPTR_NC_CPU1 = 0xA0400100;
LCF_STARTPTR_NC_CPU2 = 0xA0800100;
LCF_STARTPTR_NC_CPU3 = 0xA0A00100;
LCF_STARTPTR_NC_CPU4 = 0xA0E00100;
LCF_STARTPTR_NC_CPU5 = 0xA1200100;
LCF_STARTPTR_NC_CPU6 = 0xA4000000;

RESET = LCF_STARTPTR_NC_CPU6;

MEMORY
{
    dsram6_local (w!xp): org = 0xd0000000, len = 112k
    dsram6 (w!xp): org = 0x10000000, len = 240k
    psram6 (w!xp): org = 0x10100000, len = 64K
    
    psram_local (w!xp): org = 0xc0000000, len = 64K
    
    pfls6 (rx!p): org = 0x84000000, len = 0x18000
    pfls6_nc (rx!p): org = 0xa4000000, len = 0x18000
    
    ucb_cs (rx!p): org = 0xaec01800, len = 52K - 4K
    
}

/* map local memory address to a global address */
REGION_MAP( CPU6 , ORIGIN(dsram6_local), LENGTH(dsram6_local), ORIGIN(dsram6))

/* map cached and non cached addresses */
REGION_MIRROR("pfls6", "pfls6_nc")

REGION_ALIAS( default_ram , dsram6)
REGION_ALIAS( default_rom , pfls6)

/*Sections located at absolute fixed address*/
    /*Fixed memory Allocations for stack memory and CSA*/
    CORE_ID = CPU6 ;
    SECTIONS
    {
        CORE_SEC(.ustack) (LCF_DSPR6_START + LCF_USTACK6_OFFSET):
        { PROVIDE(__USTACK6_END = .);    . = . + LCF_USTACK6_SIZE;    PROVIDE(__USTACK6 = .); }
        
        CORE_SEC(.istack) (LCF_DSPR6_START + LCF_ISTACK6_OFFSET):
        { PROVIDE(__ISTACK6_END = .);    . = . + LCF_ISTACK6_SIZE;    PROVIDE(__ISTACK6 = .); }
        
        CORE_SEC(.csa) (LCF_DSPR6_START + LCF_CSA6_OFFSET):
        { PROVIDE(__CSA6 = .);    . = . + LCF_CSA6_SIZE;    PROVIDE(__CSA6_END = .); }
    }
    
    /*Fixed memory Allocations for _START*/
    CORE_ID = GLOBAL ;
    SECTIONS
    {
        /* Linked at the cached alias so the binary image is contiguous; the
         * BMHD STAD (0xA4000000) executes the same flash through the
         * non-cached alias, and the stub only performs absolute jumps. */
        .start_tc6 (LCF_STARTPTR_CPU6) : FLAGS(rxl) { KEEP (*(.start_cpu6)); } > pfls6
        /* wolfBoot's own image base (used by the self-update path) */
        PROVIDE(_start_text = LCF_STARTPTR_CPU6);
        PROVIDE(__IF_CONST = 0x80000020);
        PROVIDE(__START0 = LCF_STARTPTR_NC_CPU0);
        PROVIDE(__START1 = LCF_STARTPTR_NC_CPU1);
        PROVIDE(__START2 = LCF_STARTPTR_NC_CPU2);
        PROVIDE(__START3 = LCF_STARTPTR_NC_CPU3);
        PROVIDE(__START4 = LCF_STARTPTR_NC_CPU4);
        PROVIDE(__START5 = LCF_STARTPTR_NC_CPU5);
        PROVIDE(__START6 = LCF_STARTPTR_NC_CPU6);
        PROVIDE(__ENABLE_INDIVIDUAL_C_INIT_CPU6 = 1);
    }
    
    /*Fixed memory Allocations for Trap Vector Table*/
    CORE_ID = GLOBAL ;
    SECTIONS
    {
        .traptab_tc6 (LCF_TRAPVEC6_START) : { PROVIDE(__TRAPTAB_CPU6 = .); KEEP (*(.traptab_cpu6)); } > pfls6
    }
    
    /*Fixed memory Allocations for Interrupt Vector Table*/
    SECTIONS
    {
        /*CPU6 Interrupt Vector Table*/
        .inttab_tc6_000 (__INTTAB_CPU6 + 0x0000) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_0  )); }
        .inttab_tc6_001 (__INTTAB_CPU6 + 0x0020) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_1  )); }
        .inttab_tc6_002 (__INTTAB_CPU6 + 0x0040) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_2  )); }
        .inttab_tc6_003 (__INTTAB_CPU6 + 0x0060) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_3  )); }
        .inttab_tc6_004 (__INTTAB_CPU6 + 0x0080) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_4  )); }
        .inttab_tc6_005 (__INTTAB_CPU6 + 0x00A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_5  )); }
        .inttab_tc6_006 (__INTTAB_CPU6 + 0x00C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_6  )); }
        .inttab_tc6_007 (__INTTAB_CPU6 + 0x00E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_7  )); }
        .inttab_tc6_008 (__INTTAB_CPU6 + 0x0100) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_8  )); }
        .inttab_tc6_009 (__INTTAB_CPU6 + 0x0120) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_9  )); }
        .inttab_tc6_00A (__INTTAB_CPU6 + 0x0140) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_10 )); }
        .inttab_tc6_00B (__INTTAB_CPU6 + 0x0160) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_11 )); }
        .inttab_tc6_00C (__INTTAB_CPU6 + 0x0180) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_12 )); }
        .inttab_tc6_00D (__INTTAB_CPU6 + 0x01A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_13 )); }
        .inttab_tc6_00E (__INTTAB_CPU6 + 0x01C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_14 )); }
        .inttab_tc6_00F (__INTTAB_CPU6 + 0x01E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_15 )); }
        .inttab_tc6_010 (__INTTAB_CPU6 + 0x0200) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_16 )); }
        .inttab_tc6_011 (__INTTAB_CPU6 + 0x0220) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_17 )); }
        .inttab_tc6_012 (__INTTAB_CPU6 + 0x0240) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_18 )); }
        .inttab_tc6_013 (__INTTAB_CPU6 + 0x0260) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_19 )); }
        .inttab_tc6_014 (__INTTAB_CPU6 + 0x0280) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_20 )); }
        .inttab_tc6_015 (__INTTAB_CPU6 + 0x02A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_21 )); }
        .inttab_tc6_016 (__INTTAB_CPU6 + 0x02C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_22 )); }
        .inttab_tc6_017 (__INTTAB_CPU6 + 0x02E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_23 )); }
        .inttab_tc6_018 (__INTTAB_CPU6 + 0x0300) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_24 )); }
        .inttab_tc6_019 (__INTTAB_CPU6 + 0x0320) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_25 )); }
        .inttab_tc6_01A (__INTTAB_CPU6 + 0x0340) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_26 )); }
        .inttab_tc6_01B (__INTTAB_CPU6 + 0x0360) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_27 )); }
        .inttab_tc6_01C (__INTTAB_CPU6 + 0x0380) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_28 )); }
        .inttab_tc6_01D (__INTTAB_CPU6 + 0x03A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_29 )); }
        .inttab_tc6_01E (__INTTAB_CPU6 + 0x03C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_30 )); }
        .inttab_tc6_01F (__INTTAB_CPU6 + 0x03E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_31 )); }
        .inttab_tc6_020 (__INTTAB_CPU6 + 0x0400) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_32 )); }
        .inttab_tc6_021 (__INTTAB_CPU6 + 0x0420) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_33 )); }
        .inttab_tc6_022 (__INTTAB_CPU6 + 0x0440) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_34 )); }
        .inttab_tc6_023 (__INTTAB_CPU6 + 0x0460) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_35 )); }
        .inttab_tc6_024 (__INTTAB_CPU6 + 0x0480) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_36 )); }
        .inttab_tc6_025 (__INTTAB_CPU6 + 0x04A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_37 )); }
        .inttab_tc6_026 (__INTTAB_CPU6 + 0x04C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_38 )); }
        .inttab_tc6_027 (__INTTAB_CPU6 + 0x04E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_39 )); }
        .inttab_tc6_028 (__INTTAB_CPU6 + 0x0500) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_40 )); }
        .inttab_tc6_029 (__INTTAB_CPU6 + 0x0520) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_41 )); }
        .inttab_tc6_02A (__INTTAB_CPU6 + 0x0540) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_42 )); }
        .inttab_tc6_02B (__INTTAB_CPU6 + 0x0560) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_43 )); }
        .inttab_tc6_02C (__INTTAB_CPU6 + 0x0580) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_44 )); }
        .inttab_tc6_02D (__INTTAB_CPU6 + 0x05A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_45 )); }
        .inttab_tc6_02E (__INTTAB_CPU6 + 0x05C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_46 )); }
        .inttab_tc6_02F (__INTTAB_CPU6 + 0x05E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_47 )); }
        .inttab_tc6_030 (__INTTAB_CPU6 + 0x0600) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_48 )); }
        .inttab_tc6_031 (__INTTAB_CPU6 + 0x0620) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_49 )); }
        .inttab_tc6_032 (__INTTAB_CPU6 + 0x0640) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_50 )); }
        .inttab_tc6_033 (__INTTAB_CPU6 + 0x0660) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_51 )); }
        .inttab_tc6_034 (__INTTAB_CPU6 + 0x0680) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_52 )); }
        .inttab_tc6_035 (__INTTAB_CPU6 + 0x06A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_53 )); }
        .inttab_tc6_036 (__INTTAB_CPU6 + 0x06C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_54 )); }
        .inttab_tc6_037 (__INTTAB_CPU6 + 0x06E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_55 )); }
        .inttab_tc6_038 (__INTTAB_CPU6 + 0x0700) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_56 )); }
        .inttab_tc6_039 (__INTTAB_CPU6 + 0x0720) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_57 )); }
        .inttab_tc6_03A (__INTTAB_CPU6 + 0x0740) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_58 )); }
        .inttab_tc6_03B (__INTTAB_CPU6 + 0x0760) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_59 )); }
        .inttab_tc6_03C (__INTTAB_CPU6 + 0x0780) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_60 )); }
        .inttab_tc6_03D (__INTTAB_CPU6 + 0x07A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_61 )); }
        .inttab_tc6_03E (__INTTAB_CPU6 + 0x07C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_62 )); }
        .inttab_tc6_03F (__INTTAB_CPU6 + 0x07E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_63 )); }
        .inttab_tc6_040 (__INTTAB_CPU6 + 0x0800) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_64 )); }
        .inttab_tc6_041 (__INTTAB_CPU6 + 0x0820) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_65 )); }
        .inttab_tc6_042 (__INTTAB_CPU6 + 0x0840) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_66 )); }
        .inttab_tc6_043 (__INTTAB_CPU6 + 0x0860) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_67 )); }
        .inttab_tc6_044 (__INTTAB_CPU6 + 0x0880) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_68 )); }
        .inttab_tc6_045 (__INTTAB_CPU6 + 0x08A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_69 )); }
        .inttab_tc6_046 (__INTTAB_CPU6 + 0x08C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_70 )); }
        .inttab_tc6_047 (__INTTAB_CPU6 + 0x08E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_71 )); }
        .inttab_tc6_048 (__INTTAB_CPU6 + 0x0900) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_72 )); }
        .inttab_tc6_049 (__INTTAB_CPU6 + 0x0920) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_73 )); }
        .inttab_tc6_04A (__INTTAB_CPU6 + 0x0940) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_74 )); }
        .inttab_tc6_04B (__INTTAB_CPU6 + 0x0960) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_75 )); }
        .inttab_tc6_04C (__INTTAB_CPU6 + 0x0980) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_76 )); }
        .inttab_tc6_04D (__INTTAB_CPU6 + 0x09A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_77 )); }
        .inttab_tc6_04E (__INTTAB_CPU6 + 0x09C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_78 )); }
        .inttab_tc6_04F (__INTTAB_CPU6 + 0x09E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_79 )); }
        .inttab_tc6_050 (__INTTAB_CPU6 + 0x0A00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_80 )); }
        .inttab_tc6_051 (__INTTAB_CPU6 + 0x0A20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_81 )); }
        .inttab_tc6_052 (__INTTAB_CPU6 + 0x0A40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_82 )); }
        .inttab_tc6_053 (__INTTAB_CPU6 + 0x0A60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_83 )); }
        .inttab_tc6_054 (__INTTAB_CPU6 + 0x0A80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_84 )); }
        .inttab_tc6_055 (__INTTAB_CPU6 + 0x0AA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_85 )); }
        .inttab_tc6_056 (__INTTAB_CPU6 + 0x0AC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_86 )); }
        .inttab_tc6_057 (__INTTAB_CPU6 + 0x0AE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_87 )); }
        .inttab_tc6_058 (__INTTAB_CPU6 + 0x0B00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_88 )); }
        .inttab_tc6_059 (__INTTAB_CPU6 + 0x0B20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_89 )); }
        .inttab_tc6_05A (__INTTAB_CPU6 + 0x0B40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_90 )); }
        .inttab_tc6_05B (__INTTAB_CPU6 + 0x0B60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_91 )); }
        .inttab_tc6_05C (__INTTAB_CPU6 + 0x0B80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_92 )); }
        .inttab_tc6_05D (__INTTAB_CPU6 + 0x0BA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_93 )); }
        .inttab_tc6_05E (__INTTAB_CPU6 + 0x0BC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_94 )); }
        .inttab_tc6_05F (__INTTAB_CPU6 + 0x0BE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_95 )); }
        .inttab_tc6_060 (__INTTAB_CPU6 + 0x0C00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_96 )); }
        .inttab_tc6_061 (__INTTAB_CPU6 + 0x0C20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_97 )); }
        .inttab_tc6_062 (__INTTAB_CPU6 + 0x0C40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_98 )); }
        .inttab_tc6_063 (__INTTAB_CPU6 + 0x0C60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_99 )); }
        .inttab_tc6_064 (__INTTAB_CPU6 + 0x0C80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_100)); }
        .inttab_tc6_065 (__INTTAB_CPU6 + 0x0CA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_101)); }
        .inttab_tc6_066 (__INTTAB_CPU6 + 0x0CC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_102)); }
        .inttab_tc6_067 (__INTTAB_CPU6 + 0x0CE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_103)); }
        .inttab_tc6_068 (__INTTAB_CPU6 + 0x0D00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_104)); }
        .inttab_tc6_069 (__INTTAB_CPU6 + 0x0D20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_105)); }
        .inttab_tc6_06A (__INTTAB_CPU6 + 0x0D40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_106)); }
        .inttab_tc6_06B (__INTTAB_CPU6 + 0x0D60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_107)); }
        .inttab_tc6_06C (__INTTAB_CPU6 + 0x0D80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_108)); }
        .inttab_tc6_06D (__INTTAB_CPU6 + 0x0DA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_109)); }
        .inttab_tc6_06E (__INTTAB_CPU6 + 0x0DC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_110)); }
        .inttab_tc6_06F (__INTTAB_CPU6 + 0x0DE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_111)); }
        .inttab_tc6_070 (__INTTAB_CPU6 + 0x0E00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_112)); }
        .inttab_tc6_071 (__INTTAB_CPU6 + 0x0E20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_113)); }
        .inttab_tc6_072 (__INTTAB_CPU6 + 0x0E40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_114)); }
        .inttab_tc6_073 (__INTTAB_CPU6 + 0x0E60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_115)); }
        .inttab_tc6_074 (__INTTAB_CPU6 + 0x0E80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_116)); }
        .inttab_tc6_075 (__INTTAB_CPU6 + 0x0EA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_117)); }
        .inttab_tc6_076 (__INTTAB_CPU6 + 0x0EC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_118)); }
        .inttab_tc6_077 (__INTTAB_CPU6 + 0x0EE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_119)); }
        .inttab_tc6_078 (__INTTAB_CPU6 + 0x0F00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_120)); }
        .inttab_tc6_079 (__INTTAB_CPU6 + 0x0F20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_121)); }
        .inttab_tc6_07A (__INTTAB_CPU6 + 0x0F40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_122)); }
        .inttab_tc6_07B (__INTTAB_CPU6 + 0x0F60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_123)); }
        .inttab_tc6_07C (__INTTAB_CPU6 + 0x0F80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_124)); }
        .inttab_tc6_07D (__INTTAB_CPU6 + 0x0FA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_125)); }
        .inttab_tc6_07E (__INTTAB_CPU6 + 0x0FC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_126)); }
        .inttab_tc6_07F (__INTTAB_CPU6 + 0x0FE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_127)); }
        .inttab_tc6_080 (__INTTAB_CPU6 + 0x1000) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_128)); }
        .inttab_tc6_081 (__INTTAB_CPU6 + 0x1020) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_129)); }
        .inttab_tc6_082 (__INTTAB_CPU6 + 0x1040) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_130)); }
        .inttab_tc6_083 (__INTTAB_CPU6 + 0x1060) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_131)); }
        .inttab_tc6_084 (__INTTAB_CPU6 + 0x1080) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_132)); }
        .inttab_tc6_085 (__INTTAB_CPU6 + 0x10A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_133)); }
        .inttab_tc6_086 (__INTTAB_CPU6 + 0x10C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_134)); }
        .inttab_tc6_087 (__INTTAB_CPU6 + 0x10E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_135)); }
        .inttab_tc6_088 (__INTTAB_CPU6 + 0x1100) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_136)); }
        .inttab_tc6_089 (__INTTAB_CPU6 + 0x1120) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_137)); }
        .inttab_tc6_08A (__INTTAB_CPU6 + 0x1140) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_138)); }
        .inttab_tc6_08B (__INTTAB_CPU6 + 0x1160) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_139)); }
        .inttab_tc6_08C (__INTTAB_CPU6 + 0x1180) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_140)); }
        .inttab_tc6_08D (__INTTAB_CPU6 + 0x11A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_141)); }
        .inttab_tc6_08E (__INTTAB_CPU6 + 0x11C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_142)); }
        .inttab_tc6_08F (__INTTAB_CPU6 + 0x11E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_143)); }
        .inttab_tc6_090 (__INTTAB_CPU6 + 0x1200) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_144)); }
        .inttab_tc6_091 (__INTTAB_CPU6 + 0x1220) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_145)); }
        .inttab_tc6_092 (__INTTAB_CPU6 + 0x1240) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_146)); }
        .inttab_tc6_093 (__INTTAB_CPU6 + 0x1260) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_147)); }
        .inttab_tc6_094 (__INTTAB_CPU6 + 0x1280) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_148)); }
        .inttab_tc6_095 (__INTTAB_CPU6 + 0x12A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_149)); }
        .inttab_tc6_096 (__INTTAB_CPU6 + 0x12C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_150)); }
        .inttab_tc6_097 (__INTTAB_CPU6 + 0x12E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_151)); }
        .inttab_tc6_098 (__INTTAB_CPU6 + 0x1300) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_152)); }
        .inttab_tc6_099 (__INTTAB_CPU6 + 0x1320) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_153)); }
        .inttab_tc6_09A (__INTTAB_CPU6 + 0x1340) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_154)); }
        .inttab_tc6_09B (__INTTAB_CPU6 + 0x1360) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_155)); }
        .inttab_tc6_09C (__INTTAB_CPU6 + 0x1380) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_156)); }
        .inttab_tc6_09D (__INTTAB_CPU6 + 0x13A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_157)); }
        .inttab_tc6_09E (__INTTAB_CPU6 + 0x13C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_158)); }
        .inttab_tc6_09F (__INTTAB_CPU6 + 0x13E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_159)); }
        .inttab_tc6_0A0 (__INTTAB_CPU6 + 0x1400) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_160)); }
        .inttab_tc6_0A1 (__INTTAB_CPU6 + 0x1420) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_161)); }
        .inttab_tc6_0A2 (__INTTAB_CPU6 + 0x1440) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_162)); }
        .inttab_tc6_0A3 (__INTTAB_CPU6 + 0x1460) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_163)); }
        .inttab_tc6_0A4 (__INTTAB_CPU6 + 0x1480) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_164)); }
        .inttab_tc6_0A5 (__INTTAB_CPU6 + 0x14A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_165)); }
        .inttab_tc6_0A6 (__INTTAB_CPU6 + 0x14C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_166)); }
        .inttab_tc6_0A7 (__INTTAB_CPU6 + 0x14E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_167)); }
        .inttab_tc6_0A8 (__INTTAB_CPU6 + 0x1500) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_168)); }
        .inttab_tc6_0A9 (__INTTAB_CPU6 + 0x1520) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_169)); }
        .inttab_tc6_0AA (__INTTAB_CPU6 + 0x1540) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_170)); }
        .inttab_tc6_0AB (__INTTAB_CPU6 + 0x1560) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_171)); }
        .inttab_tc6_0AC (__INTTAB_CPU6 + 0x1580) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_172)); }
        .inttab_tc6_0AD (__INTTAB_CPU6 + 0x15A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_173)); }
        .inttab_tc6_0AE (__INTTAB_CPU6 + 0x15C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_174)); }
        .inttab_tc6_0AF (__INTTAB_CPU6 + 0x15E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_175)); }
        .inttab_tc6_0B0 (__INTTAB_CPU6 + 0x1600) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_176)); }
        .inttab_tc6_0B1 (__INTTAB_CPU6 + 0x1620) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_177)); }
        .inttab_tc6_0B2 (__INTTAB_CPU6 + 0x1640) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_178)); }
        .inttab_tc6_0B3 (__INTTAB_CPU6 + 0x1660) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_179)); }
        .inttab_tc6_0B4 (__INTTAB_CPU6 + 0x1680) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_180)); }
        .inttab_tc6_0B5 (__INTTAB_CPU6 + 0x16A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_181)); }
        .inttab_tc6_0B6 (__INTTAB_CPU6 + 0x16C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_182)); }
        .inttab_tc6_0B7 (__INTTAB_CPU6 + 0x16E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_183)); }
        .inttab_tc6_0B8 (__INTTAB_CPU6 + 0x1700) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_184)); }
        .inttab_tc6_0B9 (__INTTAB_CPU6 + 0x1720) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_185)); }
        .inttab_tc6_0BA (__INTTAB_CPU6 + 0x1740) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_186)); }
        .inttab_tc6_0BB (__INTTAB_CPU6 + 0x1760) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_187)); }
        .inttab_tc6_0BC (__INTTAB_CPU6 + 0x1780) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_188)); }
        .inttab_tc6_0BD (__INTTAB_CPU6 + 0x17A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_189)); }
        .inttab_tc6_0BE (__INTTAB_CPU6 + 0x17C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_190)); }
        .inttab_tc6_0BF (__INTTAB_CPU6 + 0x17E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_191)); }
        .inttab_tc6_0C0 (__INTTAB_CPU6 + 0x1800) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_192)); }
        .inttab_tc6_0C1 (__INTTAB_CPU6 + 0x1820) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_193)); }
        .inttab_tc6_0C2 (__INTTAB_CPU6 + 0x1840) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_194)); }
        .inttab_tc6_0C3 (__INTTAB_CPU6 + 0x1860) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_195)); }
        .inttab_tc6_0C4 (__INTTAB_CPU6 + 0x1880) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_196)); }
        .inttab_tc6_0C5 (__INTTAB_CPU6 + 0x18A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_197)); }
        .inttab_tc6_0C6 (__INTTAB_CPU6 + 0x18C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_198)); }
        .inttab_tc6_0C7 (__INTTAB_CPU6 + 0x18E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_199)); }
        .inttab_tc6_0C8 (__INTTAB_CPU6 + 0x1900) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_200)); }
        .inttab_tc6_0C9 (__INTTAB_CPU6 + 0x1920) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_201)); }
        .inttab_tc6_0CA (__INTTAB_CPU6 + 0x1940) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_202)); }
        .inttab_tc6_0CB (__INTTAB_CPU6 + 0x1960) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_203)); }
        .inttab_tc6_0CC (__INTTAB_CPU6 + 0x1980) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_204)); }
        .inttab_tc6_0CD (__INTTAB_CPU6 + 0x19A0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_205)); }
        .inttab_tc6_0CE (__INTTAB_CPU6 + 0x19C0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_206)); }
        .inttab_tc6_0CF (__INTTAB_CPU6 + 0x19E0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_207)); }
        .inttab_tc6_0D0 (__INTTAB_CPU6 + 0x1A00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_208)); }
        .inttab_tc6_0D1 (__INTTAB_CPU6 + 0x1A20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_209)); }
        .inttab_tc6_0D2 (__INTTAB_CPU6 + 0x1A40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_210)); }
        .inttab_tc6_0D3 (__INTTAB_CPU6 + 0x1A60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_211)); }
        .inttab_tc6_0D4 (__INTTAB_CPU6 + 0x1A80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_212)); }
        .inttab_tc6_0D5 (__INTTAB_CPU6 + 0x1AA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_213)); }
        .inttab_tc6_0D6 (__INTTAB_CPU6 + 0x1AC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_214)); }
        .inttab_tc6_0D7 (__INTTAB_CPU6 + 0x1AE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_215)); }
        .inttab_tc6_0D8 (__INTTAB_CPU6 + 0x1B00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_216)); }
        .inttab_tc6_0D9 (__INTTAB_CPU6 + 0x1B20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_217)); }
        .inttab_tc6_0DA (__INTTAB_CPU6 + 0x1B40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_218)); }
        .inttab_tc6_0DB (__INTTAB_CPU6 + 0x1B60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_219)); }
        .inttab_tc6_0DC (__INTTAB_CPU6 + 0x1B80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_220)); }
        .inttab_tc6_0DD (__INTTAB_CPU6 + 0x1BA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_221)); }
        .inttab_tc6_0DE (__INTTAB_CPU6 + 0x1BC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_222)); }
        .inttab_tc6_0DF (__INTTAB_CPU6 + 0x1BE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_223)); }
        .inttab_tc6_0E0 (__INTTAB_CPU6 + 0x1C00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_224)); }
        .inttab_tc6_0E1 (__INTTAB_CPU6 + 0x1C20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_225)); }
        .inttab_tc6_0E2 (__INTTAB_CPU6 + 0x1C40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_226)); }
        .inttab_tc6_0E3 (__INTTAB_CPU6 + 0x1C60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_227)); }
        .inttab_tc6_0E4 (__INTTAB_CPU6 + 0x1C80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_228)); }
        .inttab_tc6_0E5 (__INTTAB_CPU6 + 0x1CA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_229)); }
        .inttab_tc6_0E6 (__INTTAB_CPU6 + 0x1CC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_230)); }
        .inttab_tc6_0E7 (__INTTAB_CPU6 + 0x1CE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_231)); }
        .inttab_tc6_0E8 (__INTTAB_CPU6 + 0x1D00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_232)); }
        .inttab_tc6_0E9 (__INTTAB_CPU6 + 0x1D20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_233)); }
        .inttab_tc6_0EA (__INTTAB_CPU6 + 0x1D40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_234)); }
        .inttab_tc6_0EB (__INTTAB_CPU6 + 0x1D60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_235)); }
        .inttab_tc6_0EC (__INTTAB_CPU6 + 0x1D80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_236)); }
        .inttab_tc6_0ED (__INTTAB_CPU6 + 0x1DA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_237)); }
        .inttab_tc6_0EE (__INTTAB_CPU6 + 0x1DC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_238)); }
        .inttab_tc6_0EF (__INTTAB_CPU6 + 0x1DE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_239)); }
        .inttab_tc6_0F0 (__INTTAB_CPU6 + 0x1E00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_240)); }
        .inttab_tc6_0F1 (__INTTAB_CPU6 + 0x1E20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_241)); }
        .inttab_tc6_0F2 (__INTTAB_CPU6 + 0x1E40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_242)); }
        .inttab_tc6_0F3 (__INTTAB_CPU6 + 0x1E60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_243)); }
        .inttab_tc6_0F4 (__INTTAB_CPU6 + 0x1E80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_244)); }
        .inttab_tc6_0F5 (__INTTAB_CPU6 + 0x1EA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_245)); }
        .inttab_tc6_0F6 (__INTTAB_CPU6 + 0x1EC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_246)); }
        .inttab_tc6_0F7 (__INTTAB_CPU6 + 0x1EE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_247)); }
        .inttab_tc6_0F8 (__INTTAB_CPU6 + 0x1F00) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_248)); }
        .inttab_tc6_0F9 (__INTTAB_CPU6 + 0x1F20) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_249)); }
        .inttab_tc6_0FA (__INTTAB_CPU6 + 0x1F40) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_250)); }
        .inttab_tc6_0FB (__INTTAB_CPU6 + 0x1F60) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_251)); }
        .inttab_tc6_0FC (__INTTAB_CPU6 + 0x1F80) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_252)); }
        .inttab_tc6_0FD (__INTTAB_CPU6 + 0x1FA0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_253)); }
        .inttab_tc6_0FE (__INTTAB_CPU6 + 0x1FC0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_254)); }
        .inttab_tc6_0FF (__INTTAB_CPU6 + 0x1FE0) : { . = ALIGN(8) ;  KEEP (*(.intvec_tc6_255)); }
    }
	
	/*Fixed memory Allocations for BMHD CS*/
    CORE_ID = GLOBAL;
    SECTIONS
    {
        .bmhdcs_0_org (0xaec01800) : FLAGS(arl) { KEEP (*(.bmhdcs_0_orig)); } > ucb_cs
        .bmhdcs_1_org (0xaec02000) : FLAGS(arl) { KEEP (*(.bmhdcs_1_orig)); } > ucb_cs
        .bmhdcs_2_org (0xaec02800) : FLAGS(arl) { KEEP (*(.bmhdcs_2_orig)); } > ucb_cs
        .bmhdcs_3_org (0xaec03000) : FLAGS(arl) { KEEP (*(.bmhdcs_3_orig)); } > ucb_cs
        .csusercfg_0_org (0xaec07800) : FLAGS(arl) { KEEP (*(.csusercfg_0_orig)); } > ucb_cs
        .csusercfg_0_cpy (0xaec08000) : FLAGS(arl) { KEEP (*(.csusercfg_0_copy)); } > ucb_cs
    }	
    
    /*Near Abbsolute Addressable Data Sections*/
    CORE_ID = CPU6;
    SECTIONS
    {
        CORE_SEC(.zdata) (LCF_DSPR6_START): FLAGS(awzl)
        {
            *Ifx_Ssw_Tc6.* (.zdata)
            *Cpu6_Main.* (.zdata)
            *(.zdata_cpu6)
            *(.zdata_cpu6.*)
        } > dsram6 AT> pfls6
        
        CORE_SEC(.zbss) (NOLOAD): FLAGS(awz)
        {
            *Ifx_Ssw_Tc6.* (.zbss)
            *Cpu6_Main.* (.zbss)
            *(.zbss_cpu6)
            *(.zbss_cpu6.*)
        } > dsram6
    }
    
    /*Near Absolute Data, selectable by toolchain*/
    CORE_ID = GLOBAL;
    SECTIONS
    {    
        CORE_SEC(.zdata_powerOn) : FLAGS(awzl)
        {
            *(.zdata.dsprPowerOnInit.cpu6.32bit)
            *(.zdata.dsprPowerOnInit.cpu6.16bit)
            *(.zdata.dsprPowerOnInit.cpu6.8bit)
        } > default_ram AT> pfls6
        
        CORE_SEC(.zdata) : FLAGS(awzl)
        {
            *(.zdata.dsprInit.cpu6.32bit)
            *(.zdata.dsprInit.cpu6.16bit)
            *(.zdata.dsprInit.cpu6.8bit)
            *(.zdata)
            *(.zdata.*)
            *(.gnu.linkonce.z.*)
        } > default_ram AT> pfls6
        
        CORE_SEC(.zbss_powerOn) (NOLOAD) : FLAGS(awz)
        {
            *(.zbss.dsprPowerOnClear.cpu6.32bit)
            *(.zbss.dsprPowerOnClear.cpu6.16bit)
            *(.zbss.dsprPowerOnClear.cpu6.8bit)
        } > default_ram
        
        CORE_SEC(.zbss_noClear) (NOLOAD) : FLAGS(awz)
        {
            *(.zbss.dsprNoInit.cpu6.32bit)
            *(.zbss.dsprNoInit.cpu6.16bit)
            *(.zbss.dsprNoInit.cpu6.8bit)
        } > default_ram
        
        CORE_SEC(.zbss) (NOLOAD) : FLAGS(awz)
        {
            *(.zbss.dsprClearOnInit.cpu6.32bit)
            *(.zbss.dsprClearOnInit.cpu6.16bit)
            *(.zbss.dsprClearOnInit.cpu6.8bit)
            *(.zbss)
            *(.zbss.*)
            *(.bbss)
            *(.bbss.*)
            *(.gnu.linkonce.zb.*)
        } > default_ram
    }

    /*Near Absolute Const, selectable with patterns and user defined sections*/
    CORE_ID = GLOBAL;
    SECTIONS
    {
        CORE_SEC(.zrodata) : FLAGS(arzl)
        {
            *Ifx_Ssw_Tc?.* (.zrodata)
            *Cpu?_Main.* (.zrodata)
            *(.zrodata_cpu?)
        } > pfls6
    }
    
    /*Near Absolute Const, selectable by toolchain*/
    CORE_ID = GLOBAL;
    SECTIONS
    {
        CORE_SEC(.zrodata) : FLAGS(arzl)
        {
            *(.zrodata.const.cpu6.32bit)
            *(.zrodata.const.cpu6.16bit)
            *(.zrodata.const.cpu6.8bit)
            *(.zrodata.config.cpu6.32bit)
            *(.zrodata.config.cpu6.16bit)
            *(.zrodata.config.cpu6.8bit)
            *(.zrodata)
            *(.zrodata.*)
        } > pfls6
    }

/*Relative A0/A1/A8/A9 Addressable Sections*/
CORE_ID = GLOBAL;
SECTIONS
{
    /*Relative A0 Addressable Data, selectable with patterns and user defined sections*/
        /*Note: A0 addressable area is common, to make the functions callable in any CPU*/
    /*Relative A0 Addressable Data, selectable by toolchain*/
    CORE_SEC(.sdata) : FLAGS(awsl)
    {
        *(.sdata)
        *(.sdata.*)
    } > default_ram AT> pfls6
    CORE_SEC(.sbss) (NOLOAD): FLAGS(aws)
    {
        *(.sbss)
        *(.sbss.*)
    } > default_ram
    _SMALL_DATA_ = SIZEOF(CORE_SEC(.sdata)) ? ADDR(CORE_SEC(.sdata)) : (ADDR(CORE_SEC(.sdata)) & 0xF0000000) + 32k ;
    __A0_MEM = _SMALL_DATA_;
}

CORE_ID = GLOBAL;
SECTIONS
{
    /*Relative A1 Addressable Const, selectable with patterns and user defined sections*/
        /*Note: A1 addressable area is common, to make the functions callable in any CPU*/
    /*Relative A1 Addressable Const, selectable by toolchain*/
    CORE_SEC(.sdata2) : FLAGS(arsl)
    {
        *(.srodata)
        *(.srodata.*)
    } > default_rom
    _SMALL_DATA2_ = SIZEOF(CORE_SEC(.sdata2)) ? ADDR(CORE_SEC(.sdata2)) : (ADDR(CORE_SEC(.sdata2)) & 0xF0000000) + 32k ;
    __A1_MEM = _SMALL_DATA2_;
}

CORE_ID = GLOBAL;
SECTIONS
{
    /*Relative A9 Addressable Data, selectable with patterns and user defined sections*/
    CORE_SEC(.sdata4) :
    {
        *(.a9sdata)
        *(.a9sdata.*)    
    } > dsram6 AT> pfls6
    
    CORE_SEC(.sbss4) :
    {
        *(.a9sbss)
        *(.a9sbss.*)    
    } > dsram6
    
    _SMALL_DATA4_ = SIZEOF(CORE_SEC(.sdata4)) ? ADDR(CORE_SEC(.sdata4)) : (ADDR(CORE_SEC(.sdata4)) & 0xF0000000) + 32k ;
    __A9_MEM = _SMALL_DATA4_;

    /*Relative A8 Addressable Const, selectable with patterns and user defined sections*/
    CORE_SEC(.sdata3) : FLAGS(arsl)
    {
        *(.rodata_a8)
        *(.rodata_a8.*)
    } > default_rom
    
    _SMALL_DATA3_ = SIZEOF(CORE_SEC(.sdata3)) ? ADDR(CORE_SEC(.sdata3)) : (ADDR(CORE_SEC(.sdata3)) & 0xF0000000) + 32k ;
    __A8_MEM = _SMALL_DATA3_;
}

/*Far Data / Far Const Sections, selectable with patterns and user defined sections*/
/*Far Data Sections, selectable with patterns and user defined sections*/
CORE_ID = CPU6 ;
SECTIONS
{
    /*DSRAM5 Sections*/
    CORE_SEC(.data) : FLAGS(awl)
    {
        *Ifx_Ssw_Tc6.* (.data)
        *Cpu6_Main.* (.data)
        *(.data_cpu6)
        *(.data_cpu6.*)
    } > dsram6 AT> pfls6
    
    CORE_SEC(.bss) (NOLOAD): FLAGS(aw)
    {
        *Ifx_Ssw_Tc6.* (.bss)
        *Cpu6_Main.* (.bss)
        *(.bss_cpu6)
        *(.bss_cpu6.*)
    } > dsram6
    
    /*DLMU5 Sections*/
    CORE_SEC(.lmudata) : FLAGS(awl)
    {
        *(.lmudata_cpu6)
        *(.lmudata_cpu6.*)
    } > dsram6 AT> pfls6
    
    CORE_SEC(.lmubss) : FLAGS(aw)
    {
        *(.lmubss_cpu6)
        *(.lmubss_cpu6.*)
    } > dsram6
}

/*Far Data Sections, selectable by toolchain*/
CORE_ID = GLOBAL;
SECTIONS
{
    CORE_SEC(.bss_noClear) (NOLOAD) : FLAGS(aw)
    {
        *(.bss.farDsprNoInit.cpu6.32bit)
        *(.bss.farDsprNoInit.cpu6.16bit)
        *(.bss.farDsprNoInit.cpu6.8bit)
    } > default_ram
    
    CORE_SEC(.data) : FLAGS(awl)
    {
        *(.data.farDsprInit.cpu6.32bit)
        *(.data.farDsprInit.cpu6.16bit)
        *(.data.farDsprInit.cpu6.8bit)
        *(.data)
        *(.data.*)
    *(.gnu.linkonce.d.*)
    } > default_ram AT> pfls6
    
    CORE_SEC(.bss) (NOLOAD) : FLAGS(aw)
    {
        *(.bss.farDsprClearOnInit.cpu6.32bit)
        *(.bss.farDsprClearOnInit.cpu6.16bit)
        *(.bss.farDsprClearOnInit.cpu6.8bit)
        *(.bss)
        *(.bss.*)
        *(.gnu.linkonce.b.*)
    } > default_ram
    
    .heap  : FLAGS(aw)
    {
    . = ALIGN(4);
    __HEAP = .;
    . += LCF_HEAP_SIZE;
    __HEAP_END = .;
    } > default_ram

    /* DSPR6 layout guard: the bottom-up .heap (ending at __HEAP_END) must
     * not overrun the user stack, whose low edge is __USTACK6_END (placed
     * top-anchored at LCF_DSPR6_START + LCF_USTACK6_OFFSET). If .bss + .heap
     * ever grow past the stack the link fails here instead of producing an
     * image that corrupts the stack at runtime. */
    ASSERT(__HEAP_END <= __USTACK6_END,
           "DSPR6 .heap overruns .ustack")

    CORE_SEC(.lmudata) : FLAGS(awl)
    {
        *(.lmudata)
        *(.lmudata.*)
    } > dsram6 AT> pfls6
    
    CORE_SEC(.lmubss) : FLAGS(aw)
    {
        *(.lmubss)
        *(.lmubss.*)
    } > dsram6
}
/*Far Const Sections, selectable with patterns and user defined sections*/
CORE_ID = CPU6;
SECTIONS
{
    CORE_SEC(.rodata) : FLAGS(arl)
    {
        *Ifx_Ssw_Tc6.* (.rodata)
        *Cpu6_Main.* (.rodata)
        *(.rodata_cpu6)
        *(.rodata_cpu6.*)
    } > pfls6
}

/*Far Const Sections, selectable by toolchain*/
CORE_ID = GLOBAL;
SECTIONS
{
    CORE_SEC(.rodata) : FLAGS(arl)
    {
        *(.rodata.farConst.cpu6.32bit)
        *(.rodata.farConst.cpu6.16bit)
        *(.rodata.farConst.cpu6.8bit)
        *(.rodata)
        *(.rodata.*)
    *(.gnu.linkonce.r.*)
    /*
     * Create the clear and copy tables that tell the startup code
     * which memory areas to clear and to copy, respectively.
     */
    . = ALIGN(4) ;
    PROVIDE(__clear_table = .);
    LONG(0 + ADDR(.CPU6.zbss));       LONG(SIZEOF(.CPU6.zbss));
    LONG(0 + ADDR(.CPU6.bss));        LONG(SIZEOF(.CPU6.bss));
    LONG(0 + ADDR(.CPU6.lmubss));     LONG(SIZEOF(.CPU6.lmubss));
    LONG(0 + ADDR(.zbss));            LONG(SIZEOF(.zbss));
    LONG(0 + ADDR(.sbss));            LONG(SIZEOF(.sbss));
    LONG(0 + ADDR(.bss));             LONG(SIZEOF(.bss));
    LONG(0 + ADDR(.lmubss));          LONG(SIZEOF(.lmubss));
    LONG(0 + ADDR(.sbss4));           LONG(SIZEOF(.sbss4));
    LONG(-1);                         LONG(-1);
    PROVIDE(__clear_table_powerOn = .);
    LONG(0 + ADDR(.zbss_powerOn));    LONG(SIZEOF(.zbss_powerOn));
    LONG(-1);                         LONG(-1);
    PROVIDE(__copy_table = .);
    LONG(LOADADDR(.CPU6.zdata));      LONG(0 + ADDR(.CPU6.zdata));      LONG(SIZEOF(.CPU6.zdata));
    LONG(LOADADDR(.CPU6.data));       LONG(0 + ADDR(.CPU6.data));       LONG(SIZEOF(.CPU6.data));
    LONG(LOADADDR(.CPU6.lmudata));    LONG(0 + ADDR(.CPU6.lmudata));    LONG(SIZEOF(.CPU6.lmudata));
    LONG(LOADADDR(.zdata));           LONG(0 + ADDR(.zdata));           LONG(SIZEOF(.zdata));
    LONG(LOADADDR(.sdata));           LONG(0 + ADDR(.sdata));           LONG(SIZEOF(.sdata));
    LONG(LOADADDR(.data));            LONG(0 + ADDR(.data));            LONG(SIZEOF(.data));
    LONG(LOADADDR(.lmudata));         LONG(0 + ADDR(.lmudata));         LONG(SIZEOF(.lmudata));
    LONG(LOADADDR(.sdata4));          LONG(0 + ADDR(.sdata4));          LONG(SIZEOF(.sdata4));
    LONG(LOADADDR(.CPU6.psram_text)); LONG(0 + ADDR(.CPU6.psram_text)); LONG(SIZEOF(.CPU6.psram_text));
    LONG(-1);                         LONG(-1);                         LONG(-1);
    PROVIDE(__copy_table_powerOn = .) ;
    LONG(LOADADDR(.zdata_powerOn));   LONG(0 + ADDR(.zdata_powerOn));   LONG(SIZEOF(.zdata_powerOn));
    LONG(-1);                         LONG(-1);                         LONG(-1);
    . = ALIGN(8);
    } > default_rom
}

/*Code selections*/
/*Code Sections, selectable with patterns and user defined sections*/
CORE_ID = CPU6;
SECTIONS
{
    CORE_SEC(.text) : FLAGS(axl)
    {
        . = ALIGN(2);
        *Ifx_Ssw_Tc6.*(.text)
        *Cpu6_Main.*(.text)
        *Ifx_Ssw_Tc6.*(.text.*)
        *Cpu6_Main.*(.text.*)
        *(.text_cpu6)
        *(.text_cpu6.*)
    } > pfls6
    
    /*
     * Code executed before calling main extra section for C++ constructor init
     *  -------------------------Start-----------------------------------------
     */
    .init :
    {
        PROVIDE(__init_start = .);
        KEEP(*(.init))
        KEEP(*(.init*))
        PROVIDE(__init_end = .);
        . = ALIGN(8);
    
    } > pfls6
    
    .fini :
    {
        PROVIDE(__fini_start = .);
        KEEP(*(.fini))
        KEEP(*(.fini*))
        PROVIDE(__fini_end = .);
        . = ALIGN(8);
    } > pfls6
    
    /*
     * Code executed before calling main extra section for C++ constructor init
     *  -------------------------End-----------------------------------------
     */
    CORE_SEC(.psram_text)  : FLAGS(awx)
    {
        . = ALIGN(2);
        *(.psram_text_cpu6)
        *(.psram_text_cpu6.*)
        *(.cpu6_psram)
        *(.cpu6_psram.*)
        /* wolfBoot RAMFUNCTION flash drivers: run from PSPR so no fetch
         * hits the CSRM flash bank with a program/erase sequence in
         * flight. Copied at startup via the auto-generated __copy_table. */
        *(.ramcode)
        *(.ramcode.*)
    } > psram6 AT> pfls6
}

/*Code Sections, selectable by toolchain*/
CORE_ID = GLOBAL;
SECTIONS
{
    CORE_SEC(.text) : FLAGS(axl)
    {
        *(.text.fast.pfls.cpu6)
        *(.text.slow.pfls.cpu6)
        *(.text.5ms.pfls.cpu6)
        *(.text.10ms.pfls.cpu6)
        *(.text.callout.pfls.cpu6)
        *(.text)
        *(.text.*)
        *(.gnu.linkonce.t.*)
        *(.gnu.warning)        /* .gnu.warning sections are handled specially by elf32.em. */
        . = ALIGN(4);
    } > default_rom

    /*
     * C++ exception handling tables.  NOTE: gcc emits .eh_frame
     * sections when compiling C sources with debugging enabled (-g).
     * If you can be sure that your final application consists
     * exclusively of C objects (i.e., no C++ objects), you may use
     * the -R option of the "strip" and "objcopy" utilities to remove
     * the .eh_frame section from the executable.
     */
      .eh_frame : ALIGN(8)
	  {
			__eh_frame_start = .;
			KEEP(*(.eh_frame))
			__eh_frame_end = .;
			. = ALIGN(8);
      } > default_rom

    /*
     * Constructors and destructors.
     */
    .ctors : FLAGS(ar)
    {
        __CTOR_LIST__ = . ;
        LONG((__CTOR_END__ - __CTOR_LIST__) / 4 - 2);
        /*
         * Code executed before calling main extra section for C++ constructor init
         *  -------------------------Start-----------------------------------------
         */
        KEEP (*crtbegin.o(.ctors))
        KEEP (*(EXCLUDE_FILE (*crtend.o ) .ctors))
        KEEP (*(SORT(.ctors.*)))
        KEEP (*(.ctors))
        /*
         * Code executed before calling main extra section for C++ constructor init
         *  -------------------------End-----------------------------------------
         */
        LONG(0) ;
        __CTOR_END__ = . ;
        . = ALIGN(8);
    } > default_rom
    .dtors : FLAGS(ar)
    {
        __DTOR_LIST__ = . ;
        LONG((__DTOR_END__ - __DTOR_LIST__) / 4 - 2);
        /*
         * Code executed before calling main extra section for C++ distructor init
         *  -------------------------Start-----------------------------------------
         */
        KEEP (*crtbegin.o(.dtors))
        KEEP (*(EXCLUDE_FILE (*crtend.o ) .dtors))
        KEEP (*(SORT(.dtors.*)))
        KEEP (*(.dtors))
        /*
         * Code executed before calling main extra section for C++ distructor init
         *  -------------------------End-----------------------------------------
         */
        LONG(0) ;
        __DTOR_END__ = . ;
        . = ALIGN(8);
    } > default_rom
    /*
     * DWARF debug sections.
     * Symbols in the DWARF debugging sections are relative to the
     * beginning of the section, so we begin them at 0.
     */
    /*
     * DWARF 1
     */
    .comment         0 : { *(.comment) }
    .debug           0 : { *(.debug) }
    .line            0 : { *(.line) }
    /*
     * GNU DWARF 1 extensions
     */
    .debug_srcinfo   0 : { *(.debug_srcinfo) }
    .debug_sfnames   0 : { *(.debug_sfnames) }
    /*
     * DWARF 1.1 and DWARF 2
     */
    .debug_aranges   0 : { *(.debug_aranges) }
    .debug_pubnames  0 : { *(.debug_pubnames) }
    /*
     * DWARF 2
     */
    .debug_info      0 : { *(.debug_info) }
    .debug_abbrev    0 : { *(.debug_abbrev) }
    .debug_line      0 : { *(.debug_line) }
    .debug_frame     0 : { *(.debug_frame) }
    .debug_str       0 : { *(.debug_str) }
    .debug_loc       0 : { *(.debug_loc) }
    .debug_macinfo   0 : { *(.debug_macinfo) }
    .debug_ranges    0 : { *(.debug_ranges) }
    /*
     * SGI/MIPS DWARF 2 extensions
     */
    .debug_weaknames 0 : { *(.debug_weaknames) }
    .debug_funcnames 0 : { *(.debug_funcnames) }
    .debug_typenames 0 : { *(.debug_typenames) }
    .debug_varnames  0 : { *(.debug_varnames) }
    /*
     * Optional sections that may only appear when relocating.
     */
    /*
     * Optional sections that may appear regardless of relocating.
     */
    .version_info    0 : { *(.version_info) }
    .boffs           0 : { KEEP (*(.boffs)) }
}

/* Shared wolfHSM IPC buffer symbols.
 *
 * Physical memory is owned and reserved by the client image (CPU0's
 * DSPR0 - see tchsm-client/Lcf_Gcc_Tricore_Tc.lsl `.hsmShmCoreBufs`
 * NOLOAD section). The server doesn't allocate anything here; it just
 * needs the same symbol *values* so port/tchsm_common.h's externs
 * resolve to the same physical addresses on both sides. Fixed
 * assignment is the most direct expression of that contract - if you
 * change the address on either side, change it here too. */
_hsmShmCore0CommBufStart = 0x70018100;   /* APP0 - CPU0 DSPR0 */
_hsmShmCore0CommBufEnd   = 0x70020000;
_hsmShmCore1CommBufStart = 0x60018100;   /* APP1 - CPU1 DSPR1 (global alias) */
_hsmShmCore1CommBufEnd   = 0x60020000;

/* Per-host-core boot/handshake status regions (tchsm_CoreStatus), 256 B
 * each, at the FRONT of each core's cross-core window (0x..018000) - the
 * range proven cross-core-writable; reserved by the client image. The
 * server reads/writes them (HSM-ready stamp) via the same symbol values. */
_hsmStatusCore0Start = 0x70018000;       /* CPU0 DSPR0 */
_hsmStatusCore0End   = 0x70018100;
_hsmStatusCore1Start = 0x60018000;       /* CPU1 DSPR1 (global alias) */
_hsmStatusCore1End   = 0x60018100;

/* CSRM-owned data-flash NVM region for wolfHSM persistence.
 *
 * 64 KiB at 0xAE800000 carved out of the 1 MiB CSRM DF bank (logical
 * sectors 0..31 of 2 KiB each - see IfxFlashCsrm_cfg_TC4Dx.h). The
 * region is reachable only via the CSRM cmd interface (0xF80C0000)
 * driven by port/server/tchsm_csrm_flash.c.
 *
 * These are plain absolute-address symbols, NOT a NOLOAD reservation:
 * port/server/config/tchsm_server_cfg.c reads them as base/end of the
 * flash driver's region. The only thing currently preventing the
 * linker from placing code/data at 0xAE8xxxxx is the absence of a
 * MEMORY entry covering this address range. If you ever add a MEMORY
 * region overlapping it (e.g. to allow reads via the linker rather
 * than only through the cmd interface), wrap these symbols in a real
 * NOLOAD SECTION first to keep the linker out of the NVM region.
 *
 * If you change the size or base, also update tchsm_CsrmFlash_Init's
 * BKALLOC check (bit 17 == DCsrm - TC4Dx-specific). */
_csrmNvmStart = 0xAE800000;
_csrmNvmEnd   = 0xAE810000;

/* wolfHSM DMA window - see client linker comment for the design.
 *
 * The host image reserves the LMU non-cached window with a NOLOAD section
 * and opens LMU APU for CSRM over [_clientDmaWindowStart, _clientDmaWindowEnd)
 * at boot (port/client/tchsm_lmu_apu.c). The server image only needs the
 * window extents visible to port/server/tchsm_dma_cb.c, which validates the
 * absolute client address (LMU window OR a host DSPR range) and dereferences
 * it directly. There is no bounce pool. */
_clientDmaWindowStart = 0xB0410000;
_clientDmaWindowEnd   = 0xB0480000;

