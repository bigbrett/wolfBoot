#!/bin/bash
#
# Sunnyday update test with cryptocb dispatch verification.
# stdout is redirected to sim_cryptocb.log which contains both
# wc_CryptoCb_InfoString output ("Crypto CB: ...") and the test-app
# version number. Version is extracted by filtering out crypto lines.
#
# Usage: sim-cryptocb-sunnyday-update.sh <expected_hash> [expected_pk]
# Example: sim-cryptocb-sunnyday-update.sh "SHA-256" "RSA"
#

LOGFILE="sim_cryptocb.log"

if [ $# -lt 1 ]; then
    echo "usage: $0 <expected_hash> [expected_pk]"
    exit 1
fi

EXPECTED_HASH=$1
EXPECTED_PK=${2:-}

# First boot: update_trigger + get_version (stdout -> log)
./wolfboot.elf update_trigger get_version > $LOGFILE 2>/dev/null
V=$(grep -v "^Crypto CB:" $LOGFILE | tail -1)
if [ "x$V" != "x1" ]; then
    echo "Failed first boot with update_trigger (V: $V)"
    cat $LOGFILE
    exit 1
fi

# Second boot: success + get_version (stdout -> log)
./wolfboot.elf success get_version > $LOGFILE 2>/dev/null
V=$(grep -v "^Crypto CB:" $LOGFILE | tail -1)
if [ "x$V" != "x2" ]; then
    echo "Failed update (V: $V)"
    cat $LOGFILE
    exit 1
fi

# Verify crypto callback log entries
if ! grep -q "Crypto CB: Hash $EXPECTED_HASH" $LOGFILE; then
    echo "Error: expected 'Crypto CB: Hash $EXPECTED_HASH' not found"
    cat $LOGFILE
    exit 1
fi
echo "Verified: Hash $EXPECTED_HASH dispatched through cryptocb"

# Optional PK verification (skip for ECC/PQC which bypass cryptocb PK dispatch)
if [ -n "$EXPECTED_PK" ]; then
    if ! grep -q "Crypto CB: PK $EXPECTED_PK" $LOGFILE; then
        echo "Error: expected 'Crypto CB: PK $EXPECTED_PK' not found"
        cat $LOGFILE
        exit 1
    fi
    echo "Verified: PK $EXPECTED_PK dispatched through cryptocb"
fi

echo Test successful.
exit 0
