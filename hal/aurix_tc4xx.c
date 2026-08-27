/* aurix_tc4xx.c
 *
 * Copyright (C) 2014-2026 wolfSSL Inc.
 *
 * This file is part of wolfBoot.
 *
 * wolfBoot is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * wolfBoot is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with wolfBoot.  If not, see <http://www.gnu.org/licenses/>.
 */

/* wolfBoot HAL for the Infineon AURIX TC4xx. Two flavors share this
 * file, selected by WOLFBOOT_AURIX_TC4XX_CSRM:
 *
 * Host domain (default, TriCore CPU0): flash programming drives the host
 * NVM command interface (HCI) at 0xF8080000 directly, following the same
 * command/polling discipline as the CSRM data-flash driver in the
 * wolfHSM TC4xx port (port/server/tchsm_csrm_flash.c), adapted for host
 * PFLASH geometry: 32-byte pages, 512-byte bursts, 16KB logical sectors.
 * The boot firmware evaluates RTC_BMHD0 (STAD 0xA0000000) and starts
 * CPU0 in wolfBoot's iLLD startup software (PLL, watchdogs left running,
 * CPU1..5 held in reset). After image verification, hal_prepare_boot()
 * switches the clock tree back to the backup clock (IfxClock_init cannot
 * re-run while the system runs from the PLL) and do_boot() jumps to the
 * application's startup code, which re-runs the full iLLD SSW from a
 * near-reset clock state and releases CPU1.
 *
 * CSRM (WOLFBOOT_AURIX_TC4XX_CSRM, TriCore CPU6): same command/polling
 * discipline against the CSRM command interface (CSCI) at 0xF80C0000 for
 * the CSRM's own 1MB PFLASH bank (32-byte pages, 16KB logical sectors,
 * no documented burst command - pages only). The boot firmware evaluates
 * CS_BMHD0 (STAD 0xA4000000) and starts CPU6 in the CSRM startup
 * software (Ifx_Ssw_Tc6.c), which has no hypervisor-exit or PLL step and
 * is warm-start safe, so no clock restore is needed before do_boot() and
 * the chain-loaded application re-runs it unmodified. wolfBoot and the
 * partitions share the single CSRM flash bank: everything that executes
 * while a program/erase sequence is in flight runs from CSRM PSPR
 * (.ramcode), and no interrupts are enabled.
 *
 * Commands take the non-cached (0xAxxxxxxx) address alias in both
 * flavors. Erased PFLASH cannot be read (uncorrectable ECC), so every
 * read is preceded by a hardware erase-verify and erased regions are
 * synthesized as FILL_BYTE. */

#include <stdint.h>
#include <string.h>

/* wolfBoot headers */
#include "hal.h"
#include "image.h"  /* for RAMFUNCTION */
#include "loader.h" /* for wolfBoot_panic */
#include "printf.h"

/* iLLD headers */
#include "Ifx_Types.h"
#include "IfxAsclin.h"
#include "IfxAsclin_PinMap.h"
#include "IfxCpu.h"
#include "IfxWtu.h"
#ifndef WOLFBOOT_AURIX_TC4XX_CSRM
#include "IfxClock.h"
#endif

/* ---------------------------------------------------------------------------
 * PFLASH geometry (TC4Dx; see IfxFlash_cfg_TC4Dx.h and
 * IfxFlashCsrm_cfg_TC4Dx.h). Host and CSRM PFLASH share the 32-byte page
 * and 16KB logical sector; only the host interface documents the
 * 512-byte burst program, so the CSRM programs page by page.
 */
#define TC4_PFLASH_PAGE_SIZE  (32u)
#define TC4_PFLASH_BURST_SIZE (512u)
#ifdef WOLFBOOT_AURIX_TC4XX_CSRM
#define TC4_PROG_CHUNK_SIZE   TC4_PFLASH_PAGE_SIZE
#else
#define TC4_PROG_CHUNK_SIZE   TC4_PFLASH_BURST_SIZE
#endif

/* FLASH_BYTE_ERASED (the value synthesized when reading erased flash)
 * comes from wolfboot.h: 0x00 with FLAGS_INVERT, matching FILL_BYTE. */

/* Convert between the cached (0x8...) segment used by the wolfBoot
 * partition configuration and the non-cached (0xA...) alias the command
 * interface requires. */
#define TC4_FLASH_NC(addr) (((uint32_t)(addr)) | 0x20000000u)

/* ---------------------------------------------------------------------------
 * Flash command interface registers. The host command interface (HCI)
 * serves all host PFLASH banks; the CSRM command interface (CSCI, same
 * register layout at +0x40000 / +0x80) serves the CSRM's banks. The
 * target bank is implied by the address written to the command address
 * register.
 */
#ifdef WOLFBOOT_AURIX_TC4XX_CSRM
#define TC4_CMD_BASE (0xF80C0000u)
#else
#define TC4_CMD_BASE (0xF8080000u)
#endif

#define TC4_CMD_REG(off) ((volatile uint32_t *)(TC4_CMD_BASE | (off)))
#define TC4_CMD_MODE     TC4_CMD_REG(0x5554u) /* mode/status cycles */
#define TC4_CMD_LOAD2X32 TC4_CMD_REG(0x55F4u) /* page assembly, 2x32-bit */
#define TC4_CMD_ADDR     TC4_CMD_REG(0xAA50u) /* command word 1: address */
#define TC4_CMD_COUNT    TC4_CMD_REG(0xAA58u) /* command word 2: count */
#define TC4_CMD_CODE     TC4_CMD_REG(0xAAA8u) /* command code, written twice */

#define TC4_MODE_CLEAR_STATUS (0xFAu)
#define TC4_MODE_PF_PAGEMODE  (0x50u)
#define TC4_MODE_RESET_READ   (0xF0u)

/* DMU command interface status/error registers (CSCI mirrors HCI at
 * +0x80) */
#define TC4_DMU_REG(addr) ((volatile uint32_t *)(addr))
#ifdef WOLFBOOT_AURIX_TC4XX_CSRM
#define TC4_HCI_STATUS TC4_DMU_REG(0xF8040084u)
#define TC4_HCI_ERR    TC4_DMU_REG(0xF8040090u)
#define TC4_HCI_CLRERR TC4_DMU_REG(0xF8040094u)
#else
#define TC4_HCI_STATUS TC4_DMU_REG(0xF8040004u)
#define TC4_HCI_ERR    TC4_DMU_REG(0xF8040010u)
#define TC4_HCI_CLRERR TC4_DMU_REG(0xF8040014u)
#endif
#define TC4_GP_BKALLOC TC4_DMU_REG(0xF8040A00u)
#define TC4_BKALLOC_CSRMPF (1u << 18)

/* HCI.STATUS fields */
#define TC4_STATUS_BANKS_BUSY (0x000F0FFFu) /* per-bank busy + host DF + FSI */
#define TC4_STATUS_PFPAGE     (1u << 25)
#define TC4_STATUS_REQDONE    (1u << 31)

/* HCI.ERR fields. EVER (erase verify) is intentionally not part of the
 * failure mask: it is the result bit of the blank-check commands and is
 * evaluated separately. */
#define TC4_ERR_OPFAIL_MASK (0x00010077u) /* ADER|SQER|PROER|ABER|CLER|PVER|OPER */
#define TC4_ERR_EVER        (1u << 7)
#define TC4_CLRERR_ALL      (0xF7u) /* OPER (bit16) has no clear bit */

/* Bounded spin limits, sized like the CSRM flash driver's: generous enough
 * for a worst-case sector erase, small enough to fail rather than hang. */
#define TC4_BUSY_SPIN_LIMIT    (50000000u)
#define TC4_REQDONE_SPIN_LIMIT (1000000u)

#define WOLFBOOT_AURIX_RESET_REASON (0x5742) /* "WB" */

/* Helper macros for the base address of the page or sector containing addr */
#define GET_PAGE_ADDR(addr)   ((uintptr_t)(addr) & ~(TC4_PFLASH_PAGE_SIZE - 1))
#define GET_SECTOR_ADDR(addr) ((uintptr_t)(addr) & ~(WOLFBOOT_SECTOR_SIZE - 1))

#define TC4_DSYNC() __asm volatile("dsync" ::: "memory")

/* RAM buffer holding one flash sector for read-modify-write operations */
static uint32_t sectorBuffer[WOLFBOOT_SECTOR_SIZE / sizeof(uint32_t)];

/* ---------------------------------------------------------------------------
 * Low-level command sequences. Everything that runs while a flash
 * operation is in flight is RAMFUNCTION so no fetch hits a busy bank.
 */

static void RAMFUNCTION flashClearStatus(void)
{
    *TC4_CMD_MODE = TC4_MODE_CLEAR_STATUS;
    TC4_DSYNC();
}

/* Wait for all host banks idle, then for sequence completion (REQDONE).
 * REQDONE - not busy-deassertion - is the real end-of-sequence signal;
 * a timeout is a hard failure because the error latches may be stale.
 * Returns 0 on completion, -1 on timeout. */
static int RAMFUNCTION flashWaitDone(void)
{
    uint32_t spins;

    spins = TC4_BUSY_SPIN_LIMIT;
    while (((*TC4_HCI_STATUS & TC4_STATUS_BANKS_BUSY) != 0u) && (--spins != 0u)) {
    }
    if (spins == 0u) {
        return -1;
    }

    spins = TC4_REQDONE_SPIN_LIMIT;
    while (((*TC4_HCI_STATUS & TC4_STATUS_REQDONE) == 0u) && (--spins != 0u)) {
    }
    if (spins == 0u) {
        return -1;
    }

    TC4_DSYNC();
    return 0;
}

/* Read and clear the error flags. Returns the raw error register value. */
static uint32_t RAMFUNCTION flashGetClearErrors(void)
{
    uint32_t err = *TC4_HCI_ERR;
    *TC4_HCI_CLRERR = TC4_CLRERR_ALL;
    TC4_DSYNC();
    return err;
}

/* Issue a two-cycle command and wait for completion. Returns the error
 * flags on completion or TC4_ERR_OPFAIL_MASK on timeout. */
static uint32_t RAMFUNCTION flashCommand(uint32_t address, uint32_t count,
                                         uint32_t code1, uint32_t code2)
{
    flashClearStatus();
    *TC4_CMD_ADDR  = TC4_FLASH_NC(address);
    *TC4_CMD_COUNT = count;
    *TC4_CMD_CODE  = code1;
    *TC4_CMD_CODE  = code2;
    TC4_DSYNC();

    if (flashWaitDone() != 0) {
        return TC4_ERR_OPFAIL_MASK;
    }
    return flashGetClearErrors();
}

/* Blank check one page via the hardware erase-verify command (reading
 * erased PFLASH would raise an uncorrectable ECC bus error). Returns 1 if
 * erased, 0 if programmed, -1 on error. */
static int RAMFUNCTION flashIsPageErased(uint32_t pageAddr)
{
    uint32_t err = flashCommand(pageAddr, 0u, 0x80u, 0x56u);
    if ((err & TC4_ERR_OPFAIL_MASK) != 0u) {
        return -1;
    }
    return ((err & TC4_ERR_EVER) != 0u) ? 0 : 1;
}

/* Erase one 16KB logical sector. Sectors are erased one at a time: bulk
 * multi-sector erases have been seen to leave the busy flags wedged on
 * this NVM subsystem (see tchsm_csrm_flash.c). Returns 0 on success. */
static int RAMFUNCTION flashEraseSector(uint32_t sectorAddr)
{
    uint32_t err = flashCommand(sectorAddr, 1u, 0x80u, 0x50u);
    if ((err & TC4_ERR_OPFAIL_MASK) != 0u) {
        return -1;
    }
    return 0;
}

/* Program a naturally aligned group of pages (one page or one burst) that
 * is already erased. data must hold size bytes; size is either
 * TC4_PFLASH_PAGE_SIZE or TC4_PFLASH_BURST_SIZE. Returns 0 on success. */
static int RAMFUNCTION flashProgramAligned(uint32_t addr, const uint32_t *data,
                                           uint32_t size)
{
    uint32_t i;
    uint32_t err;
    uint32_t spins;

    /* Enter page mode and wait for the assembly buffer to be ready */
    flashClearStatus();
    *TC4_CMD_MODE = TC4_MODE_PF_PAGEMODE;
    TC4_DSYNC();
    spins = TC4_REQDONE_SPIN_LIMIT;
    while (((*TC4_HCI_STATUS & TC4_STATUS_PFPAGE) == 0u) && (--spins != 0u)) {
    }
    if (spins == 0u) {
        return -1;
    }

    /* Fill the page assembly buffer, two 32-bit words per cycle */
    for (i = 0; i < (size / sizeof(uint32_t)); i += 2u) {
        *TC4_CMD_LOAD2X32 = data[i];
        *TC4_CMD_LOAD2X32 = data[i + 1u];
    }
    TC4_DSYNC();

    /* Write Page (0xAA) or Write Burst (0xA6) */
    err = flashCommand(addr, 0u,
                       0xA0u,
                       (size == TC4_PFLASH_BURST_SIZE) ? 0xA6u : 0xAAu);
    if ((err & TC4_ERR_OPFAIL_MASK) != 0u) {
        /* Leave page mode so the interface is not stuck */
        *TC4_CMD_MODE = TC4_MODE_RESET_READ;
        TC4_DSYNC();
        return -1;
    }
    return 0;
}

/* Read len bytes at address, which must not span an erased page (callers
 * blank-check first). Reads go through the non-cached alias so no stale
 * cache lines are involved. */
static void RAMFUNCTION flashRead(uint32_t address, uint8_t *data, uint32_t len)
{
    const volatile uint8_t *src =
        (const volatile uint8_t *)TC4_FLASH_NC(address);
    uint32_t i;
    for (i = 0; i < len; i++) {
        data[i] = src[i];
    }
}

/* ---------------------------------------------------------------------------
 * Sector-level helpers mirroring the TC3xx HAL structure
 */

/* Read an entire sector into sectorBuffer, substituting the erased-byte
 * value for erased pages so no erased cell is ever read. */
static void RAMFUNCTION cacheSector(uint32_t sectorAddress)
{
    uint32_t page;
    for (page = 0; page < WOLFBOOT_SECTOR_SIZE; page += TC4_PFLASH_PAGE_SIZE) {
        uint32_t *dst = sectorBuffer + (page / sizeof(uint32_t));
        int       erased = flashIsPageErased(sectorAddress + page);

        if (erased < 0) {
            wolfBoot_panic();
        }
        else if (erased == 1) {
            uint32_t i;
            for (i = 0; i < TC4_PFLASH_PAGE_SIZE / sizeof(uint32_t); i++) {
                dst[i] = FLASH_BYTE_ERASED;
            }
        }
        else {
            flashRead(sectorAddress + page, (uint8_t *)dst,
                      TC4_PFLASH_PAGE_SIZE);
        }
    }
}

/* Program sectorBuffer back into an erased sector, chunk by chunk
 * (bursts on the host interface, single pages on the CSRM) */
static void RAMFUNCTION programCachedSector(uint32_t sectorAddress)
{
    uint32_t off;
    for (off = 0; off < WOLFBOOT_SECTOR_SIZE; off += TC4_PROG_CHUNK_SIZE) {
        if (flashProgramAligned(sectorAddress + off,
                                sectorBuffer + (off / sizeof(uint32_t)),
                                TC4_PROG_CHUNK_SIZE) != 0) {
            wolfBoot_panic();
        }
    }
}

/* Program unaligned data into erased flash, page by page */
static int RAMFUNCTION programBytesToErasedFlash(uint32_t address,
                                                 const uint8_t *data, int size)
{
    uint32_t pageBuffer[TC4_PFLASH_PAGE_SIZE / sizeof(uint32_t)];
    uint32_t pageAddress = GET_PAGE_ADDR(address);
    uint32_t offset      = address % TC4_PFLASH_PAGE_SIZE;

    while (size > 0) {
        uint32_t toWrite = TC4_PFLASH_PAGE_SIZE - offset;
        uint32_t i;

        if (toWrite > (uint32_t)size) {
            toWrite = (uint32_t)size;
        }

        for (i = 0; i < TC4_PFLASH_PAGE_SIZE / sizeof(uint32_t); i++) {
            pageBuffer[i] = FLASH_BYTE_ERASED;
        }
        memcpy((uint8_t *)pageBuffer + offset, data, toWrite);

        if (flashProgramAligned(pageAddress, pageBuffer,
                                TC4_PFLASH_PAGE_SIZE) != 0) {
            return -1;
        }

        size -= toWrite;
        data += toWrite;
        address += toWrite;
        pageAddress = GET_PAGE_ADDR(address);
        offset      = address % TC4_PFLASH_PAGE_SIZE;
    }
    return 0;
}

/* ---------------------------------------------------------------------------
 * UART (ASCLIN0, 115200 8N1 on P14.0/P14.1 - same console as the wolfHSM
 * demo applications). Polled, no interrupts.
 */

#if defined(DEBUG_UART) || defined(UART_FLASH)

#define TC4_UART           (&MODULE_ASCLIN0)
#define TC4_UART_BAUD      (115200u)
#define TC4_UART_FIFO_SIZE (16u)

int  uart_tx(const uint8_t c);
int  uart_rx(uint8_t *c);
void uart_init(void);
void uart_write(const char *buf, unsigned int sz);

void uart_init(void)
{
    Ifx_ASCLIN *u = TC4_UART;

    IfxAsclin_enableModule(u);
    IfxAsclin_setClockSource(u, IfxAsclin_ClockSource_noClock);
    IfxAsclin_setFrameMode(u, IfxAsclin_FrameMode_initialise);
    IfxAsclin_setPrescaler(u, 1);
    IfxAsclin_setClockSource(u, IfxAsclin_ClockSource_ascFastClock);
    (void)IfxAsclin_setBitTiming(u, (float32)TC4_UART_BAUD,
                                 IfxAsclin_OversamplingFactor_16,
                                 IfxAsclin_SamplePointPosition_8,
                                 IfxAsclin_SamplesPerBit_three);
    IfxAsclin_setClockSource(u, IfxAsclin_ClockSource_noClock);

    IfxAsclin_enableParity(u, FALSE);
    IfxAsclin_setStopBit(u, IfxAsclin_StopBit_1);
    IfxAsclin_setShiftDirection(u, IfxAsclin_ShiftDirection_lsbFirst);
    IfxAsclin_setDataLength(u, IfxAsclin_DataLength_8);
    IfxAsclin_setTxFifoInletWidth(u, IfxAsclin_TxFifoInletWidth_1);
    IfxAsclin_setRxFifoOutletWidth(u, IfxAsclin_RxFifoOutletWidth_1);
    IfxAsclin_setFrameMode(u, IfxAsclin_FrameMode_asc);

    IfxAsclin_initTxPin(&IfxAsclin0_TX_F_P14_0_OUT, IfxPort_OutputMode_pushPull,
                        IfxPort_PadDriver_cmosAutomotiveSpeed1);
    IfxAsclin_initRxPin(&IfxAsclin0_RXA_F_P14_1_IN, IfxPort_InputMode_pullUp,
                        IfxPort_PadDriver_cmosAutomotiveSpeed1);

    IfxAsclin_setClockSource(u, IfxAsclin_ClockSource_ascFastClock);
    IfxAsclin_disableAllFlags(u);
    IfxAsclin_clearAllFlags(u);
    IfxAsclin_flushTxFifo(u);
    IfxAsclin_enableTxFifoOutlet(u, TRUE);
}

int uart_tx(const uint8_t c)
{
    Ifx_ASCLIN *u = TC4_UART;
    while (IfxAsclin_getTxFifoFillLevel(u) >= TC4_UART_FIFO_SIZE) {
    }
    IfxAsclin_writeTxData(u, c);
    return 1;
}

int uart_rx(uint8_t *c)
{
    (void)c;
    return 0;
}

void uart_write(const char *buf, unsigned int sz)
{
    while (sz > 0) {
        if (*buf == '\n') {
            (void)uart_tx('\r');
        }
        (void)uart_tx(*buf++);
        sz--;
    }
}

/* Block until the TX FIFO has fully drained onto the wire */
static void uart_flush(void)
{
    Ifx_ASCLIN *u = TC4_UART;
    volatile uint32_t i;

    while (IfxAsclin_getTxFifoFillLevel(u) != 0u) {
    }
    /* The TC flag is sticky and may still be set from an earlier idle
     * period while the last frame sits in the shifter, so it cannot be
     * trusted here. Wait a fixed interval instead: one frame at 115200
     * baud is ~87 us; this loop is comfortably longer at any core
     * clock. */
    for (i = 0; i < 200000u; i++) {
    }
}

#endif /* DEBUG_UART || UART_FLASH */

/* ---------------------------------------------------------------------------
 * wolfBoot HAL entry points
 */

void hal_init(void)
{
#ifdef WOLFBOOT_AURIX_TC4XX_CSRM
    /* Disable the CSRM security watchdog for the duration of the image
     * verification, exactly as the tchsm-server does. */
    IfxWtu_disableSecurityWatchdog(IfxWtu_getSecurityWatchdogPassword());

    /* The CSRM PFLASH bank must be allocated to the CSRM or the CSCI
     * command writes silently no-op. */
    if ((*TC4_GP_BKALLOC & TC4_BKALLOC_CSRMPF) == 0u) {
        wolfBoot_panic();
    }
#else
    /* The iLLD startup software has already run: PLLs locked, flash
     * waitstates programmed, CPU1..5 held in reset. Watchdogs are live -
     * disable them for the duration of the (potentially long) image
     * verification, exactly as the demo applications do. */
    IfxWtu_disableCpuWatchdog(IfxWtu_getCpuWatchdogPassword());
    IfxWtu_disableSystemWatchdog(IfxWtu_getSystemWatchdogPassword());

    /* Refuse to run if a host PFLASH bank this HAL programs has been
     * reallocated to the CSRM: command writes would silently no-op. Banks
     * P00/P01 (wolfBoot, pfls0) and P10/P11 (partitions, pfls1) must be
     * host-owned (BKALLOC bit clear). */
    if ((*TC4_GP_BKALLOC & 0xFu) != 0u) {
        wolfBoot_panic();
    }
#endif

#ifdef DEBUG_UART
#ifdef WOLFBOOT_AURIX_TC4XX_CSRM
    /* The ASCLIN0/P14 write grants for the CSRM come from the host
     * parker running on CPU0 (port/wolfboot/csrm/host_park.S), which is
     * released from reset in parallel with this core. Its dozen store
     * instructions finish long before this point, but give it explicit
     * margin: an ungranted UART register write is a bus-error trap. */
    {
        volatile uint32_t i;
        for (i = 0; i < 100000u; i++) {
        }
    }
#endif
    uart_init();
#ifdef WOLFBOOT_AURIX_TC4XX_CSRM
    wolfBoot_printf("Hello from TC4xx wolfBoot on CSRM: V%d\n",
                    WOLFBOOT_VERSION);
#else
    wolfBoot_printf("Hello from TC4xx wolfBoot on TriCore CPU0: V%d\n",
                    WOLFBOOT_VERSION);
#endif
#endif
}

void hal_prepare_boot(void)
{
#ifdef DEBUG_UART
    /* Final print, then drain so the clock switch below cannot corrupt
     * in-flight characters */
    wolfBoot_printf("hal_prepare_boot\n");
    uart_flush();
    IfxAsclin_setClockSource(TC4_UART, IfxAsclin_ClockSource_noClock);
    IfxAsclin_disableModule(TC4_UART);
#endif

#ifndef WOLFBOOT_AURIX_TC4XX_CSRM
    /* Return the clock tree to the backup clock and power the PLLs down.
     * The application image re-runs the full iLLD SSW (including
     * IfxClock_init), which refuses to reconfigure a PLL the system is
     * currently running from - so hand it the same near-reset clock state
     * a cold boot would. The CSRM startup software never touches the
     * clock tree, so its flavor has nothing to restore. */
    (void)IfxClock_switchToBackupClock(&IfxClock_defaultClockConfig);
#endif
}

void do_boot(const uint32_t *app_offset)
{
    /* Jump to the application's startup code (its .start section, placed
     * at BOOT partition + IMAGE_HEADER_SIZE). The app's SSW rebuilds CSA,
     * stacks, clocks and starts the secondary cores. */
    __asm volatile("ji %0" ::"a"(app_offset));
}

void RAMFUNCTION arch_reboot(void)
{
    (void)WOLFBOOT_AURIX_RESET_REASON;
#ifdef WOLFBOOT_AURIX_TC4XX_CSRM
    /* The system reset request register (SMM) is host-domain; whether the
     * CSRM may write it is untested, and no path in this configuration
     * reaches here. Hang for the debugger instead of risking a fault. */
    while (1) {
    }
#else
    IfxCpu_triggerSwReset();
    while (1) {
    }
#endif
}

/* ---------------------------------------------------------------------------
 * Flash HAL. Addresses arrive in the cached (0x8...) segment from the
 * partition configuration; all command sequences convert to the
 * non-cached alias internally.
 */

int RAMFUNCTION hal_flash_write(uint32_t address, const uint8_t *data, int size)
{
    int ret               = 0;
    uint32_t currentAddress = address;
    int      remainingSize  = size;
    int      bytesWrittenTotal = 0;

    while (remainingSize > 0) {
        uint32_t currentSectorAddress = GET_SECTOR_ADDR(currentAddress);
        uint32_t offsetInSector       = currentAddress - currentSectorAddress;
        uint32_t bytesInThisSector    = WOLFBOOT_SECTOR_SIZE - offsetInSector;
        uint32_t page;
        int      needsSectorRmw = 0;

        if (bytesInThisSector > (uint32_t)remainingSize) {
            bytesInThisSector = remainingSize;
        }

        /* If any affected page already has data, read-modify-write the
         * whole sector */
        const uint32_t startPage = GET_PAGE_ADDR(currentAddress);
        const uint32_t endPage =
            GET_PAGE_ADDR(currentAddress + bytesInThisSector - 1);
        for (page = startPage; page <= endPage; page += TC4_PFLASH_PAGE_SIZE) {
            int erased = flashIsPageErased(page);
            if (erased < 0) {
                return -1;
            }
            if (erased == 0) {
                needsSectorRmw = 1;
                break;
            }
        }

        if (needsSectorRmw) {
            cacheSector(currentSectorAddress);

            ret = hal_flash_erase(currentSectorAddress, WOLFBOOT_SECTOR_SIZE);
            if (ret != 0) {
                break;
            }

            memcpy((uint8_t *)sectorBuffer + offsetInSector,
                   data + bytesWrittenTotal, bytesInThisSector);

            programCachedSector(currentSectorAddress);
        }
        else {
            ret = programBytesToErasedFlash(currentAddress,
                                            data + bytesWrittenTotal,
                                            bytesInThisSector);
            if (ret != 0) {
                break;
            }
        }

        bytesWrittenTotal += bytesInThisSector;
        currentAddress += bytesInThisSector;
        remainingSize -= bytesInThisSector;
    }

    return ret;
}

int RAMFUNCTION hal_flash_erase(uint32_t address, int len)
{
    uint32_t currentSectorAddr;
    uint32_t startSectorAddr;
    uint32_t endAddress;
    uint32_t endSectorAddr;
    int      ret = 0;

    if (len <= 0) {
        return 0;
    }

    startSectorAddr = GET_SECTOR_ADDR(address);
    endAddress      = address + len - 1;
    endSectorAddr   = GET_SECTOR_ADDR(endAddress);

    for (currentSectorAddr = startSectorAddr;
         currentSectorAddr <= endSectorAddr;
         currentSectorAddr += WOLFBOOT_SECTOR_SIZE) {

        const int isFirstSector = (currentSectorAddr == startSectorAddr);
        const int isLastSector  = (currentSectorAddr == endSectorAddr);
        const int isPartialStart =
            isFirstSector && (address > startSectorAddr);
        const int isPartialEnd =
            isLastSector &&
            (endAddress < (endSectorAddr + WOLFBOOT_SECTOR_SIZE - 1));

        if (isPartialStart || isPartialEnd) {
            /* Partial sector: read-modify-write with the target range
             * filled with the erased value */
            uint32_t eraseStartOffset =
                isPartialStart ? (address - currentSectorAddr) : 0;
            uint32_t eraseEndOffset = isPartialEnd
                                          ? (endAddress - currentSectorAddr)
                                          : (WOLFBOOT_SECTOR_SIZE - 1);
            uint32_t eraseLen = eraseEndOffset - eraseStartOffset + 1;
            uint32_t i;

            cacheSector(currentSectorAddr);

            for (i = 0; i < eraseLen; i++) {
                ((uint8_t *)sectorBuffer)[eraseStartOffset + i] =
                    FLASH_BYTE_ERASED;
            }

            if (flashEraseSector(currentSectorAddr) != 0) {
                ret = -1;
                break;
            }

            programCachedSector(currentSectorAddr);
        }
        else {
            if (flashEraseSector(currentSectorAddr) != 0) {
                ret = -1;
                break;
            }
        }
    }

    return ret;
}

void RAMFUNCTION hal_flash_unlock(void)
{
}

void RAMFUNCTION hal_flash_lock(void)
{
}

int RAMFUNCTION ext_flash_write(uintptr_t address, const uint8_t *data, int len)
{
    return hal_flash_write((uint32_t)address, data, len);
}

/* Reads flash, synthesizing the erased-byte value for erased pages
 * (reading them directly would raise an uncorrectable ECC bus error).
 * Returns the number of bytes read, or -1 on error. */
int RAMFUNCTION ext_flash_read(uintptr_t address, uint8_t *data, int len)
{
    int bytesRead = 0;

    while (bytesRead < len) {
        uint32_t pageAddress = GET_PAGE_ADDR(address);
        uint32_t offset      = address % TC4_PFLASH_PAGE_SIZE;
        uint32_t bytesInThisPage = TC4_PFLASH_PAGE_SIZE - offset;
        int      erased;

        if (bytesInThisPage > (uint32_t)(len - bytesRead)) {
            bytesInThisPage = len - bytesRead;
        }

        erased = flashIsPageErased(pageAddress);
        if (erased < 0) {
            return -1;
        }

        if (erased == 1) {
            uint32_t i;
            for (i = 0; i < bytesInThisPage; i++) {
                data[bytesRead + i] = FLASH_BYTE_ERASED;
            }
        }
        else {
            flashRead(address, data + bytesRead, bytesInThisPage);
        }

        address += bytesInThisPage;
        bytesRead += bytesInThisPage;
    }

    return bytesRead;
}

int RAMFUNCTION ext_flash_erase(uintptr_t address, int len)
{
    return hal_flash_erase((uint32_t)address, len);
}

void RAMFUNCTION ext_flash_lock(void)
{
    hal_flash_lock();
}

void RAMFUNCTION ext_flash_unlock(void)
{
    hal_flash_unlock();
}
