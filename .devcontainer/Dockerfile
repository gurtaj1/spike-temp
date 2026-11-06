FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  acl \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Global npm packages are installed as root, so node can't modify them
RUN mkdir -p /usr/local/share/npm-global

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Copy and set up the firewall script and the entrypoint that runs it
COPY init-firewall.sh entrypoint.sh /usr/local/bin/
USER root
RUN chmod 755 /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Agents run as their own user, so they can't reach VS Code's processes or sockets.
# agent isn't in node's group. work is the group they share files through.
RUN groupadd work && \
  useradd -m -u 1001 agent && \
  usermod -aG work node && \
  usermod -aG work agent && \
  mkdir -p /home/agent/.claude && \
  chown agent:agent /home/agent/.claude && \
  sed -i '1i . /etc/harden-env.sh' /home/agent/.bashrc && \
  touch /home/agent/.zshrc && \
  chown agent:agent /home/agent/.zshrc && \
  chmod 700 /home/agent /home/agent/.claude /home/node

# Remove VS Code's links to the Mac. Root-owned, so node can't change these files.
# Agents' commands run in zsh, and /etc/zsh/zshenv is read by every zsh. BASH_ENV (below)
# covers non-interactive bash, and .bashrc covers interactive bash.
COPY harden-env.sh /etc/harden-env.sh
COPY agent-gitconfig /etc/agent-gitconfig
COPY socket-cleanup.sh /usr/local/bin/socket-cleanup.sh
RUN chmod 644 /etc/harden-env.sh /etc/agent-gitconfig && \
  chmod 755 /usr/local/bin/socket-cleanup.sh && \
  echo ". /etc/harden-env.sh" >> /etc/zsh/zshenv && \
  sed -i '1i . /etc/harden-env.sh' /home/node/.bashrc

# The prompt's git element would run git in the workspace, as node, on every prompt
RUN sed -i 's/^POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(user dir vcs status)/POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(user dir status)/' /home/node/.zshrc && \
  ! grep -q 'vcs' /home/node/.zshrc

# Install Claude and Bun as root
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
ARG BUN_VERSION=1.4.4
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash -s "bun-v${BUN_VERSION}"
ENV BASH_ENV=/etc/harden-env.sh
USER node

# containerUser in devcontainer.json runs this as root. Run as node, the firewall can't
# start, so the container exits rather than starting open.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
