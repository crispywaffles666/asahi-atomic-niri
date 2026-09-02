#!/usr/bin/env bash
# Keep Brew out of root and non-interactive PATHs, where it may shadow host tools.
if [[ -d /home/linuxbrew/.linuxbrew && $- == *i* && "$(/usr/bin/id -u)" != 0 ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
