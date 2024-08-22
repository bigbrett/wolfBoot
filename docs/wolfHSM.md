- TODO:

- In wolfHSM server, remove `#if 0` for ECC der public key input from cache, pending above
```
diff --git a/src/wh_server_crypto.c b/src/wh_server_crypto.c
index 8b86c4b..aab3033 100644
--- a/src/wh_server_crypto.c
+++ b/src/wh_server_crypto.c
@@ -434,6 +434,7 @@ static int hsmLoadKeyEcc(whServerContext* server, ecc_key* key, uint16_t keyId,
         }
     }
     /* decode the key */
+    #if 1
     if (ret >= 0) {
         /* determine which buffers should be set by size, wc_ecc_import_unsigned
          * will set the key type accordingly */
@@ -454,6 +455,12 @@ static int hsmLoadKeyEcc(whServerContext* server, ecc_key* key, uint16_t keyId,
         }
         ret = wc_ecc_import_unsigned(key, qxBuf, qyBuf, qdBuf, curveId);
     }
+    #else
+    if (ret >=0) {
+        size_t idx;
+        ret = wc_EccPublicKeyDecode(cacheBuf, (word32*)&idx, key, cacheMeta->len);
+    }
+    #endif
     return ret;
 }
```

- Add keystore file CLI args to server so it can load/cache keys from a file on startup so client can refer to them by keyId
- Document missing ECC export functions in wolfCrypt
