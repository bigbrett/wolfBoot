#include <stdint.h>
#include <string.h>
#include <stddef.h>

/* wolfBoot headers */
#include "image.h" /* for RAMFUNCTION */

/* ILLD headers */
#include "Ifx_Ssw_Infra.h" /* for Ifx_Ssw_jumpToFunction */
#include "IfxFlash.h" /* for IfxFlash_eraseMultipleSectors, */
#include "IfxScuRcu.h" /* for IfxScuRcu_performReset */

#define FLASH_MODULE (0)

/* Manually programs erased bytes to a sector to prevent ECC errors */
static void programErasedSector(uint32_t address)
{
    uint16 endInitSafetyPassword = IfxScuWdt_getSafetyWatchdogPasswordInline();
    uint32_t pageAddr = address;

    /* Burst program the whole sector with erased values */
    for (int i=0; i<WOLFBOOT_SECTOR_SIZE / IFXFLASH_PFLASH_BURST_LENGTH; i++) {
        IfxFlash_enterPageMode(pageAddr);

        /* Wait until page mode is entered */
        IfxFlash_waitUnbusy(FLASH_MODULE, IfxFlash_FlashType_P0);

        /* Load a burst size worth of data into the page */
        for(int offset = 0; offset < IFXFLASH_PFLASH_BURST_LENGTH; offset += 2*sizeof(uint32_t)) {
            IfxFlash_loadPage2X32(0, FLASH_WORD_ERASED, FLASH_WORD_ERASED);
        }

        /* Write the page */
        IfxScuWdt_clearSafetyEndinitInline(endInitSafetyPassword);
        IfxFlash_writeBurst(pageAddr);
        IfxScuWdt_setSafetyEndinitInline(endInitSafetyPassword);

        /* Wait until the page is written in the Program Flash memory */
        IfxFlash_waitUnbusy(FLASH_MODULE, IfxFlash_FlashType_P0);

        pageAddr += IFXFLASH_PFLASH_BURST_LENGTH;
    }

}


/* This function is called by the bootloader at the very beginning of the
 * execution. Ideally, the implementation provided configures the clock settings
 * for the target microcontroller, to ensure that it runs at at the required
 * speed to shorten the time required for the cryptography primitives to verify
 * the firmware images*/
void hal_init(void)
{
    /* eventually this will hold the clock init and CPU sync stuff that is
     * currently happening in core0_main() */
}

/*
 * This function provides an implementation of the flash write function, using
 * the target's IAP interface. address is the offset from the beginning of the
 * flash area, data is the payload to be stored in the flash using the IAP
 * interface, and len is the size of the payload. hal_flash_write should return
 * 0 upon success, or a negative value in case of failure.
 */
int RAMFUNCTION hal_flash_write(uint32_t address, const uint8_t *data, int len) {
    int i = 0;
    uint32_t pageAddr;
    uint32_t pgbuf[IFXFLASH_PFLASH_PAGE_LENGTH / 4];  // Buffer to hold 32 bytes of data (8 x 32-bit words)
    uint16 endInitSafetyPassword = IfxScuWdt_getSafetyWatchdogPasswordInline();

    while (i < len) {
        // Calculate the page address (aligned to 32 bytes)
        pageAddr = (address + i) & ~(IFXFLASH_PFLASH_PAGE_LENGTH - 1);

        // Initialize buffer with 0xFF (default flash value)
        memset(pgbuf, 0xFF, sizeof(pgbuf));

        if ((len - i >= IFXFLASH_PFLASH_PAGE_LENGTH) && (((address + i) & (IFXFLASH_PFLASH_PAGE_LENGTH - 1)) == 0) && (((uintptr_t)(data + i) & (IFXFLASH_PFLASH_PAGE_LENGTH - 1)) == 0)) {
            // Direct 32-byte aligned write
            memcpy(pgbuf, data + i, IFXFLASH_PFLASH_PAGE_LENGTH);
            i += IFXFLASH_PFLASH_PAGE_LENGTH;
        } else {
            // Unaligned or smaller-than-32-byte write
            uint8_t *vbytes = (uint8_t *)pgbuf;
            int offset = (address + i) % IFXFLASH_PFLASH_PAGE_LENGTH;
            int remaining = len - i;
            int toWrite = remaining > (IFXFLASH_PFLASH_PAGE_LENGTH - offset) ? (IFXFLASH_PFLASH_PAGE_LENGTH - offset) : remaining;

            // Read the current 32-byte value from flash
            for (int j = 0; j < IFXFLASH_PFLASH_PAGE_LENGTH / 4; j++) {
                pgbuf[j] = *((uint32_t *)(address + pageAddr + j * 4));
            }

            // Update buffer with new data
            for (int j = 0; j < toWrite; j++) {
                vbytes[offset + j] = data[i + j];
            }

            i += toWrite;
        }

        // Enter page mode
        IfxFlash_enterPageMode(pageAddr);

        // Wait until page mode is entered
        IfxFlash_waitUnbusy(FLASH_MODULE, IfxFlash_FlashType_P0);

        // Load data to be written in the page
        IfxFlash_loadPage(pageAddr, pgbuf[0], pgbuf[1]);

        // Write the loaded page
        IfxScuWdt_clearSafetyEndinit(endInitSafetyPassword); // Disable EndInit protection
        IfxFlash_writePage(pageAddr);                         // Write the page
        IfxScuWdt_setSafetyEndinit(endInitSafetyPassword);    // Enable EndInit protection

        // Wait until the data is written in the Data Flash memory
        IfxFlash_waitUnbusy(FLASH_MODULE, IfxFlash_FlashType_P0);
    }
    return 0;
}

/* Called by the bootloader to erase part of the flash memory to allow
 * subsequent boots. Erase operations must be performed via the specific IAP
 * interface of the target microcontroller. address marks the start of the area
 * that the bootloader wants to erase, and len specifies the size of the area to
 * be erased. This function must take into account the geometry of the flash
 * sectors, and erase all the sectors in between. */
int RAMFUNCTION hal_flash_erase(uint32_t address, int len)
{
    int rc = 0;
    const size_t nsectors = len / WOLFBOOT_SECTOR_SIZE;

    IfxFlash_eraseMultipleSectors(address, nsectors );

    for (int i = 0; i < nsectors; i++) {
        programErasedSector(address);
        address += WOLFBOOT_SECTOR_SIZE;
    }
    return rc;
}

/* This function is called by the bootloader at a very late stage, before
 * chain-loading the firmware in the next stage. This can be used to revert all
 * the changes made to the clock settings, to ensure that the state of the
 * microcontroller is restored to its original settings */
void hal_prepare_boot(void) {}

/* If the IAP interface of the flash memory of the target requires it, this
 * function is called before every write and erase operations to unlock write
 * access to the flash. On some targets, this function may be empty. */
void RAMFUNCTION hal_flash_unlock(void) {}
/* If the IAP interface of the flash memory requires locking/unlocking, this
 * function restores the flash write protection by excluding write accesses.
 * This function is called by the bootloader at the end of every write and erase
 * operations. */
void RAMFUNCTION hal_flash_lock(void) {}


void do_boot(const uint32_t* app_offset)
{
    /* TODO need to do anything with stack pointer, CSA, etc? */

    Ifx_Ssw_jumpToFunction((void (*)(void))app_offset);
}


void arch_reboot(void)
{
    /* TODO implement custom reset reason (e.g. "self update") for wolfBoot if needed */
    IfxScuRcu_performReset(IfxScuRcu_ResetType_system, 0);
}
