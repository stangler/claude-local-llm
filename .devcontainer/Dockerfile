FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update && apt-get install -y zstd curl unzip

# Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# uv (system-wide)
ENV UV_INSTALL_DIR="/usr/local/bin"
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# fnm 1.39.0 (GitHub Releaseバイナリ直取得)
ENV FNM_DIR="/usr/local/share/fnm"
RUN mkdir -p "$FNM_DIR" \
    && curl -fsSL -o /tmp/fnm.zip https://github.com/Schniz/fnm/releases/download/v1.39.0/fnm-linux.zip \
    && unzip /tmp/fnm.zip -d "$FNM_DIR" \
    && rm /tmp/fnm.zip \
    && chmod +x "$FNM_DIR/fnm"
ENV PATH="$FNM_DIR:$PATH"

# Node.js v26.5.0
RUN fnm install 26.5.0 && fnm default 26.5.0
ENV PATH="$FNM_DIR/aliases/default/bin:$PATH"

# pnpm 11.10.0
RUN npm install -g pnpm@11.10.0

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]