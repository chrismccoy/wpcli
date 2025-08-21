#!/bin/bash
#
#   Dry Run (Audit Mode - Safe):
#   ./wp-bulk-media-clear.sh
#
#   Live Run (Deletion Mode - Destructive):
#   ./wp-bulk-media-clear.sh --force

SEARCH_DIR="webapps"

if command -v tput &>/dev/null; then
  C_RESET=$(tput sgr0)
  C_RED=$(tput setaf 1)
  C_GREEN=$(tput setaf 2)
  C_YELLOW=$(tput setaf 3)
  C_BLUE=$(tput setaf 4)
  C_CYAN=$(tput setaf 6)
  C_BOLD=$(tput bold)
else
  C_RESET='\033[0m'
  C_RED='\033[0;31m'
  C_GREEN='\033[0;32m'
  C_YELLOW='\033[0;33m'
  C_BLUE='\033[0;34m'
  C_CYAN='\033[0;36m'
  C_BOLD='\033[1m'
fi

DRY_RUN=1
sites_processed=0
total_media_items=0

if [[ "$1" == "--force" ]]; then
  DRY_RUN=0
  echo -e "${C_RED}${C_BOLD}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo -e "!!                  🔥 LIVE RUN MODE ENABLED 🔥                  !!"
  echo -e "!! This will PERMANENTLY delete all media from found sites. !!"
  echo -e "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${C_RESET}"
  echo ""
else
  echo -e "${C_YELLOW}${C_BOLD}=============================================================="
  echo -e "==                  🔬 DRY RUN MODE (AUDIT) 🔬                  =="
  echo -e "== No files will be deleted. The script will only report   =="
  echo -e "== on the media library size for each site found.          =="
  echo -e "==============================================================${C_RESET}"
  echo ""
fi

if [ ! -d "$SEARCH_DIR" ]; then
  echo -e "${C_RED}❗ Error: Search directory '$SEARCH_DIR' not found. Exiting.${C_RESET}"
  exit 1
fi

if ! command -v wp &>/dev/null; then
  echo -e "${C_RED}❗ Error: 'wp' command not found. WP-CLI is required.${C_RESET}"
  exit 1
fi

if [ "$DRY_RUN" -eq 0 ]; then
  echo -e "${C_YELLOW}You are about to delete ALL media from every WordPress site found in the '$SEARCH_DIR' directory."
  echo -e "This action cannot be undone.${C_RESET}"
  echo -en "${C_BOLD}${C_RED}Are you absolutely sure you have a backup and want to continue? (type 'yes' to proceed): ${C_RESET}"
  read CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "\n${C_CYAN}Operation cancelled by user.${C_RESET}"
    exit 0
  fi
  echo ""
fi

echo -e "${C_CYAN}🔍 Starting scan for WordPress installations...${C_RESET}"
echo ""

while IFS= read -r -d '' wp_config_path; do
  wp_path=$(dirname "$wp_config_path")

  echo -e "${C_BLUE}--------------------------------------------------------------${C_RESET}"
  echo -e "📁 Found WordPress site at: ${C_BOLD}$wp_path${C_RESET}"

  media_count=$(wp post list --post_type=attachment --format=count --path="$wp_path" 2>/dev/null)

  if [ $? -eq 0 ]; then
    echo -e "   📊 Media items found: ${C_BOLD}$media_count${C_RESET}"
    sites_processed=$((sites_processed + 1))

    if [ "$media_count" -gt 0 ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        total_media_items=$((total_media_items + media_count))
      else
        echo -e "   ${C_YELLOW}🔥 Deleting all $media_count media items...${C_RESET}"
        wp media delete --all --yes --path="$wp_path"

        if [ $? -eq 0 ]; then
          echo -e "   ${C_GREEN}✅ Success: Media library cleared for $wp_path${C_RESET}"
          total_media_items=$((total_media_items + media_count))
        else
          echo -e "   ${C_RED}❗ Warning: wp-cli returned an error during deletion for $wp_path.${C_RESET}"
        fi
      fi
    else
      if [ "$DRY_RUN" -eq 0 ]; then
        echo -e "   ⏩ No media items to delete. Skipping."
      fi
    fi
  else
    echo -e "   ${C_RED}❗ Error: Could not get media count for this site. Skipping.${C_RESET}"
    echo -e "   ${C_YELLOW}(Check database connection or site health for $wp_path)${C_RESET}"
  fi
done < <(find "$SEARCH_DIR" -type f -name "wp-config.php" -print0)

echo ""
echo -e "${C_CYAN}${C_BOLD}==================== SCRIPT SUMMARY ====================${C_RESET}"
echo -e "Scan complete."
echo -e "Total WordPress sites processed: ${C_BOLD}$sites_processed${C_RESET}"

if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "Total media items found across all sites: ${C_BOLD}$total_media_items${C_RESET}"
  echo -e "${C_YELLOW}📝 Mode: DRY RUN (no changes were made).${C_RESET}"
else
  echo -e "${C_GREEN}Total media items successfully deleted: ${C_BOLD}$total_media_items${C_RESET}"
  echo -e "${C_GREEN}🎉 Mode: LIVE RUN (changes were permanent).${C_RESET}"
fi
echo -e "${C_CYAN}${C_BOLD}======================================================${C_RESET}"
