# OpenBSDHomemadeBlockScripts

Simple IP block scripts in `/bin/sh` for OpenBSD running the pf firewall.
Each script reads `/var/log/authlog`, extracts attacker IPs, adds them to a
pf table for immediate blocking, and logs each new block to a **remote syslog
server**.

These scripts are adapted from the FreeBSD originals at
<https://github.com/gladiola/homemadeBlockScriptsPF>.

---

## Situation

`sshd` is enabled. Log entries and HIDS show that SSH is repeatedly subjected
to brute-force attacks. These scripts respond automatically with a primitive
mechanism: extract the offending IP, add it to a pf block table, reload the
table, and ship a `auth.warning` syslog message to a remote log server so
attackers are centrally recorded.

## Given

These scripts were written for OpenBSD. No extra packages are required —
`/bin/sh`, `pfctl`, and `logger` are all part of the base system.

`/etc/pf.conf` must contain a table that reads from the block file, for
example:

```
table <arbitraryblocks> persist file "/etc/pf/blocks/arbitraryBlocks.txt"
block in quick from <arbitraryblocks>
```

Create the block file, ledger file, and their directory before running the scripts:

```sh
mkdir -p /etc/pf/blocks
touch /etc/pf/blocks/arbitraryBlocks.txt
touch /etc/pf/blocks/blockLedger.txt
```

## Configuration

At the top of each script, set the two remote-syslog variables to match your
environment:

```sh
SYSLOG_HOST='your.syslog.host'   # hostname or IP of the remote syslog server
SYSLOG_PORT='514'                # UDP port (514 is the standard syslog port)
```

Each newly blocked IP is sent to that server with priority `auth.warning`:

```
pf-blocker: blocked SSH invalid-user attacker 198.51.100.42
```

The messages are sent with OpenBSD's built-in `logger(1)` using the
`-n <host>` flag. Ensure the remote syslog server accepts UDP messages from
this host.

At the top of `expireBlocks.sh`, set how long a block stays in effect:

```sh
BLOCK_HOURS=24   # remove the block after this many hours
```

## Actions

The scripts inspect `/var/log/authlog` (OpenBSD's authentication log):

| Script | Log pattern matched |
|--------|---------------------|
| `monitorReactInvalidUserSSH.sh` | `sshd.*Invalid user` |
| `monitorReactReceivedDisconnectFromSSH.sh` | `sshd.*Received disconnect from` |
| `expireBlocks.sh` | *(reads the block ledger — no log pattern)* |

### Block ledger

Each time a block script adds a new IP it also appends a line to the **block
ledger**:

```
/etc/pf/blocks/blockLedger.txt
```

Each line has the format `IP EPOCH_SECONDS`, for example:

```
198.51.100.42 1745765662
```

`expireBlocks.sh` reads this ledger, computes how long ago each IP was
blocked, and removes any entry that is older than `BLOCK_HOURS`.  When at
least one block is removed the live block file is updated and the pf table
is reloaded automatically.  Each removal is also logged to the remote syslog
server at `auth.info` priority:

```
pf-blocker: expired block for 198.51.100.42 after 24h
```

Working files are kept under subdirectories of `/var/monitor/` and are
removed automatically when no new IPs are found.

Create the working-file base directory before running:

```sh
mkdir -p /var/monitor/monitorInvalidUserSSH
mkdir -p /var/monitor/monitorReactReceivedDisconnectFromSSH
```

Make the scripts executable and run them as root (required for `pfctl`):

```sh
chmod +x monitorReactInvalidUserSSH.sh monitorReactReceivedDisconnectFromSSH.sh expireBlocks.sh
```

## Cronjob

Add entries to root's crontab (`crontab -e`) to run the scripts periodically,
for example every 5 minutes for blocking and every hour for expiry:

```
*/5 * * * * /usr/local/sbin/monitorReactInvalidUserSSH.sh
*/5 * * * * /usr/local/sbin/monitorReactReceivedDisconnectFromSSH.sh
0   * * * * /usr/local/sbin/expireBlocks.sh
```

The expiry interval does not need to match `BLOCK_HOURS` exactly — the script
compares the actual elapsed seconds for each entry against the threshold, so
running it hourly is precise enough for any `BLOCK_HOURS` setting.

## Hazards

These scripts are primitive and limited in their decision making. They are
less than 60 lines long. Each script contains a `grep -v www.xxx.yyy.zzz`
line. Replace `www.xxx.yyy.zzz` with a trusted IP you never want to block
(e.g. your own management address). Read the scripts carefully before
deploying them.

Over time the block table will grow proportionally to the attack rate and
`BLOCK_HOURS`.  With `expireBlocks.sh` running on a cron schedule, old blocks
are pruned automatically, so manual intervention is only needed if you want to
release a specific IP sooner than the configured expiry time.

OpenBSD ships with `sshguard` available in packages and its own `pf` log
analysis tools; these scripts are a lightweight alternative for environments
where simplicity is preferred over sophistication.