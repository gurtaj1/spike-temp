# Clears the variables VS Code uses to link a shell to the Mac. Sourced by every shell,
# because VS Code re-injects some of them into new processes. An agent can undo this, so
# deleting the sockets (socket-cleanup.sh) is what removes the link.

# Must work in both bash and zsh
unset VSCODE_IPC_HOOK_CLI VSCODE_GIT_IPC_HANDLE GIT_ASKPASS VSCODE_GIT_ASKPASS_MAIN \
  VSCODE_GIT_ASKPASS_NODE VSCODE_GIT_ASKPASS_EXTRA_ARGS REMOTE_CONTAINERS_IPC \
  REMOTE_CONTAINERS_SOCKETS REMOTE_CONTAINERS_DISPLAY_SOCK WAYLAND_DISPLAY

# Empty rather than unset, so tools don't fall back to default socket paths
export SSH_AUTH_SOCK= GPG_AGENT_INFO= BROWSER=

# Make git ignore the config files VS Code writes
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/etc/agent-gitconfig

# node and agent share files through group work
umask 002
