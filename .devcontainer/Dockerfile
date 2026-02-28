# Use Ubuntu 22.04 LTS as the base image
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Build arguments for git configuration
ARG GIT_NAME="Developer"
ARG GIT_EMAIL="developer@example.com"

# Install essential development packages
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    git \
    gnupg \
    lsb-release \
    build-essential \
    gcc \
    make \
    jq \
    ripgrep \
    fd-find \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Create fd symlink (fd-find is called fdfind on Ubuntu)
RUN mkdir -p /usr/local/bin && ln -sf $(which fdfind) /usr/local/bin/fd

# Configure Git defaults
RUN git config --global user.name "${GIT_NAME}" \
    && git config --global user.email "${GIT_EMAIL}" \
    && git config --global init.defaultBranch main \
    && git config --global core.autocrlf input

# Create code directory
RUN mkdir -p /home/vscode/code && chown -R vscode:vscode /home/vscode/code

# Set working directory
WORKDIR /home/vscode/code
