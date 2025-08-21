#!/bin/bash

# Moves pending comments to the trash and empties the trash for each install

# The base directory where your WordPress sites are located.
BASE_DIR="/home/chris/webapps"

set -e
set -u
set -o pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

if ! command -v wp &>/dev/null; then
  echo -e "${YELLOW}Error: wp-cli is not installed or not in the system's PATH.${NC}"
  echo "Please install wp-cli to continue. See: https://wp-cli.org/"
  exit 1
fi

if [ ! -d "$BASE_DIR" ]; then
  echo -e "${YELLOW}Error: Base directory '${BASE_DIR}' not found.${NC}"
  exit 1
fi

echo -e "${CYAN}Starting WordPress comment cleanup process in '${BASE_DIR}'...${NC}"
echo "--------------------------------------------------------"

find "$BASE_DIR" -maxdepth 2 -type f -name "wp-config.php" -print0 | while IFS= read -r -d '' config_file; do
  wp_dir=$(dirname "$config_file")

  echo -e "\n${CYAN}Processing WordPress install at: ${wp_dir}${NC}"

  pending_ids=$(wp comment list --status=hold --format=ids --path="$wp_dir")

  if [ -n "$pending_ids" ]; then
    echo "Found pending comments. Moving to trash..."
    wp comment delete $pending_ids --path="$wp_dir" --force
    echo -e "${GREEN}Successfully moved pending comments to trash.${NC}"
  else
    echo "No pending comments found."
  fi

done

echo "--------------------------------------------------------"
echo -e "${GREEN}All WordPress installations have been processed.${NC}"
