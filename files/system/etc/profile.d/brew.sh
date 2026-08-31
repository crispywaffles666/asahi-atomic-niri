#!/usr/bin/env bash
# Source brew's shellenv only for interactive, non-root shells so that system and
# brew suites sharing a binary name don't conflict (same fix as Universal Blue).
if [[ -d /home/linuxbrew/.linuxbrew && $- == *i* && "$(/usr/bin/id -u)" != 0 ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
