/* app_aurix_tc4xx.c
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

/* wolfBoot test application for the AURIX TC4xx host domain. Chain-loaded
 * by wolfBoot on TriCore CPU0 (never entered in hypervisor state, never
 * booted from a BMHD; the startup software is built accordingly - see the
 * TC4 block in test-app/Makefile). Runs bare-metal with interrupts
 * disabled and CPU1..5 in reset, so the libwolfboot flash accesses need
 * no fetch-stall protection: everything that could fetch from the flash
 * banks being touched executes from PSPR (.ramcode) or stays blocked in
 * the call. */

#ifdef TARGET_aurix_tc4xx

#include <stdint.h>
#include "target.h"
#include "printf.h"
#include "hal.h"
#include "wolfboot/wolfboot.h"

#define BASE_FW_VERSION 1

/* The SSW's C++-init hook calls _init, normally supplied by crti.o;
 * the test app links with -nostartfiles, so provide the empty stub. */
void _init(void)
{
}

/* Referenced by the wolfBoot flash HAL linked into this image. A flash
 * driver fault has no recovery path here; hang for the debugger. */
void wolfBoot_panic(void)
{
    while (1) {
        __asm volatile("nop");
    }
}

/* Entered by the iLLD startup software after C runtime init. Watchdogs
 * are already disabled (wolfBoot's hal_init did that and nothing
 * re-enables them across do_boot). */
void core0_main(void)
{
#ifdef DEBUG_UART
    uart_init();
#endif
    wolfBoot_printf("TC4xx Test Application\n");
    wolfBoot_printf("Version: %d\n", wolfBoot_current_firmware_version());

    if (wolfBoot_current_firmware_version() <= BASE_FW_VERSION) {
        /* We are booting into the base firmware, so stage the update */
        wolfBoot_update_trigger();
    }
    else {
        /* we are booting into the updated firmware so acknowledge the
         * update (to prevent rollback) */
        wolfBoot_success();
    }

    /* Main application loop */
    while (1) {
        /* spin forever */
    }
}

#endif /* TARGET_aurix_tc4xx */
