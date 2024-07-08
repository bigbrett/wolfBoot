#include <stdint.h>
#include <string.h>

/* wolfBoot headers */
#include "image.h" /* for RAMFUNCTION */

/* ILLD headers */
#include "Ifx_Ssw_Infra.h" /* for Ifx_Ssw_jumpToFunction */
#include "IfxFlash.h" /* for IfxFlash_eraseMultipleSectors, */


/* TODO: This is just to make eclipse happy, remove */
#define RAMFUNCTION __attribute__((used,section(".ramcode")))

#define FLASH_MODULE (0)


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
int RAMFUNCTION hal_flash_write(uint32_t address, const uint8_t* data, int len)
{
    int rc = 0;
    const int npages = len / IFXFLASH_PFLASH_PAGE_LENGTH;
    uint32_t pgbuf[IFXFLASH_PFLASH_PAGE_LENGTH/sizeof(uint32_t)];

    /* Get the current password of the Safety WatchDog module */
    uint16 endInitSafetyPassword = IfxScuWdt_getSafetyWatchdogPasswordInline();

    /* Iterate over each page to program */
    for(int page = 0; page < npages; page++)
    {
        /* Get the address of the page to program */
        uint32 pageAddr = IFXFLASH_PFLASH_P0_START + (page * IFXFLASH_PFLASH_PAGE_LENGTH);

        /* Enter in page mode */
        IfxFlash_enterPageMode(pageAddr);

        /* Wait until page mode is entered */
        IfxFlash_waitUnbusy(FLASH_MODULE, IfxFlash_FlashType_P0);

        /* Load data to be written in the page */
        memcpy(pgbuf, data, IFXFLASH_PFLASH_PAGE_LENGTH);
        IfxFlash_loadPage2X32(pageAddr, pgbuf[0], pgbuf[1]); /* TODO: which loadPage should we use?*/

        /* Write the loaded page */
        IfxScuWdt_clearSafetyEndinit(endInitSafetyPassword);    /* Disable EndInit protection                       */
        IfxFlash_writePage(pageAddr);                           /* Write the page                                   */
        IfxScuWdt_setSafetyEndinit(endInitSafetyPassword);      /* Enable EndInit protection                        */

        /* Wait until the data is written in the Data Flash memory */
        IfxFlash_waitUnbusy(FLASH_MODULE, IfxFlash_FlashType_P0);

        data += IFXFLASH_PFLASH_PAGE_LENGTH;
    }

    return rc;
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
    IfxFlash_eraseMultipleSectors(address, len / WOLFBOOT_SECTOR_SIZE );
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
