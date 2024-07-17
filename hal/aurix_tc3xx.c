#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* wolfBoot headers */
#include "image.h" /* for RAMFUNCTION */
#include "loader.h" /* for wolfBoot_panic */

/* ILLD headers */
#include "IfxFlash.h" /* for IfxFlash_eraseMultipleSectors, */
#include "IfxScuRcu.h" /* for IfxScuRcu_performReset */
#include "Ifx_Ssw_Infra.h" /* for Ifx_Ssw_jumpToFunction */

#define FLASH_MODULE (0)
#define UNUSED_PARAMETER (0)

/* Helper macros to gets the base address of the page, wordline, or sector that
 * contains byteAddress */
#define GET_PAGE_ADDR(addr) \
    ((uintptr_t)(addr) & ~(IFXFLASH_PFLASH_PAGE_LENGTH - 1))
#define GET_WORDLINE_ADDR(addr) \
    ((uintptr_t)(addr) & ~(IFXFLASH_PFLASH_WORDLINE_LENGTH - 1))
#define GET_SECTOR_ADDR(addr) ((uintptr_t)(addr) & ~(WOLFBOOT_SECTOR_SIZE - 1))

static uint32_t sectorBuffer[WOLFBOOT_SECTOR_SIZE];

static IfxFlash_FlashType getFlashTypeFromAddr(uint32_t addr)
{
    IfxFlash_FlashType type = 0;

    if (addr >= IFXFLASH_DFLASH_START && addr <= IFXFLASH_DFLASH_END) {
        type = IfxFlash_FlashType_D0; /* Assuming D0 for simplicity */
    }
    else if (addr >= IFXFLASH_PFLASH_P0_START && addr <= IFXFLASH_PFLASH_P0_END)
    {
        type = IfxFlash_FlashType_P0;
    }
    else if (addr >= IFXFLASH_PFLASH_P1_START && addr <= IFXFLASH_PFLASH_P1_END)
    {
        type = IfxFlash_FlashType_P1;
    }
    else {
        /* bad address, panic for now */
        wolfBoot_panic();
    }

    return type;
}

static void RAMFUNCTION programPage(uint32_t address,
                                    const uint32_t* data,
                                    IfxFlash_FlashType type)
{
    if (address % IFXFLASH_PFLASH_PAGE_LENGTH != 0) {
        wolfBoot_panic();
    }

    uint16 endInitSafetyPassword = IfxScuWdt_getSafetyWatchdogPasswordInline();

    // Enter page mode
    IfxFlash_enterPageMode(address);

    // Wait until page mode is entered
    IfxFlash_waitUnbusy(FLASH_MODULE, type);

    // Load data to be written in the page
    for (size_t offset = 0;
         offset < IFXFLASH_PFLASH_PAGE_LENGTH / sizeof(uint32_t);
         offset += 2)
    {
        // IfxFlash_loadPage(pageAddr, data[offset], data[offset+1]);
        IfxFlash_loadPage2X32(address, data[offset], data[offset + 1]);
    }

    // Write the loaded page
    IfxScuWdt_clearSafetyEndinitInline(endInitSafetyPassword);
    IfxFlash_writePage(address);  // Write the page
    IfxScuWdt_setSafetyEndinitInline(
        endInitSafetyPassword);  // Enable EndInit protection

    // Wait until the data is written in the Data Flash memory
    IfxFlash_waitUnbusy(FLASH_MODULE, type);
}

static int RAMFUNCTION flashIsErased(uint32_t address,
                                     int len,
                                     IfxFlash_FlashType type)
{
    uint32_t base = 0;

    /* TODO ensure len doesn't span flash units */

    /* Clear status flags */
    IfxFlash_clearStatus(UNUSED_PARAMETER);

    /* sector granularity */
    if (len > IFXFLASH_PFLASH_WORDLINE_LENGTH) {
        base = GET_SECTOR_ADDR(address);
        IfxFlash_eraseVerifySector(base);
        IfxFlash_waitUnbusy(FLASH_MODULE, type);
    }
    /* wordline granularity */
    else if (len > IFXFLASH_PFLASH_PAGE_LENGTH) {
        base = GET_WORDLINE_ADDR(address);
        IfxFlash_verifyErasedWordLine(base);
        IfxFlash_waitUnbusy(FLASH_MODULE, type);
    }
    /* page granularity */
    else if (len > 0) {
        base = GET_PAGE_ADDR(address);
        IfxFlash_verifyErasedPage(base);
        IfxFlash_waitUnbusy(FLASH_MODULE, type);
    }
    /* error on 0 len for now */
    else {
        wolfBoot_panic();
    }

    /* No erase verify error means block is erased */
    return (DMU_HF_ERRSR.B.EVER == 0) ? 1 : 0;
}

/* Returns true if any of the pages spanned by address and len are erased */
static int RAMFUNCTION containsErasedPage(uint32_t address,
                                          size_t len,
                                          IfxFlash_FlashType type)
{
    uint32_t startPage = GET_PAGE_ADDR(address);
    uint32_t endPage   = GET_PAGE_ADDR(address + len - 1);

    for (uint32_t page = startPage; page <= endPage;
         page += IFXFLASH_PFLASH_PAGE_LENGTH)
    {
        if (flashIsErased(page, IFXFLASH_PFLASH_PAGE_LENGTH, type)) {
            return 1;
        }
    }

    return 0;
}

/* Manually programs erased bytes to a sector to prevent ECC errors */
static void RAMFUNCTION programErasedSector(uint32_t address,
                                            IfxFlash_FlashType type)
{
    uint16 endInitSafetyPassword = IfxScuWdt_getSafetyWatchdogPasswordInline();
    uint32_t pageAddr            = address;

    /* Burst program the whole sector with erased values */
    for (int i = 0; i < WOLFBOOT_SECTOR_SIZE / IFXFLASH_PFLASH_BURST_LENGTH;
         i++)
    {
        IfxFlash_enterPageMode(pageAddr);

        /* Wait until page mode is entered */
        IfxFlash_waitUnbusy(FLASH_MODULE, type);

        /* Load a burst size worth of data into the page */
        for (int offset = 0; offset < IFXFLASH_PFLASH_BURST_LENGTH;
             offset += 2 * sizeof(uint32_t))
        {
            IfxFlash_loadPage2X32(UNUSED_PARAMETER,
                                  FLASH_WORD_ERASED,
                                  FLASH_WORD_ERASED);
        }

        /* Write the page */
        IfxScuWdt_clearSafetyEndinitInline(endInitSafetyPassword);
        IfxFlash_writeBurst(pageAddr);
        IfxScuWdt_setSafetyEndinitInline(endInitSafetyPassword);

        /* Wait until the page is written in the Program Flash memory */
        IfxFlash_waitUnbusy(FLASH_MODULE, type);

        pageAddr += IFXFLASH_PFLASH_BURST_LENGTH;
    }
}

/* Programs the contents of the cached sector buffer to flash */
static void RAMFUNCTION programCachedSector(uint32_t sectorAddress,
                                            IfxFlash_FlashType type)
{
    uint16 endInitSafetyPassword = IfxScuWdt_getSafetyWatchdogPasswordInline();
    uint32_t pageAddr            = sectorAddress;

    /* Burst program the whole sector with values from sectorBuffer */
    for (int i = 0; i < WOLFBOOT_SECTOR_SIZE / IFXFLASH_PFLASH_BURST_LENGTH;
         i++)
    {
        IfxFlash_enterPageMode(pageAddr);

        /* Wait until page mode is entered */
        IfxFlash_waitUnbusy(FLASH_MODULE, type);

        /* Load a burst worth of data into the page */
        for (size_t offset = 0;
             offset < IFXFLASH_PFLASH_BURST_LENGTH / (2 * sizeof(uint32_t));
             offset++)
        {
            size_t bufferIndex =
                i * (IFXFLASH_PFLASH_BURST_LENGTH / sizeof(uint32_t))
                + (offset * 2);
            IfxFlash_loadPage2X32(UNUSED_PARAMETER,
                                  sectorBuffer[bufferIndex],
                                  sectorBuffer[bufferIndex + 1]);
        }

        /* Write the page */
        IfxScuWdt_clearSafetyEndinitInline(endInitSafetyPassword);
        IfxFlash_writeBurst(pageAddr);
        IfxScuWdt_setSafetyEndinitInline(endInitSafetyPassword);

        /* Wait until the page is written in the Program Flash memory */
        IfxFlash_waitUnbusy(FLASH_MODULE, type);

        pageAddr += IFXFLASH_PFLASH_BURST_LENGTH;
    }
}

/* Programs unaligned input data to flash, assuming the underlying memory is erased */
void RAMFUNCTION programBytesToErasedFlash(uint32_t address,
                                           const uint8_t* data,
                                           int size,
                                           IfxFlash_FlashType type)
{
    uint32_t pageBuffer[IFXFLASH_PFLASH_PAGE_LENGTH / sizeof(uint32_t)];
    uint32_t pageAddress = address & ~(IFXFLASH_PFLASH_PAGE_LENGTH - 1);
    uint32_t offset      = address % IFXFLASH_PFLASH_PAGE_LENGTH;
    uint32_t toWrite;

    while (size > 0) {
        /* Calculate the number of bytes to write in the current page */
        toWrite = IFXFLASH_PFLASH_PAGE_LENGTH - offset;
        if (toWrite > size) {
            toWrite = size;
        }

        /* Fill the page buffer with the erased byte value */
        memset(pageBuffer, FLASH_BYTE_ERASED, IFXFLASH_PFLASH_PAGE_LENGTH);

        /* Copy the new data into the page buffer at the correct offset */
        memcpy((uint8_t*)pageBuffer + offset, data, toWrite);

        /* Write the modified page buffer back to flash */
        programPage(pageAddress, pageBuffer, type);

        /* Update pointers and counters */
        size -= toWrite;
        data += toWrite;
        address += toWrite;
        pageAddress = address & ~(IFXFLASH_PFLASH_PAGE_LENGTH - 1);
        offset =
            address
            % IFXFLASH_PFLASH_PAGE_LENGTH;  // Calculate offset for the next page
    }
}

static void readPage32(uint32_t pageAddr, uint32_t* data)
{
    uint32_t* ptr = (uint32_t*)pageAddr;

    for (int i = 0; i < IFXFLASH_PFLASH_PAGE_LENGTH / sizeof(uint32_t); i++) {
        *data = *ptr;
        data++;
        ptr++;
    }
}

/* reads an entire flash sector into the RAM cache, making sure to never read
 * any pages from flash that are erased */
static void cacheSector(uint32_t sectorAddress, IfxFlash_FlashType type)
{
    uint32_t startPage = GET_PAGE_ADDR(sectorAddress);
    uint32_t endPage = GET_PAGE_ADDR(sectorAddress + WOLFBOOT_SECTOR_SIZE - 1);

    /* Iterate over every page in the sector, caching its contents if not
     * erased, and caching 0s if erased */
    for (uint32_t page = startPage; page <= endPage;
         page += IFXFLASH_PFLASH_PAGE_LENGTH)
    {
        uint32_t* pageInSectorBuffer =
            sectorBuffer + ((page - sectorAddress) / sizeof(uint32_t));
        if (flashIsErased(page, IFXFLASH_PFLASH_PAGE_LENGTH, type)) {
            memset(pageInSectorBuffer,
                   FLASH_BYTE_ERASED,
                   IFXFLASH_PFLASH_PAGE_LENGTH);
        }
        else {
            readPage32(page, pageInSectorBuffer);
        }
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
int RAMFUNCTION hal_flash_write(uint32_t address, const uint8_t* data, int size)
{
    /* base address of the containing sector (TODO what if size spans sectors?) */
    const uint32_t sectorAddress  = GET_SECTOR_ADDR(address);
    const IfxFlash_FlashType type = getFlashTypeFromAddr(address);

    /* Flag to check if sector read-modify-write is necessary */
    bool needsSectorRmw = false;

    /* Determine the range of pages affected */
    uint32_t startPage = GET_PAGE_ADDR(address);
    uint32_t endPage   = GET_PAGE_ADDR(address + size - 1);

    /* Check if any page within the range is not erased */
    for (uint32_t page = startPage; page <= endPage;
         page += IFXFLASH_PFLASH_PAGE_LENGTH)
    {
        if (!flashIsErased(page, IFXFLASH_PFLASH_PAGE_LENGTH, type)) {
            needsSectorRmw = true;
            break;
        }
    }

    if (needsSectorRmw) {
        /* Read entire sector into RAM */
        cacheSector(sectorAddress, type);

        /* Erase the entire sector */
        hal_flash_erase(sectorAddress, WOLFBOOT_SECTOR_SIZE);

        /* Modify the relevant part of the sector buffer */
        size_t offsetInSector = address - sectorAddress;
        memcpy((uint8_t*)sectorBuffer + offsetInSector, data, size);

        /* Program the modified sector back into flash */
        programCachedSector(sectorAddress, type);
    }
    else {
        /* All affected pages are erased, program the data directly */
        programBytesToErasedFlash(address, data, size, type);
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
    int rc                    = 0;
    const uint32_t sectorAddr = GET_SECTOR_ADDR(address);
    const size_t numSectors   = (len == 0) ? 0 : 1 + len / WOLFBOOT_SECTOR_SIZE;
    IfxFlash_FlashType type   = getFlashTypeFromAddr(address);

    /* Get the current password of the Safety WatchDog module */
    uint16 endInitSafetyPassword = IfxScuWdt_getSafetyWatchdogPasswordInline();

    /* Erase the sector */
    IfxScuWdt_clearSafetyEndinitInline(endInitSafetyPassword);
    IfxFlash_eraseMultipleSectors(sectorAddr, numSectors);
    IfxScuWdt_setSafetyEndinitInline(endInitSafetyPassword);

    IfxFlash_waitUnbusy(FLASH_MODULE, type);

    return rc;
}

/* This function is called by the bootloader at a very late stage, before
 * chain-loading the firmware in the next stage. This can be used to revert all
 * the changes made to the clock settings, to ensure that the state of the
 * microcontroller is restored to its original settings */
void hal_prepare_boot(void)
{
}

/* If the IAP interface of the flash memory of the target requires it, this
 * function is called before every write and erase operations to unlock write
 * access to the flash. On some targets, this function may be empty. */
void RAMFUNCTION hal_flash_unlock(void)
{
}

/* If the IAP interface of the flash memory requires locking/unlocking, this
 * function restores the flash write protection by excluding write accesses.
 * This function is called by the bootloader at the end of every write and erase
 * operations. */
void RAMFUNCTION hal_flash_lock(void)
{
}

int RAMFUNCTION ext_flash_write(uintptr_t address, const uint8_t* data, int len)
{
    return hal_flash_write(address, data, len);
}

int RAMFUNCTION ext_flash_read(uintptr_t address, uint8_t* data, int len)
{
    int bytesRead = 0;

    IfxFlash_FlashType type = getFlashTypeFromAddr(address);

    while (bytesRead < len) {
        uint32_t pageAddress = GET_PAGE_ADDR(address);
        uint32_t offset      = address % IFXFLASH_PFLASH_PAGE_LENGTH;

        // Check if the current page is erased
        int isErased =
            flashIsErased(pageAddress, IFXFLASH_PFLASH_PAGE_LENGTH, type);

        // Read bytes from the current page
        while (offset < IFXFLASH_PFLASH_PAGE_LENGTH && bytesRead < len) {
            if (isErased) {
                data[bytesRead] =
                    FLASH_BYTE_ERASED;  // Assuming erased data is set to 0xFF
            }
            else {
                data[bytesRead] = *((uint8_t*)address);
            }
            address++;
            bytesRead++;
            offset++;
        }
    }

    return 0;
}

int RAMFUNCTION ext_flash_erase(uintptr_t address, int len)
{
    return hal_flash_erase(address, len);
}

void RAMFUNCTION ext_flash_lock(void)
{
    hal_flash_lock();
}

void RAMFUNCTION ext_flash_unlock(void)
{
    hal_flash_unlock();
}

void do_boot(const uint32_t* app_offset)
{
    /* TODO need to do anything with stack pointer, CSA, etc? */

    Ifx_Ssw_jumpToFunction((void (*)(void))app_offset);
}

void arch_reboot(void)
{
    /* TODO implement custom reset reason (e.g. "self update") for wolfBoot if
     * needed */
    IfxScuRcu_performReset(IfxScuRcu_ResetType_system, 0);
}
