#!/bin/bash
# Runs as root every time the container starts, including a plain docker start. If the
# firewall fails, the container exits rather than starting open.
set -e

# Files in the container survive stop and start, so an old marker must not look like
# proof of this start. Compared with Docker's StartedAt by check-hardening.sh.
rm -f /run/entrypoint-done

/usr/local/bin/init-firewall.sh

# setsid keeps it out of reach of anything that signals this process group
setsid /usr/local/bin/socket-cleanup.sh </dev/null >/dev/null 2>&1 &

date -u +%FT%TZ >/run/entrypoint-done

exec "$@"
