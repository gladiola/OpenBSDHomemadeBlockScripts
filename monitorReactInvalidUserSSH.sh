#!/bin/sh

## Remote syslog server — set these to your remote syslog host and port.
SYSLOG_HOST='your.syslog.host'
SYSLOG_PORT='514'

## Create directory to hold this work
BASEDIRECTORY='/var/monitor/monitorInvalidUserSSH/'
BASENAME='monitorInvalidUserSSH_'
COPYTIME=$(date +"%Y%m%d%H%M%S")
DIRNAME="${BASEDIRECTORY}${BASENAME}${COPYTIME}"

mkdir -p "${DIRNAME}"

## Be able to interact with a file that holds blocks for the firewall
BLOCKFILE='/etc/pf/blocks/arbitraryBlocks.txt'

## I.  Read /var/log/authlog and look for invalid users and store their IPs in a file.
##     On OpenBSD, sshd writes authentication events to /var/log/authlog.
touch "${DIRNAME}/ip.txt"
tail -n 500 /var/log/authlog \
    | grep -E "sshd.*Invalid user" \
    | grep -v "www.xxx.yyy.zzz" \
    | grep -E -o "(25[0-5]|2[0-4][0-9]|[0-1]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[0-1]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[0-1]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[0-1]?[0-9][0-9]?)" \
    | sort -u >> "${DIRNAME}/ip.txt"

## II.  Read the BLOCKFILE used by firewall and determine if any IPs discovered would be an addition
SCORE=0

while IFS= read -r ip; do
    if ! grep -q "$ip" "$BLOCKFILE"; then
        # Append the IP to the block file
        echo "${ip}" >> "$BLOCKFILE"
        SCORE=$((SCORE + 1))
        # Log the newly blocked attacker to the remote syslog server
        logger -n "$SYSLOG_HOST" -P "$SYSLOG_PORT" -p auth.warning \
            "pf-blocker: blocked SSH invalid-user attacker ${ip}"
    fi
done < "${DIRNAME}/ip.txt"

## III.  Automatically reload the BLOCKFILE text file into the pf table

if [ "$SCORE" -gt 0 ]; then
    pfctl -t arbitraryblocks -T replace -f "$BLOCKFILE"
fi

## IV. Cleanup work files.

# If nothing significant was found, then delete the work directory.
if [ "$SCORE" -eq 0 ]; then
    rm -r "${DIRNAME}"
fi
