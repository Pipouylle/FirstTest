#!/usr/bin/env bash
# Compile wayland-sandbox-socket. À lancer SANS sudo, avant « sudo ./install.sh ».
set -euo pipefail
cd "$(dirname "$0")"
P=/usr/share/wayland-protocols/staging/security-context/security-context-v1.xml
wayland-scanner client-header "$P" security-context-v1-client-protocol.h
wayland-scanner private-code "$P" security-context-v1-protocol.c
gcc -O2 -Wall -o wayland-sandbox-socket wayland-sandbox-socket.c security-context-v1-protocol.c \
    $(pkg-config --cflags --libs wayland-client)
echo "compilé : $(pwd)/wayland-sandbox-socket"
