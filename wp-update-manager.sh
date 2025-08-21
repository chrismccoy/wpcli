#!/bin/bash

SEARCH_DIR="$HOME/webapps"

COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'

CHECK_CORE=false
CHECK_PLUGINS=false
CHECK_THEMES=false
FORCE_UPDATE=false

TOTAL_SITES_SCANNED=0
TOTAL_CORE_UPDATES=0
TOTAL_PLUGIN_UPDATES=0
TOTAL_THEME_UPDATES=0

declare -A SITES_PLUGINS_MAP
declare -A SITES_THEMES_MAP

SITES_WITH_CORE_UPDATES=()

print_header() {
  printf "\n${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}\n"
  printf "${COLOR_BOLD}${COLOR_BLUE}  %s\n" "$1"
  printf "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}\n"
}

print_usage() {
  echo "Usage: $0 [search_directory] [-c] [-p] [-t] [-f]"
  echo
  echo "  Checks and optionally applies updates for all WordPress installations."
  echo
  echo "  Arguments:"
  echo "    search_directory   Optional. The directory to search in. Defaults to '~/webapps'."
  echo
  echo "  Options:"
  echo "    -c                 Check for WordPress core updates."
  echo "    -p                 Check for plugin updates."
  echo "    -t                 Check for theme updates."
  echo "    -f                 ${COLOR_BOLD}Force apply all found updates. USE WITH EXTREME CAUTION.${COLOR_RESET}"
  echo
  echo "  Example: $0 -pf  (Finds and applies all plugin updates in the default directory)"
}

if [ $# -eq 0 ]; then
  print_usage
  exit 0
fi

if [[ -d "$1" && ! "$1" =~ ^- ]]; then
  SEARCH_DIR="$1"
  shift
fi

while getopts ":cptf" opt; do
  case ${opt} in
    c) CHECK_CORE=true ;;
    p) CHECK_PLUGINS=true ;;
    t) CHECK_THEMES=true ;;
    f) FORCE_UPDATE=true ;;
    \?)
      echo "Invalid Option: -$OPTARG" 1>&2
      print_usage
      exit 1
      ;;
  esac
done

if ! $CHECK_CORE && ! $CHECK_PLUGINS && ! $CHECK_THEMES; then
  printf "${COLOR_YELLOW}No specific checks requested. Defaulting to check ALL updates.${COLOR_RESET}\n"
  CHECK_CORE=true
  CHECK_PLUGINS=true
  CHECK_THEMES=true
fi

if ! command -v wp &>/dev/null; then
  printf "${COLOR_RED}Error: 'wp-cli' is not installed or not in your PATH. Aborting.${COLOR_RESET}\n"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  printf "${COLOR_RED}Error: 'jq' is not installed or not in your PATH. Aborting.${COLOR_RESET}\n"
  exit 1
fi

if [ ! -d "$SEARCH_DIR" ]; then
    printf "${COLOR_RED}Error: Search directory '${SEARCH_DIR}' not found. Aborting.${COLOR_RESET}\n"
    exit 1
fi

if [ "$FORCE_UPDATE" = true ]; then
  print_header "!! WARNING: FORCE UPDATE MODE ENABLED !!"
  printf "${COLOR_BOLD}${COLOR_RED}This script will perform LIVE updates on all found WordPress sites.${COLOR_RESET}\n"
  printf "${COLOR_YELLOW}It is HIGHLY recommended to have backups before proceeding.${COLOR_RESET}\n\n"
  read -p "Are you sure you want to continue? (type 'yes' to proceed): " confirm
  if [[ "$confirm" != "yes" ]]; then
    printf "\n${COLOR_GREEN}Aborting. No changes were made.${COLOR_RESET}\n"
    exit 0
  fi
fi

print_header "WordPress Update Scan Initialized"

printf "Searching for WordPress installs in: ${COLOR_CYAN}${SEARCH_DIR}${COLOR_RESET}\n"
printf "Checks to perform: Core (${CHECK_CORE}), Plugins (${CHECK_PLUGINS}), Themes (${CHECK_THEMES})\n"

if [ "$FORCE_UPDATE" = true ]; then
  printf "Update Mode: ${COLOR_BOLD}${COLOR_RED}ENABLED${COLOR_RESET}\n"
fi

while IFS= read -r -d '' config_file; do
  wp_path=$(dirname "$config_file")
  ((TOTAL_SITES_SCANNED++))

  printf "\n${COLOR_YELLOW}🔎 Checking Site #${TOTAL_SITES_SCANNED}: ${COLOR_CYAN}${wp_path}${COLOR_RESET}\n"
  printf -- "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - \n"

  if [ "$CHECK_CORE" = true ]; then
    core_updates=$(wp core check-update --path="$wp_path" --format=json 2>/dev/null | jq 'length')
    if [ "$core_updates" -gt 0 ]; then
      printf "  ${COLOR_RED}Core:    1 update available!${COLOR_RESET}\n"
      wp core check-update --path="$wp_path" --fields=version,update_version
      ((TOTAL_CORE_UPDATES++))
      SITES_WITH_CORE_UPDATES+=("$wp_path")
      if [ "$FORCE_UPDATE" = true ]; then
        printf "  ${COLOR_YELLOW}↳ Applying core update...${COLOR_RESET}\n"
        wp core update --path="$wp_path"
        if [ $? -eq 0 ]; then printf "  ${COLOR_GREEN}  ✔ Success: Core updated.${COLOR_RESET}\n"; else printf "  ${COLOR_RED}  ✘ Failure: Core update command failed.${COLOR_RESET}\n"; fi
      fi
    else
      printf "  ${COLOR_GREEN}Core:    Up to date.${COLOR_RESET}\n"
    fi
  fi

  if [ "$CHECK_PLUGINS" = true ]; then
    plugin_updates_json=$(wp plugin list --update=available --path="$wp_path" --format=json 2>/dev/null)
    plugin_updates=$(echo "$plugin_updates_json" | jq 'length')
    if [ "$plugin_updates" -gt 0 ]; then
      printf "  ${COLOR_RED}Plugins: ${plugin_updates} update(s) available!${COLOR_RESET}\n"
      wp plugin list --update=available --path="$wp_path" --fields=name,version,update_version | sed 's/^/    /'
      ((TOTAL_PLUGIN_UPDATES += plugin_updates))
      plugin_details=$(echo "$plugin_updates_json" | jq -r '.[] | "    - \(.name) (\(.version) -> \(.update_version))"')
      SITES_PLUGINS_MAP["$wp_path"]="$plugin_details"
      if [ "$FORCE_UPDATE" = true ]; then
        printf "  ${COLOR_YELLOW}↳ Applying ${plugin_updates} plugin update(s)...${COLOR_RESET}\n"
        wp plugin update --all --path="$wp_path"
        if [ $? -eq 0 ]; then printf "  ${COLOR_GREEN}  ✔ Success: Plugins updated.${COLOR_RESET}\n"; else printf "  ${COLOR_RED}  ✘ Failure: Plugin update command failed.${COLOR_RESET}\n"; fi
      fi
    else
      printf "  ${COLOR_GREEN}Plugins: All up to date.${COLOR_RESET}\n"
    fi
  fi

  if [ "$CHECK_THEMES" = true ]; then
    theme_updates_json=$(wp theme list --update=available --path="$wp_path" --format=json 2>/dev/null)
    theme_updates=$(echo "$theme_updates_json" | jq 'length')
    if [ "$theme_updates" -gt 0 ]; then
      printf "  ${COLOR_RED}Themes:  ${theme_updates} update(s) available!${COLOR_RESET}\n"
      wp theme list --update=available --path="$wp_path" --fields=name,version,update_version | sed 's/^/    /'
      ((TOTAL_THEME_UPDATES += theme_updates))
      theme_details=$(echo "$theme_updates_json" | jq -r '.[] | "    - \(.name) (\(.version) -> \(.update_version))"')
      SITES_THEMES_MAP["$wp_path"]="$theme_details"
      if [ "$FORCE_UPDATE" = true ]; then
        printf "  ${COLOR_YELLOW}↳ Applying ${theme_updates} theme update(s)...${COLOR_RESET}\n"
        wp theme update --all --path="$wp_path"
        if [ $? -eq 0 ]; then printf "  ${COLOR_GREEN}  ✔ Success: Themes updated.${COLOR_RESET}\n"; else printf "  ${COLOR_RED}  ✘ Failure: Theme update command failed.${COLOR_RESET}\n"; fi
      fi
    else
      printf "  ${COLOR_GREEN}Themes:  All up to date.${COLOR_RESET}\n"
    fi
  fi
done < <(find "$SEARCH_DIR" -name "wp-config.php" -not -path "*/node_modules/*" -not -path "*/vendor/*" -print0)

print_header "Scan Complete: Summary"

printf "Total WordPress sites scanned: ${COLOR_BOLD}${COLOR_CYAN}${TOTAL_SITES_SCANNED}${COLOR_RESET}\n"

ANY_UPDATES_FOUND=$((TOTAL_CORE_UPDATES + TOTAL_PLUGIN_UPDATES + TOTAL_THEME_UPDATES))

if [ "$ANY_UPDATES_FOUND" -gt 0 ]; then
  printf "\n${COLOR_YELLOW}--- Sites Requiring Attention ---${COLOR_RESET}\n"

  if [ ${#SITES_WITH_CORE_UPDATES[@]} -gt 0 ]; then
    printf "\n${COLOR_BOLD}Core Updates:${COLOR_RESET}\n"
    for site in "${SITES_WITH_CORE_UPDATES[@]}"; do
      printf "  - ${COLOR_CYAN}%s${COLOR_RESET}\n" "$site"
    done
  fi

  if [ ${#SITES_PLUGINS_MAP[@]} -gt 0 ]; then
    printf "\n${COLOR_BOLD}Plugin Updates:${COLOR_RESET}\n"
    for site in "${!SITES_PLUGINS_MAP[@]}"; do
      printf "  - ${COLOR_CYAN}%s${COLOR_RESET}\n" "$site"
      printf "%s\n" "${SITES_PLUGINS_MAP["$site"]}"
    done
  fi

  if [ ${#SITES_THEMES_MAP[@]} -gt 0 ]; then
    printf "\n${COLOR_BOLD}Theme Updates:${COLOR_RESET}\n"
    for site in "${!SITES_THEMES_MAP[@]}"; do
      printf "  - ${COLOR_CYAN}%s${COLOR_RESET}\n" "$site"
      printf "%s\n" "${SITES_THEMES_MAP["$site"]}"
    done
  fi
else
  printf "\n${COLOR_BOLD}${COLOR_GREEN}🎉 All scanned sites are fully up to date! 🎉${COLOR_RESET}\n"
fi

printf "\n${COLOR_YELLOW}--- Grand Totals ---${COLOR_RESET}\n"
printf "The following totals reflect the number of updates ${COLOR_YELLOW}found${COLOR_RESET}, not necessarily applied.\n\n"

printf "Total Core Updates Found:   "
[ "$TOTAL_CORE_UPDATES" -gt 0 ] && printf "${COLOR_BOLD}${COLOR_RED}" || printf "${COLOR_BOLD}${COLOR_GREEN}"
printf "%s${COLOR_RESET}\n" "$TOTAL_CORE_UPDATES"

printf "Total Plugin Updates Found: "
[ "$TOTAL_PLUGIN_UPDATES" -gt 0 ] && printf "${COLOR_BOLD}${COLOR_RED}" || printf "${COLOR_BOLD}${COLOR_GREEN}"
printf "%s${COLOR_RESET}\n" "$TOTAL_PLUGIN_UPDATES"

printf "Total Theme Updates Found:  "
[ "$TOTAL_THEME_UPDATES" -gt 0 ] && printf "${COLOR_BOLD}${COLOR_RED}" || printf "${COLOR_BOLD}${COLOR_GREEN}"
printf "%s${COLOR_RESET}\n" "$TOTAL_THEME_UPDATES"

printf "${COLOR_BLUE}============================================================${COLOR_RESET}\n"
