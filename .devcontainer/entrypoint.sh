#!/bin/bash
# Runs as root every time the container starts, including a plain docker start. If the
# firewall fails, the container exits rather than starting open.
set -e

# Files in the container survive stop and start, so an old marker must not look like
# proof of this start. Compared with Docker's StartedAt by check-hardening.sh.
rm -f /run/entrypoint-done

/usr/local/bin/init-firewall.sh

# Volumes can start with the wrong owner, so set them here. Top folders only: agents can
# write inside the workspace, and root shouldn't walk a tree they control.
chown node:node /commandhistory /home/node/.claude
chmod 700 /commandhistory /home/node/.claude
chown agent:agent /home/agent/.claude
chmod 700 /home/agent/.claude

# New files stay in group work and group-writable, whatever umask the tool has
chown node:work /workspace
chmod 2775 /workspace
setfacl -d -m u::rwx,g::rwx,o::rx /workspace

# setsid keeps it out of reach of anything that signals this process group
setsid /usr/local/bin/socket-cleanup.sh </dev/null >/dev/null 2>&1 &

date -u +%FT%TZ >/run/entrypoint-done

exec "$@"
