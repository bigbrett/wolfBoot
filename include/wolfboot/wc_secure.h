/* wc_secure.h
 *
 * The wolfBoot library version
 *
 * Copyright (C) 2021 wolfSSL Inc.
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
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA
 */

#ifndef WOLFBOOT_SECURE_CALLS_INCLUDED
#define WOLFBOOT_SECURE_CALLS_INCLUDED

#include <stdint.h>

/* Data types shared between wolfBoot and the non-secure application */

#ifdef WOLFCRYPT_SECURE_MODE
struct wcs_sign_call_params
{
    int slot_id;
    const uint8_t *in;
    uint32_t inSz;
    uint8_t *out;
    uint32_t outSz;
};

struct wcs_verify_call_params
{
    int slot_id;
    const uint8_t *sig;
    uint32_t sigSz;
    uint8_t *hash;
    uint32_t hashSz;
    int *verify_res;
};
#endif


#ifdef WOLFBOOT_SECURE_CALLS


/* Secure calls prototypes for the non-secure world */

/* RAW file read */
int __attribute__((cmse_nonsecure_entry)) wcs_slot_read(int slot_id,
        uint8_t *buffer, uint32_t len);



/* ECC */
int __attribute__((cmse_nonsecure_entry)) wcs_ecc_import_public(int ecc_curve,
        uint8_t *pubkey, uint32_t key_size);

int __attribute__((cmse_nonsecure_entry)) wcs_ecc_keygen(uint32_t key_size,
        int ecc_curve);

int __attribute__((cmse_nonsecure_entry)) wcs_ecc_getpublic(int slot_id,
        uint8_t *pubkey, uint32_t *pubkeySz);

int __attribute__((cmse_nonsecure_entry)) wcs_ecdh_shared(int privkey_slot_id,
        int pubkey_slot_id, uint32_t outlen);

/*  ECC Calls with wrapper for arguments (ABI only allows 4 arguments) */
int __attribute__((cmse_nonsecure_entry))
    wcs_ecc_sign_call(struct wcs_sign_call_params *p);
int __attribute__((cmse_nonsecure_entry))
    wcs_ecc_verify_call(struct wcs_verify_call_params *p);

/* RNG */
int __attribute__((cmse_nonsecure_entry)) wcs_get_random(uint8_t *rand,
        uint32_t size);

/* exposed API for sign/verify with all needed arguments */
static inline int wcs_ecc_sign(int slot_id, const uint8_t *in,
        uint32_t inSz, uint8_t *out, uint32_t outSz)
{
    struct wcs_sign_call_params p;
    p.slot_id = slot_id;
    p.in = in;
    p.inSz = inSz;
    p.out = out;
    p.outSz = outSz;
    return wcs_ecc_sign_call(&p);
}

static inline int wcs_ecc_verify(int slot_id, const uint8_t *sig,
        uint32_t sigSz, uint8_t *hash, uint32_t hashSz, int *verify_res)
{
    struct wcs_verify_call_params p;
    p.slot_id = slot_id;
    p.sig = sig;
    p.sigSz = sigSz;
    p.hash = hash;
    p.hashSz = hashSz;
    p.verify_res = verify_res;
    return wcs_ecc_verify_call(&p);
}

#endif /* WOLFBOOT_SECURE_CALLS */

#endif
