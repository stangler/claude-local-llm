FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update && apt-get install -y zstd curl unzip

# Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# uv (system-wide)
ENV UV_INSTALL_DIR="/usr/local/bin"
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Volta
ENV VOLTA_HOME="/usr/local/share/volta"
RUN curl -fsSL https://get.volta.sh | bash -s -- --skip-setup \
    && chown -R vscode:vscode "$VOLTA_HOME"
ENV PATH="$VOLTA_HOME/bin:$PATH"
ENV PNPM_HOME="/home/vscode/.local/share/pnpm"
ENV PATH="$PNPM_HOME/bin:$PATH"

# Node.js / pnpm / Claude Code CLI (vscodeユーザーで実行)
USER vscode
ENV SHELL=/bin/bash
RUN volta install node@26.5.0 \
    && volta install pnpm@11.13.0 \
    && pnpm setup \
    && pnpm add -g --allow-build=@anthropic-ai/claude-code @anthropic-ai/claude-code
USER root

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]