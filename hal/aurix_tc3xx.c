#include <stdint.h>

#include "Ifx_Ssw_Infra.h"

/*This function is called by the bootloader at the very beginning of the
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
int hal_flash_write(uint32_t address, const uint8_t* data, int len)
{
    int rc = 0;

    return rc;
}

/* Called by the bootloader to erase part of the flash memory to allow
 * subsequent boots. Erase operations must be performed via the specific IAP
 * interface of the target microcontroller. address marks the start of the area
 * that the bootloader wants to erase, and len specifies the size of the area to
 * be erased. This function must take into account the geometry of the flash
 * sectors, and erase all the sectors in between. */
int hal_flash_erase(uint32_t address, int len)
{
    int rc = 0;

    return rc;
}

/* This function is called by the bootloader at a very late stage, before
 * chain-loading the firmware in the next stage. This can be used to revert all
 * the changes made to the clock settings, to ensure that the state of the
 * microcontroller is restored to its original settings */
void hal_prepare_boot(void) {}

void hal_flash_lock(void) {}
void hal_flash_unlock(void) {}



void do_boot(const uint32_t *app_offset)
{
    Ifx_Ssw_jumpToFunction((void (*)(void))app_offset);
}
