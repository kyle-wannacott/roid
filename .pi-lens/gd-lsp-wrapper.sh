#!/usr/bin/env bash
# GDScript LSP wrapper for pi-lens
# 1. Ensures Godot headless editor is running (port 6005)
# 2. Bridges stdio <-> Godot's TCP LSP

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure Godot daemon is running
"$DIR/godot-lsp-daemon.sh" ensure

# Run the stdio-to-TCP bridge
exec npx -y godot-lsp-stdio-bridge
