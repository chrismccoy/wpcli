#!/bin/bash

CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_PATH="$HOME/webapps"

SEARCH_PATH="${1:-$DEFAULT_PATH}"

if [ ! -d "$SEARCH_PATH" ]; then
  echo -e "${RED}Error: The specified directory does not exist: '$SEARCH_PATH'${NC}"
  echo -e "Usage: $0 [PATH]"
  exit 1
fi

echo -e "${CYAN}Starting WordPress Media File Audit in '${YELLOW}$SEARCH_PATH${NC}'...${NC}"
echo "-----------------------------------------------------------------"

total_media_files=0

declare -A site_summary

while IFS= read -r -d '' wp_config_path; do
  wp_dir=$(dirname "$wp_config_path")

  site_name=$(basename "$wp_dir")

  echo -e -n "-> Checking '${YELLOW}$site_name${NC}'..."

  media_count=$(
    (cd "$wp_dir" && wp post list --post_type=attachment --format=count) 2> /dev/null
  )

  if [[ "$media_count" =~ ^[0-9]+$ ]]; then
    echo -e " ${GREEN}Found $media_count files.${NC}"
    total_media_files=$((total_media_files + media_count))
    site_summary["$site_name"]=$media_count
  else
    echo -e " ${RED}SKIPPED (Not a valid WP-CLI installation or database error).${NC}"
  fi

done < <(find "$SEARCH_PATH" -type f -name "wp-config.php" -print0 | sort -z)

echo
echo -e "${CYAN}==================== Audit Summary ====================${NC}"

if [ ${#site_summary[@]} -eq 0 ]; then
  echo -e "${YELLOW}No valid WordPress installations were found in '$SEARCH_PATH'.${NC}"
else
  echo "Media files per site (sorted alphabetically):"
  printf "%s\n" "${!site_summary[@]}" | sort | while read -r site; do
    printf "  - ${BLUE}%-35s${NC}: ${GREEN}%s${NC}\n" "$site" "${site_summary[$site]}"
  done
  echo "-----------------------------------------------------"
  printf "${YELLOW}Total media files across %d sites: %s${NC}\n" "${#site_summary[@]}" "$total_media_files"
fi

echo -e "${CYAN}=====================================================${NC}"
