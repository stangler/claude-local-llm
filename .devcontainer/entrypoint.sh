#!/bin/bash
ollama serve &
sleep 3
mkdir -p ~/.coderouter
if [ ! -f ~/.coderouter/providers.yaml ]; then
  curl -fsSL https://raw.githubusercontent.com/zephel01/CodeRouter/main/examples/providers.ollama-auto.yaml \
    -o ~/.coderouter/providers.yaml
fi
uvx --from coderouter-cli coderouter serve --port 8088 &
tail -f /dev/null