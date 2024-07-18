#!/bin/bash

set -euxo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

../../keytools/sign --no-sign "../../../IDE/AURIX/test-app/TriCore Debug (GCC)/test-app.bin" $1
