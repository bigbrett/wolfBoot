#!/bin/bash

set -euxo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

../../keytools/sign --rsa4096 --sha256 "../../../IDE/AURIX/test-app/TriCore Debug (GCC)/test-app.bin" ../../../priv.der $1
