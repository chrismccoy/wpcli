#!/bin/bash

SEARCH_DIR="webapps"

set -u
set -o pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DRY_RUN="true" # Default to dry run for safety

if [[ $# -gt 0 ]]; then
  if [ "$1" == "--force" ]; then
    DRY_RUN="false"
  else
    echo -e "${RED}Error: Unknown argument '$1'${NC}"
    echo "Usage: $0 [--force]"
    exit 1
  fi
fi

if ! command -v wp &>/dev/null; then
  echo -e "${RED}Error: wp-cli is not installed or not in the system's PATH.${NC}"
  exit 1
fi

if [ ! -d "${SEARCH_DIR}" ]; then
  echo -e "${YELLOW}Warning: Search directory '${SEARCH_DIR}' does not exist. Nothing to do.${NC}"
  exit 0
fi

CURRENT_USER=$(whoami)

echo "Starting WordPress URL check as user: ${GREEN}${CURRENT_USER}${NC}"
echo "Search Directory: ${SEARCH_DIR}"

if [ "$DRY_RUN" = "true" ]; then
  echo -e "${YELLOW}DRY RUN MODE IS ENABLED. No changes will be made.${NC}"
  echo "To apply changes, run with the --force flag."
else
  echo -e "${RED}LIVE MODE IS ENABLED. Changes will be applied to the database.${NC}"
  read -p "Are you sure you want to continue? (y/N) " -n 1 -r
  echo # Move to a new line
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
  fi
fi
echo "--------------------------------------------------"

mapfile -t -d '' files_found < <(find "${SEARCH_DIR}" -name "wp-config.php" -print0)

if [ ${#files_found[@]} -eq 0 ]; then
  echo -e "${YELLOW}No 'wp-config.php' files were found.${NC}"
  exit 0
fi

get_wp_option() {
  local option_name=$1
  local wp_path=$2
  local output
  if output=$(wp option get "${option_name}" --path="${wp_path}" --skip-plugins --skip-themes 2>&1); then
    echo "${output}"
  else
    echo -e "${RED} -> WP-CLI Error trying to get '${option_name}':${NC}" >&2
    echo "${output}" | sed 's/^/    /' >&2
    echo ""
  fi
}

update_wp_option() {
  local option_name=$1
  local new_value=$2
  local current_value=$3
  local wp_path=$4
  echo " -> ${option_name}:"
  echo -e "    Current:  ${current_value}"
  echo -e "    Target:   ${GREEN}${new_value}${NC}"
  if [ "$DRY_RUN" = "true" ]; then
    echo -e "    ${YELLOW}Action: Would update (Dry Run).${NC}"
  else
    if wp option update "${option_name}" "${new_value}" --path="${wp_path}" --skip-plugins --skip-themes; then
      echo -e "    ${GREEN}Action: Successfully updated.${NC}"
    else
      echo -e "    ${RED}Action: Failed to update.${NC}"
    fi
  fi
}

sites_found=0
sites_updated=0

for config_file in "${files_found[@]}"; do
  wp_dir=$(dirname "${config_file}")
  ((sites_found++))

  echo -e "\nProcessing WordPress install at: ${YELLOW}${wp_dir}${NC}"

  current_siteurl=$(get_wp_option "siteurl" "${wp_dir}")
  current_home=$(get_wp_option "home" "${wp_dir}")

  if [ -z "$current_siteurl" ] || [ -z "$current_home" ]; then
    echo -e "${RED} -> Could not retrieve URLs for this install due to errors above. Skipping.${NC}"
    continue
  fi

  bare_domain_siteurl=$(echo "${current_siteurl}" | sed -e 's#^https\?://##' -e 's#^www\.##')
  target_siteurl="https://www.${bare_domain_siteurl}"

  bare_domain_home=$(echo "${current_home}" | sed -e 's#^https\?://##' -e 's#^www\.##')
  target_home="https://www.${bare_domain_home}"

  needs_update=false
  if [ "${current_siteurl}" != "${target_siteurl}" ]; then
    update_wp_option "siteurl" "${target_siteurl}" "${current_siteurl}" "${wp_dir}"
    needs_update=true
  else
    echo -e " -> siteurl is already correct: ${GREEN}${current_siteurl}${NC}"
  fi

  if [ "${current_home}" != "${target_home}" ]; then
    update_wp_option "home" "${target_home}" "${current_home}" "${wp_dir}"
    needs_update=true
  else
    echo -e " -> home is already correct: ${GREEN}${current_home}${NC}"
  fi

  if [ "$needs_update" = true ]; then
    ((sites_updated++))
  fi
done

echo "--------------------------------------------------"
echo -e "${GREEN}Script finished.${NC}"
echo "Processed ${sites_found} WordPress installations."
if [ "$DRY_RUN" = "true" ]; then
  echo "Would have updated ${sites_updated} sites (Dry Run)."
  echo -e "${YELLOW}To apply these changes, run the script again with the --force flag.${NC}"
else
  echo "Updated ${sites_updated} sites."
fi
