#!/bin/sh

## How many hours a block stays in effect before it is automatically removed.
BLOCK_HOURS=24

## Remote syslog server — set these to your remote syslog host and port.
SYSLOG_HOST='your.syslog.host'
SYSLOG_PORT='514'

## Files shared with the block scripts
BLOCKFILE='/etc/pf/blocks/arbitraryBlocks.txt'
LEDGER='/etc/pf/blocks/blockLedger.txt'

## If the ledger does not exist yet there is nothing to expire.
if [ ! -f "$LEDGER" ]; then
    exit 0
fi

THRESHOLD=$((BLOCK_HOURS * 3600))
NOW=$(date +%s)
CHANGED=0

## Temporary files kept in the same directory as the targets so that mv is
## atomic (same filesystem).  A .tmp suffix keeps them out of pf's table load.
NEWLEDGER=$(mktemp /etc/pf/blocks/blockLedger.XXXXXXXX.tmp)
NEWBLOCKS=$(mktemp /etc/pf/blocks/arbitraryBlocks.XXXXXXXX.tmp)
EXPIREDIPS=$(mktemp /etc/pf/blocks/expiredIPs.XXXXXXXX.tmp)

cp "$BLOCKFILE" "$NEWBLOCKS"

## First pass: split ledger into expired IPs and a new ledger of remaining ones.
while IFS= read -r line; do
    ip=$(printf '%s' "$line" | awk '{print $1}')
    ts=$(printf '%s' "$line" | awk '{print $2}')
    age=$((NOW - ts))

    if [ "$age" -ge "$THRESHOLD" ]; then
        # Record for bulk removal and remote logging.
        printf '%s\n' "$ip" >> "$EXPIREDIPS"
        CHANGED=$((CHANGED + 1))
    else
        # Still within the block window: keep this entry in the new ledger.
        printf '%s\n' "$line" >> "$NEWLEDGER"
    fi
done < "$LEDGER"

## Second pass: remove all expired IPs from the block file in one grep run.
if [ "$CHANGED" -gt 0 ]; then
    grep -v -f "$EXPIREDIPS" "$NEWBLOCKS" > "${NEWBLOCKS}.filter" \
        && mv "${NEWBLOCKS}.filter" "$NEWBLOCKS"

    # Log each expired IP to the remote syslog server.
    while IFS= read -r ip; do
        logger -n "$SYSLOG_HOST" -P "$SYSLOG_PORT" -p auth.info \
            "pf-blocker: expired block for ${ip} after ${BLOCK_HOURS}h"
    done < "$EXPIREDIPS"

    ## Atomically replace the live files, then reload the pf table.
    mv "$NEWBLOCKS" "$BLOCKFILE"
    mv "$NEWLEDGER" "$LEDGER"
    pfctl -t arbitraryblocks -T replace -f "$BLOCKFILE"
fi

rm -f "$NEWLEDGER" "$NEWBLOCKS" "$EXPIREDIPS" "${NEWBLOCKS}.filter"
