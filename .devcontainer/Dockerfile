FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# 依存追加
RUN apt-get update && apt-get install -y zstd curl \
    && rm -rf /var/lib/apt/lists/*

# Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# uv (全ユーザー共通PATHへ配置)
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

# Node (Claude Code CLI用)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs
RUN npm install -g @anthropic-ai/claude-code

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh