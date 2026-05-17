#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="codex-app-extension"
CONFIG_DIR="$HOME/.codex-app-extension"
CONFIG_PATH="$CONFIG_DIR/config.json"
BACKUP_PATH="$CONFIG_DIR/config.json.bak"
AUTHOR_CONFIG_PATH="$SCRIPT_DIR/data/author-config.json"

if [[ ! -f "$AUTHOR_CONFIG_PATH" ]]; then
  echo "[$APP_NAME] Author config not found: $AUTHOR_CONFIG_PATH" >&2
  exit 1
fi

echo "[$APP_NAME] This will follow the author config:"
echo "[$APP_NAME]   source: $AUTHOR_CONFIG_PATH"
echo "[$APP_NAME]   target: $CONFIG_PATH"
echo "[$APP_NAME] Your current config will be backed up to:"
echo "[$APP_NAME]   $BACKUP_PATH"
read -r -p "[$APP_NAME] Continue? Type y/yes to confirm: " answer
normalized_answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"

case "$normalized_answer" in
  y|yes)
    ;;
  *)
    echo "[$APP_NAME] Cancelled."
    exit 1
    ;;
esac

mkdir -p "$CONFIG_DIR"

if [[ -e "$CONFIG_PATH" || -L "$CONFIG_PATH" ]]; then
  if ! cp "$CONFIG_PATH" "$BACKUP_PATH"; then
    echo "[$APP_NAME] Failed to back up current config." >&2
    exit 1
  fi
  echo "[$APP_NAME] Backed up current config to $BACKUP_PATH."
fi

rm -f "$CONFIG_PATH"
ln -s "$AUTHOR_CONFIG_PATH" "$CONFIG_PATH"

echo "[$APP_NAME] Now following author config."
echo "[$APP_NAME] Config: $CONFIG_PATH -> $AUTHOR_CONFIG_PATH"
