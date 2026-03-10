#!/bin/bash
# Enable iTerm2 Python API without authentication
FILE_PATH="$HOME/Library/Application Support/iTerm2/disable-automation-auth"
HEX_PATH=$(echo -n "$FILE_PATH" | xxd -p | tr -d '\n')
CONTENT="${HEX_PATH}61DF88DC-3423-4823-B725-22570E01C027"
echo "$CONTENT" | sudo tee "$FILE_PATH" > /dev/null
sudo chown root "$FILE_PATH"
echo "Done! Now quit iTerm2 (Cmd+Q) and reopen it."
