/* aurix_tc3xx.c
 *
 * Copyright (C) 2014-2024 wolfSSL Inc.
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
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* wolfBoot headers */
#include "hal.h"
#include "image.h"  /* for RAMFUNCTION */
#include "loader.h" /* for wolfBoot_panic */

#include "tc3_cfg.h"

#ifdef TC3_CFG_HAVE_BOARD
#include "tc3/tc3_board.h"
#endif

#include "tc3/tc3.h"
#include "tc3/tc3_gpio.h"
#include "tc3/tc3_uart.h"
#include "tc3/tc3_flash.h"
#include "tc3/tc3_clock.h"

#include "tc3/tc3tc.h"
#include "tc3/tc3tc_isr.h"
#include "tc3/tc3tc_traps.h"

#ifdef WOLFBOOT_ENABLE_WOLFHSM_CLIENT
/* wolfHSM headers */
#include "wolfhsm/wh_error.h"
#include "wolfhsm/wh_client.h"
#include "wolfhsm/wh_transport_mem.h"

/* wolfHSM AURIX port headers */
#include "tchsm_hh_host.h"
#include "tchsm_hsmhost.h"
#include "tchsm_config.h"
#include "tchsm_common.h"
#include "hsm_ipc.h"
#endif /* WOLFBOOT_ENABLE_WOLFHSM_CLIENT */

#define FLASH_MODULE (0)
#define UNUSED_PARAMETER (0)
#define WOLFBOOT_AURIX_RESET_REASON (0x5742) /* "WB" */

/* Helper macros to gets the base address of the page, wordline, or sector that
 * contains byteAddress */
#define GET_PAGE_ADDR(addr) \
    ((uintptr_t)(addr) & ~(TC3_PFLASH_PAGE_SIZE - 1))
#define GET_WORDLINE_ADDR(addr) \
    ((uintptr_t)(addr) & ~(TC3_PFLASH_WORDLINE_SIZE - 1))
#define GET_SECTOR_ADDR(addr) ((uintptr_t)(addr) & ~(WOLFBOOT_SECTOR_SIZE - 1))

/* RAM buffer to hold the contents of an entire flash sector*/
static uint32_t sectorBuffer[WOLFBOOT_SECTOR_SIZE / sizeof(uint32_t)];

#ifdef WOLFBOOT_AURIX_GPIO_TIMING
#define LED_PROG (0)
#define LED_ERASE (1)
#define LED_READ (2)
#define LED_WOLFBOOT (5)

#ifndef SWAP_LED_POLARITY
#define LED_ON_VAL 1
#define LED_OFF_VAL 0
#else
#define LED_ON_VAL 0
#define LED_OFF_VAL 1
#endif
#define LED_ON(led) tc3_gpiopin_SetOutput(board_leds[led], LED_ON_VAL)
#define LED_OFF(led) tc3_gpiopin_SetOutput(board_leds[led], LED_OFF_VAL)
#else
#define LED_ON(led)
#define LED_OFF(led)
#endif /* WOLFBOOT_AURIX_GPIO_TIMING */


#if defined(DEBUG_UART) || defined(UART_FLASH)
/* API matches wolfBoot for UART_DEBUG */
int  uart_tx(const uint8_t c);
int  uart_rx(uint8_t* c);
void uart_init(void);
void uart_write(const char* buf, unsigned int sz);

int uart_tx(const uint8_t c)
{
    tc3_uart_Write8(board_uart, c);
    return 1;
}

int uart_rx(uint8_t* c)
{
    /* Return 1 when read is successful, 0 otherwise */
    return (tc3_uart_Read8(board_uart, c) == 0);
}

void uart_init(void)
{
    tc3_uart_Init(board_uart);
}

void uart_write(const char* buf, unsigned int sz)
{
    while (sz > 0) {
        /* If newline character is detected, send carriage return first */
        if (*buf == '\n') {
            (void)uart_tx('\r');
        }
        (void)uart_tx(*buf++);
        sz--;
    }
}
#endif /* DEBUG_UART || UART_FLASH */


/* This function is called by the bootloader at the very beginning of the
 * execution. Ideally, the implementation provided configures the clock settings
 * for the target microcontroller, to ensure that it runs at at the required
 * speed to shorten the time required for the cryptography primitives to verify
 * the firmware images*/
void hal_init(void)
{
    /* Update BTV to use RAM Trap Table */
    tc3tc_traps_InitBTV();

    /* setup ISR sub-system */
    tc3tc_isr_Init();

    /* setup clock system */
    tc3_clock_SetMax();

    /* disable external WATCHDOG on the board */
    bsp_board_wdg_Disable();

#ifdef WOLFBOOT_AURIX_GPIO_TIMING
    tc3_gpiopin_led_Init(board_leds, board_led_count, LED_OFF_VAL);
#endif /* WOLFBOOT_AURIX_GPIO_TIMING */

    LED_ON(LED_WOLFBOOT);
    LED_OFF(LED_PROG);
    LED_OFF(LED_ERASE);
    LED_OFF(LED_READ);

#ifdef DEBUG_UART
    uart_init();

    char hello_string[] = "Hello from wolfBoot for Tricore on TC3xx\n";
    uart_write(hello_string, sizeof(hello_string) - 1);
#endif
}

/* This function is called by the bootloader at a very late stage, before
 * chain-loading the firmware in the next stage. This can be used to revert all
 * the changes made to the clock settings, to ensure that the state of the
 * microcontroller is restored to its original settings */
void hal_prepare_boot(void)
{

#ifdef WOLFBOOT_AURIX_GPIO_TIMING
    tc3_gpiopin_led_Deinit(board_leds, board_led_count);
#endif /* WOLFBOOT_AURIX_GPIO_TIMING */

#ifdef DEBUG_UART
    tc3_uart_Cleanup(board_uart);
#endif

    tc3_clock_SetBoot();
    tc3tc_isr_Cleanup();
    tc3tc_traps_DeinitBTV();

    /* Undo pre-init*/
    tc3tc_UnpreInit();
}

void do_boot(const uint32_t* app_offset)
{
    LED_OFF(LED_WOLFBOOT);
    TC3TC_JMPI((uint32_t)app_offset);
}

void arch_reboot(void)
{
    tc3_Scu_TriggerSwReset(1, WOLFBOOT_AURIX_RESET_REASON);
}

/* Programs unaligned input data to flash, assuming the underlying memory is
 * erased */
int programBytesToErasedFlash(uint32_t address, const uint8_t* data, int size)
{
    uint32_t pageBuffer[TC3_PFLASH_PAGE_SIZE / sizeof(uint32_t)];
    uint32_t pageAddress;
    uint32_t offset;
    uint32_t toWrite;
    int ret = 0;

    pageAddress = address & ~(TC3_PFLASH_PAGE_SIZE - 1);
    offset      = address % TC3_PFLASH_PAGE_SIZE;

    while (size > 0) {
        /* Calculate the number of bytes to write in the current page */
        toWrite = TC3_PFLASH_PAGE_SIZE - offset;
        if (toWrite > (uint32_t)size) {
            toWrite = (uint32_t)size;
        }

        /* Fill the page buffer with the erased byte value */
        //memset(pageBuffer, FLASH_BYTE_ERASED, TC3_PFLASH_PAGE_SIZE);
        for (int i = 0; i < (int)(TC3_PFLASH_PAGE_SIZE/sizeof(uint32_t)); i++) {
            pageBuffer[i] = FLASH_BYTE_ERASED;
        }

        /* Copy the new data into the page buffer at the correct offset */
        memcpy((uint8_t*)pageBuffer + offset, data, toWrite);

        /* Write the modified page buffer back to flash */
        ret = tc3_flash_Program(pageAddress, pageBuffer, TC3_PFLASH_PAGE_SIZE);
        if (ret != 0) {
            break;
        }

        size -= toWrite;
        data += toWrite;
        address += toWrite;
        pageAddress = address & ~(TC3_PFLASH_PAGE_SIZE - 1);
        offset      = address % TC3_PFLASH_PAGE_SIZE;
    }
    return ret;
}

/*
 * This function provides an implementation of the flash write function, using
 * the target's IAP interface. address is the offset from the beginning of the
 * flash area, data is the payload to be stored in the flash using the IAP
 * interface, and len is the size of the payload. hal_flash_write should return
 * 0 upon success, or a negative value in case of failure.
 */
int hal_flash_write(uint32_t address, const uint8_t* data, int size)
{
    int      ret               = 0;
    uint32_t currentAddress    = address;
    int      remainingSize     = size;
    int      bytesWrittenTotal = 0;

    LED_ON(LED_PROG);

    /* Process the data sector by sector */
    while (remainingSize > 0) {
        uint32_t offsetInSector       = currentAddress % WOLFBOOT_SECTOR_SIZE;
        uint32_t currentSectorAddress = currentAddress - offsetInSector;
        uint32_t bytesInThisSector    = WOLFBOOT_SECTOR_SIZE - offsetInSector;

        /* Adjust bytes to write if this would overflow the current sector */
        if (bytesInThisSector > (uint32_t)remainingSize) {
            bytesInThisSector = remainingSize;
        }

        /* Check if any page within the range is not erased */
        ret = tc3_flash_BlankCheck(currentAddress, bytesInThisSector);
        if ((ret != 0) && (ret != TC3_FLASH_NOTBLANK)) {
            /* Error during blank check */
            ret = -1;
            break;
        }

        /* If a page within the range is not erased, we need to
         * read-modify-write the sector */
        if (ret == TC3_FLASH_NOTBLANK) {
            /* Read entire sector into RAM, filling in erased bytes */
            ret = ext_flash_read(currentSectorAddress, (uint8_t*)sectorBuffer,
                                 sizeof(sectorBuffer));
            if (ret != 0) {
                break;
            }
            /* Erase the entire sector */
            ret = ext_flash_erase(currentSectorAddress, WOLFBOOT_SECTOR_SIZE);
            if (ret != 0) {
                break;
            }

            /* Modify the relevant part of the RAM sector buffer */
            memcpy((uint8_t*)sectorBuffer + offsetInSector,
                   data + bytesWrittenTotal, bytesInThisSector);

            /* Program the modified sector back into flash */
            ret = tc3_flash_Program(currentSectorAddress, sectorBuffer,
                                    sizeof(sectorBuffer));
            if (ret != 0) {
                ret = -1;
                break;
            }
        }
        else {
            ret = programBytesToErasedFlash(currentAddress,
                                            data + bytesWrittenTotal,
                                            bytesInThisSector);
            if (ret != 0) {
                ret = -1;
                break;
            }
        }

        /* Update pointers and counters */
        bytesWrittenTotal += bytesInThisSector;
        currentAddress += bytesInThisSector;
        remainingSize -= bytesInThisSector;
    }

    LED_OFF(LED_PROG);

    return ret;
}

/* Called by the bootloader to erase part of the flash memory to allow
 * subsequent boots. Erase operations must be performed via the specific IAP
 * interface of the target microcontroller. address marks the start of the area
 * that the bootloader wants to erase, and len specifies the size of the area to
 * be erased. This function must take into account the geometry of the flash
 * sectors, and erase all the sectors in between. */
int hal_flash_erase(uint32_t address, int len)
{
    int ret = 0;
    LED_ON(LED_ERASE);

    /* Handle zero length case */
    if (len <= 0) {
        LED_OFF(LED_ERASE);
        return 0;
    }

    ret = tc3_flash_Erase(address, len);
    if (ret != 0) {
        /* Error during erase */
        ret = -1;
    }

    LED_OFF(LED_ERASE);
    return ret;
}


/* If the IAP interface of the flash memory of the target requires it, this
 * function is called before every write and erase operations to unlock write
 * access to the flash. On some targets, this function may be empty. */
void hal_flash_unlock(void) {}

/* If the IAP interface of the flash memory requires locking/unlocking, this
 * function restores the flash write protection by excluding write accesses.
 * This function is called by the bootloader at the end of every write and erase
 * operations. */
void hal_flash_lock(void) {}

int ext_flash_write(uintptr_t address, const uint8_t* data, int len)
{
    return hal_flash_write(address, data, len);
}

/*
 * Reads data from flash memory, first checking if the data is erased and
 * returning dummy erased byte values to prevent ECC errors
 */
// int ext_flash_read(uintptr_t address, uint8_t* data, int len)
// {
//     int ret = 0;
//     uint8_t* p = data;
//     LED_ON(LED_READ);

//     if (len <= 0) {
//         LED_OFF(LED_READ);
//         return 0;
//     }

//     /* Fill buffer with erased values */
//     //memset(data, FLASH_BYTE_ERASED, len);
//     for (int i=0; i<len; i++) {
//         *p++ = FLASH_BYTE_ERASED;
//     }

//     /* Read and squash errors. */
//     ret = tc3_flash_Read(address, data, len);
//     if ((ret != 0) && (ret != TC3_FLASH_ERROR_DSE)) {
//         /* Error reading flash */
//         ret = -1;
//     }
//     else {
//         ret = 0;
//     }

//     LED_OFF(LED_READ);

//     return ret;
// }

/*
 * Reads data from flash memory, first checking if the data is erased and
 * returning dummy erased byte values to prevent ECC errors
 */
int ext_flash_read(uintptr_t address, uint8_t* data, int len)
{
    int ret = 0;
    int bytesRead;

    bytesRead = 0;
    while (bytesRead < len) {
        uint32_t pageAddress;
        uint32_t offset;
        int      isErased;

        pageAddress = GET_PAGE_ADDR(address);
        offset      = address % TC3_PFLASH_PAGE_SIZE;
        ret         = tc3_flash_BlankCheck(pageAddress, TC3_PFLASH_PAGE_SIZE);
        if ((ret != 0) && (ret != TC3_FLASH_NOTBLANK)) {
            /* Error during blank check */
            ret = -1;
            break;
        }
        isErased = !(ret == TC3_FLASH_NOTBLANK);

        while (offset < TC3_PFLASH_PAGE_SIZE && bytesRead < len) {
            if (isErased) {
                data[bytesRead] = FLASH_BYTE_ERASED;
            }
            else {
                int ret = tc3_flash_Read(address, data+bytesRead, 1);
                if (ret != 0) {
                    break;
                }
            }
            address++;
            bytesRead++;
            offset++;
        }
    }

    LED_OFF(LED_READ);
    if (ret == TC3_FLASH_NOTBLANK) {
        ret = 0;
    }
    return ret;
}

int ext_flash_erase(uintptr_t address, int len)
{
    return hal_flash_erase(address, len);
}

void ext_flash_lock(void)
{
    hal_flash_lock();
}

void ext_flash_unlock(void)
{
    hal_flash_unlock();
}


#ifdef WOLFBOOT_ENABLE_WOLFHSM_CLIENT
static int _cancelCb(uint16_t cancelSeq);
static int _connectCb(void* context, whCommConnected connect);

/* Client configuration/contexts */
static whTransportMemClientContext tmcCtx[1] = {0};
static whTransportClientCb         tmcCb[1]  = {WH_TRANSPORT_MEM_CLIENT_CB};

/* Globally exported HAL symbols */
whClientContext hsmClientCtx = {0};
const int       hsmDevIdHash = WH_DEV_ID_DMA;
#ifdef WOLFBOOT_SIGN_ML_DSA
/* Use DMA for massive ML DSA keys/signatures, too big for shm transport */
const int hsmDevIdPubKey = WH_DEV_ID_DMA;
#else
const int hsmDevIdPubKey = WH_DEV_ID;
#endif
const int hsmKeyIdPubKey = 0xFF;
#ifdef EXT_ENCRYPT
#error "AURIX TC3xx does not support firmware encryption with wolfHSM (yet)"
const int hsmDevIdCrypt = WH_DEV_ID;
const int hsmKeyIdCrypt = 0xFF;
#endif
#ifdef WOLFBOOT_CERT_CHAIN_VERIFY
const whNvmId hsmNvmIdCertRootCA = 1;
#endif


static int _cancelCb(uint16_t cancelSeq)
{
    HSM_SHM_CORE0_CANCEL_SEQ = cancelSeq;
    (void)tchsmHhHost2Hsm_Notify(TCHSM_HOST2HSM_NOTIFY_CANCEL);
    return 0;
}

static int _connectCb(void* context, whCommConnected connect)
{
    int ret;

    switch (connect) {
        case WH_COMM_CONNECTED:
            ret = tchsmHhHost2Hsm_Notify(TCHSM_HOST2HSM_NOTIFY_CONNECT);
            break;
        case WH_COMM_DISCONNECTED:
            ret = tchsmHhHost2Hsm_Notify(TCHSM_HOST2HSM_NOTIFY_DISCONNECT);
            break;
        default:
            ret = WH_ERROR_BADARGS;
            break;
    }

    return ret;
}

int hal_hsm_init_connect(void)
{
    int    rc = 0;
    size_t i;

    /* init shared memory buffers */
    uint32_t* req = (uint32_t*)hsmShmCore0CommBuf;
    uint32_t* resp =
        (uint32_t*)hsmShmCore0CommBuf + HSM_SHM_CORE0_COMM_BUF_WORDS / 2;
    whTransportMemConfig tmcCfg[1] = {{
        .req       = req,
        .req_size  = HSM_SHM_CORE0_COMM_BUF_SIZE / 2,
        .resp      = resp,
        .resp_size = HSM_SHM_CORE0_COMM_BUF_SIZE / 2,
    }};


    /* Client configuration/contexts */
    whCommClientConfig cc_conf[1] = {{
        .transport_cb      = tmcCb,
        .transport_context = (void*)tmcCtx,
        .transport_config  = (void*)tmcCfg,
        .client_id         = 1,
        .connect_cb        = _connectCb,
    }};

    whClientConfig c_conf[1] = {{
        .comm     = cc_conf,
        .cancelCb = _cancelCb,
    }};

    rc = hsm_ipc_init();
    if (rc != WH_ERROR_OK) {
        return rc;
    }

    /* init shared memory buffers */
    for (i = 0; i < HSM_SHM_CORE0_COMM_BUF_WORDS; i++) {
        hsmShmCore0CommBuf[i] = 0;
    }

    rc = wh_Client_Init(&hsmClientCtx, c_conf);
    if (rc != WH_ERROR_OK) {
        return rc;
    }

    rc = wh_Client_CommInit(&hsmClientCtx, NULL, NULL);
    if (rc != WH_ERROR_OK) {
        return rc;
    }

    return rc;
}

int hal_hsm_disconnect(void)
{
    int rc;

    rc = wh_Client_CommClose(&hsmClientCtx);
    if (rc != 0) {
        wolfBoot_panic();
    }

    rc = wh_Client_Cleanup(&hsmClientCtx);
    if (rc != 0) {
        wolfBoot_panic();
    }

    return 0;
}


#endif /* WOLFBOOT_ENABLE_WOLFHSM_CLIENT */
