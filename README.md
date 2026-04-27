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

Create the block file and its directory before running the scripts:

```sh
mkdir -p /etc/pf/blocks
touch /etc/pf/blocks/arbitraryBlocks.txt
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

## Actions

The scripts inspect `/var/log/authlog` (OpenBSD's authentication log):

| Script | Log pattern matched |
|--------|---------------------|
| `monitorReactInvalidUserSSH.sh` | `sshd.*Invalid user` |
| `monitorReactReceivedDisconnectFromSSH.sh` | `sshd.*Received disconnect from` |

Working files are kept under subdirectories of `/var/monitor/` and are
removed automatically when no new IPs are found.

Create the working-file base directory before running:

```sh
mkdir -p /var/monitor/monitorInvalidUserSSH
mkdir -p /var/monitor/monitorReactReceivedDisconnectFromSSH
```

Make the scripts executable and run them as root (required for `pfctl`):

```sh
chmod +x monitorReactInvalidUserSSH.sh monitorReactReceivedDisconnectFromSSH.sh
```

## Cronjob

Add entries to root's crontab (`crontab -e`) to run the scripts periodically,
for example every 5 minutes:

```
*/5 * * * * /usr/local/sbin/monitorReactInvalidUserSSH.sh
*/5 * * * * /usr/local/sbin/monitorReactReceivedDisconnectFromSSH.sh
```

## Hazards

These scripts are primitive and limited in their decision making. They are
less than 60 lines long. Each script contains a `grep -v www.xxx.yyy.zzz`
line. Replace `www.xxx.yyy.zzz` with a trusted IP you never want to block
(e.g. your own management address). Read the scripts carefully before
deploying them.

Over time the block table will grow, which can have a minor impact on pf
performance. Periodic review and pruning of `arbitraryBlocks.txt` is
recommended.

OpenBSD ships with `sshguard` available in packages and its own `pf` log
analysis tools; these scripts are a lightweight alternative for environments
where simplicity is preferred over sophistication.