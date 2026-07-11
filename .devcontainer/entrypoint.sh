#!/bin/bash
ollama serve > /tmp/ollama.log 2>&1 &
exec "$@"
