#!/bin/bash
# Deletes the sockets and helper scripts VS Code uses to reach the Mac. VS Code recreates
# some of them after the container starts, so this has to keep running.
set -u

while true; do
    find /tmp \( -type s -o -type f \) \( \
        -name 'vscode-ssh-auth-*.sock' \
        -o -name 'vscode-remote-containers-ipc-*.sock' \
        -o -name 'vscode-remote-containers-*.js' \
        -o -name 'vscode-ipc-*.sock' \
        -o -name 'vscode-git-*.sock' \
        \) -delete 2>/dev/null
    sleep 10
done
