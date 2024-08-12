#!/bin/bash

set -euxo pipefail

(cd ../../../ && tools/keytools/keygen --ecc256 -g priv.der)
