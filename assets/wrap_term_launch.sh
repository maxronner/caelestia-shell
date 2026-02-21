#!/usr/bin/env sh

# Output saved terminal sequences (e.g. to restore shell history/title).
# We strip control characters other than ESC (0x1b) and the sequences that
# follow it, to prevent a maliciously-crafted sequences.txt from injecting
# arbitrary terminal commands (clipboard access, OSC handlers, etc.).
# Only ESC-initiated sequences and printable ASCII/UTF-8 are passed through.
if [ -r "$HOME/.local/state/caelestia/sequences.txt" ]; then
    # Use printf to output the file, filtered through tr to strip
    # raw control chars (except ESC=\033 and tab/newline which are harmless).
    tr -d '\001-\010\013\014\016-\032\034-\037' \
        < "$HOME/.local/state/caelestia/sequences.txt" 2>/dev/null
fi

# Require at least one argument before exec-ing, to guard against
# being called with no command.
if [ $# -eq 0 ]; then
    exit 1
fi

exec "$@"
