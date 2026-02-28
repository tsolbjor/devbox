#!/usr/bin/env bash
set -euo pipefail

# =========================
# PARAMETERS (edit these)
# =========================

# Node.js version for nvm
NODE_VERSION="${NODE_VERSION:-20}"

# .NET SDK version
DOTNET_VERSION="${DOTNET_VERSION:-8.0}"

# Optional installs (set to "false" to skip)
INSTALL_DOTNET="${INSTALL_DOTNET:-true}"
INSTALL_NODEJS="${INSTALL_NODEJS:-true}"
INSTALL_AZURE_CLI="${INSTALL_AZURE_CLI:-true}"
INSTALL_AZURE_DEVELOPER_CLI="${INSTALL_AZURE_DEVELOPER_CLI:-true}"
INSTALL_AZCOPY="${INSTALL_AZCOPY:-true}"
INSTALL_OH_MY_ZSH="${INSTALL_OH_MY_ZSH:-true}"
INSTALL_OH_MY_POSH="${INSTALL_OH_MY_POSH:-true}"
INSTALL_7ZIP="${INSTALL_7ZIP:-true}"
INSTALL_COPILOT_CLI="${INSTALL_COPILOT_CLI:-true}"
INSTALL_POSTMAN="${INSTALL_POSTMAN:-true}"
INSTALL_JETBRAINS_TOOLBOX="${INSTALL_JETBRAINS_TOOLBOX:-true}"

# TypeScript and Azure Functions are installed via npm after Node.js
INSTALL_TYPESCRIPT="${INSTALL_TYPESCRIPT:-true}"
INSTALL_AZFUNC="${INSTALL_AZFUNC:-true}"

# =========================
# IMPLEMENTATION
# =========================

log() { printf "\n%s\n" "$*"; }

is_pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

ensure_pkg() {
  local pkg="$1"
  if is_pkg_installed "$pkg"; then
    echo "✓ apt package already installed: $pkg"
  else
    echo "→ Installing apt package: $pkg"
    sudo apt-get install -y "$pkg"
  fi
}

ensure_command() {
  command -v "$1" >/dev/null 2>&1
}

ensure_npm_global() {
  local pkg="$1"
  if npm list -g "$pkg" >/dev/null 2>&1; then
    echo "✓ npm package already installed globally: $pkg"
  else
    echo "→ Installing npm package globally: $pkg"
    npm install -g "$pkg"
  fi
}

# =========================
# RUN
# =========================

log "Updating apt metadata"
sudo apt-get update -y

# Install .NET SDK
if [[ "$INSTALL_DOTNET" == "true" ]]; then
  log "Installing .NET SDK ${DOTNET_VERSION}"
  if ensure_command dotnet; then
    echo "✓ dotnet already installed"
  else
    echo "→ Installing .NET SDK"
    # Add Microsoft package repository
    wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
    sudo dpkg -i /tmp/packages-microsoft-prod.deb
    rm /tmp/packages-microsoft-prod.deb
    sudo apt-get update -y
    ensure_pkg "dotnet-sdk-${DOTNET_VERSION}"
  fi
fi

# Install Node.js via nvm
if [[ "$INSTALL_NODEJS" == "true" ]]; then
  log "Installing Node.js via nvm"
  
  # Check if nvm is already installed
  if [[ -d "$HOME/.nvm" ]]; then
    echo "✓ nvm already installed"
    # Source nvm for this session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  else
    echo "→ Installing nvm"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    # Source nvm for this session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Add nvm to shell profile if not already there
    if ! grep -q 'NVM_DIR' "$HOME/.bashrc" 2>/dev/null; then
      echo "→ Adding nvm to .bashrc"
      cat >> "$HOME/.bashrc" << 'EOF'

# NVM configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
    fi
  fi
  
  # Install Node.js version if not already installed
  if nvm list | grep -q "v${NODE_VERSION}"; then
    echo "✓ Node.js ${NODE_VERSION} already installed via nvm"
  else
    echo "→ Installing Node.js ${NODE_VERSION} via nvm"
    nvm install "${NODE_VERSION}"
    nvm use "${NODE_VERSION}"
    nvm alias default "${NODE_VERSION}"
  fi
fi

# Install TypeScript globally via npm
if [[ "$INSTALL_TYPESCRIPT" == "true" ]] && [[ "$INSTALL_NODEJS" == "true" ]]; then
  log "Installing TypeScript"
  if ensure_command node; then
    ensure_npm_global "typescript"
  else
    echo "⚠ Node.js not available, skipping TypeScript"
  fi
fi

# Install Azure Functions Core Tools via npm
if [[ "$INSTALL_AZFUNC" == "true" ]] && [[ "$INSTALL_NODEJS" == "true" ]]; then
  log "Installing Azure Functions Core Tools"
  if ensure_command node; then
    ensure_npm_global "azure-functions-core-tools@4"
  else
    echo "⚠ Node.js not available, skipping Azure Functions Core Tools"
  fi
fi

# Install Azure CLI
if [[ "$INSTALL_AZURE_CLI" == "true" ]]; then
  log "Installing Azure CLI"
  if ensure_command az; then
    echo "✓ Azure CLI already installed"
  else
    echo "→ Installing Azure CLI"
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  fi
fi

# Install Azure Developer CLI
if [[ "$INSTALL_AZURE_DEVELOPER_CLI" == "true" ]]; then
  log "Installing Azure Developer CLI"
  if ensure_command azd; then
    echo "✓ Azure Developer CLI already installed"
  else
    echo "→ Installing Azure Developer CLI"
    curl -fsSL https://aka.ms/install-azd.sh | bash
  fi
fi

# Install azcopy
if [[ "$INSTALL_AZCOPY" == "true" ]]; then
  log "Installing azcopy"
  if ensure_command azcopy; then
    echo "✓ azcopy already installed"
  else
    echo "→ Installing azcopy"
    wget -O /tmp/azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
    tar -xzf /tmp/azcopy.tar.gz -C /tmp
    sudo cp /tmp/azcopy_linux_amd64_*/azcopy /usr/local/bin/
    sudo chmod +x /usr/local/bin/azcopy
    rm -rf /tmp/azcopy.tar.gz /tmp/azcopy_linux_amd64_*
  fi
fi

# Install oh-my-zsh
if [[ "$INSTALL_OH_MY_ZSH" == "true" ]]; then
  log "Installing oh-my-zsh"
  
  # First ensure zsh is installed
  ensure_pkg "zsh"
  
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    echo "✓ oh-my-zsh already installed"
  else
    echo "→ Installing oh-my-zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi
fi

# Install oh-my-posh
if [[ "$INSTALL_OH_MY_POSH" == "true" ]]; then
  log "Installing oh-my-posh"
  if ensure_command oh-my-posh; then
    echo "✓ oh-my-posh already installed"
  else
    echo "→ Installing oh-my-posh"
    sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
    sudo chmod +x /usr/local/bin/oh-my-posh
  fi
fi

# Install 7zip
if [[ "$INSTALL_7ZIP" == "true" ]]; then
  log "Installing 7zip"
  ensure_pkg "p7zip-full"
fi

# Install GitHub Copilot CLI
if [[ "$INSTALL_COPILOT_CLI" == "true" ]] && [[ "$INSTALL_NODEJS" == "true" ]]; then
  log "Installing GitHub Copilot CLI"
  if ensure_command node; then
    ensure_npm_global "@githubnext/github-copilot-cli"
    
    # Add copilot alias if gh-copilot-cli exists
    if ensure_command github-copilot-cli; then
      echo "✓ GitHub Copilot CLI installed"
      echo "Run: github-copilot-cli auth to authenticate"
    fi
  else
    echo "⚠ Node.js not available, skipping GitHub Copilot CLI"
  fi
fi

# Install Postman CLI
if [[ "$INSTALL_POSTMAN" == "true" ]]; then
  log "Installing Postman CLI"
  if ensure_command postman; then
    echo "✓ Postman CLI already installed"
  else
    echo "→ Installing Postman CLI"
    curl -o- "https://dl-cli.pstmn.io/install/linux64.sh" | sh
  fi
fi

# Install JetBrains Toolbox
if [[ "$INSTALL_JETBRAINS_TOOLBOX" == "true" ]]; then
  log "Installing JetBrains Toolbox"
  
  # Check if already installed
  if [[ -f "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ]]; then
    echo "✓ JetBrains Toolbox already installed"
  else
    echo "→ Installing JetBrains Toolbox"
    
    # Ensure required dependencies
    ensure_pkg "libfuse2"
    
    # Download and extract
    TOOLBOX_VERSION=$(curl -s 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' | grep -Po '"version":"\K[0-9.]+' | head -1)
    wget -O /tmp/jetbrains-toolbox.tar.gz "https://download.jetbrains.com/toolbox/jetbrains-toolbox-${TOOLBOX_VERSION}.tar.gz"
    tar -xzf /tmp/jetbrains-toolbox.tar.gz -C /tmp
    
    # Install
    mkdir -p "$HOME/.local/share/JetBrains/Toolbox/bin"
    mv /tmp/jetbrains-toolbox-*/jetbrains-toolbox "$HOME/.local/share/JetBrains/Toolbox/bin/"
    chmod +x "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
    
    # Cleanup
    rm -rf /tmp/jetbrains-toolbox.tar.gz /tmp/jetbrains-toolbox-*
    
    echo "✓ JetBrains Toolbox installed. Run: ~/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
  fi
fi

log "Done."
echo "Summary of installed tools:"
echo "  - .NET SDK: $(ensure_command dotnet && echo 'installed' || echo 'skipped')"
echo "  - Node.js: $(ensure_command node && node --version || echo 'skipped')"
echo "  - nvm: $([ -d "$HOME/.nvm" ] && echo 'installed' || echo 'skipped')"
echo "  - TypeScript: $(ensure_command tsc && tsc --version || echo 'skipped')"
echo "  - Azure Functions: $(ensure_command func && func --version || echo 'skipped')"
echo "  - Azure CLI: $(ensure_command az && echo 'installed' || echo 'skipped')"
echo "  - Azure Developer CLI: $(ensure_command azd && echo 'installed' || echo 'skipped')"
echo "  - azcopy: $(ensure_command azcopy && echo 'installed' || echo 'skipped')"
echo "  - oh-my-zsh: $([ -d "$HOME/.oh-my-zsh" ] && echo 'installed' || echo 'skipped')"
echo "  - oh-my-posh: $(ensure_command oh-my-posh && echo 'installed' || echo 'skipped')"
echo "  - 7zip: $(ensure_command 7z && echo 'installed' || echo 'skipped')"
echo "  - GitHub Copilot CLI: $(ensure_command github-copilot-cli && echo 'installed' || echo 'skipped')"
echo "  - Postman CLI: $(ensure_command postman && echo 'installed' || echo 'skipped')"
echo "  - JetBrains Toolbox: $([ -f "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ] && echo 'installed' || echo 'skipped')"
echo ""
echo "Next steps:"
echo "  - Restart your shell or run: source ~/.bashrc"
echo "  - For zsh users: source ~/.zshrc"
echo "  - Configure oh-my-posh: add 'eval \"\$(oh-my-posh init bash)\"' to ~/.bashrc"
