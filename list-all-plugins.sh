#!/bin/bash

set -uo pipefail

SEARCH_DIR="$HOME/webapps"

COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'

PLUGIN_STATUS_FILTER="all"
WP_CLI_ARGS=()
TOTAL_SITES_SCANNED=0

declare -A SITES_PLUGIN_MAP

print_header() {
	printf "\n${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}\n"
	printf "${COLOR_BOLD}${COLOR_BLUE}  %s\n" "$1"
	printf "${COLOR_BOLD}${COLOR_BLUE}============================================================${COLOR_RESET}\n"
}

print_usage() {
	echo "Usage: $0 [search_directory] [--all | --active | --inactive]"
	echo
	echo "  Lists plugins for all WordPress installations found in a directory."
	echo
	echo "  Arguments:"
	echo "    search_directory   Optional. The directory to search in. Defaults to '~/webapps'."
	echo
	echo "  Options:"
	echo "    --all              List all plugins (default)."
	echo "    --active           List only active plugins."
	echo "    --inactive         List only inactive plugins."
}

if [ $# -eq 0 ]; then
	print_usage
	exit 0
fi

if [[ -d "$1" && ! "$1" =~ ^- ]]; then
	SEARCH_DIR="$1"
	shift
fi

case "${1-}" in
--active)
	PLUGIN_STATUS_FILTER="active"
	WP_CLI_ARGS+=(--status=active)
	;;
--inactive)
	PLUGIN_STATUS_FILTER="inactive"
	WP_CLI_ARGS+=(--status=inactive)
	;;
--all | *)
	PLUGIN_STATUS_FILTER="all"
	;;
esac

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

print_header "WordPress Plugin Scan Initialized"

printf "Searching for WordPress installs in: ${COLOR_CYAN}${SEARCH_DIR}${COLOR_RESET}\n"
printf "Listing plugins with status:         ${COLOR_CYAN}${PLUGIN_STATUS_FILTER}${COLOR_RESET}\n"

while IFS= read -r -d '' config_file; do
	wp_path=$(dirname "$config_file")
	((TOTAL_SITES_SCANNED++))

	printf "\n${COLOR_YELLOW}🔎 Checking Site #${TOTAL_SITES_SCANNED}: ${COLOR_CYAN}${wp_path}${COLOR_RESET}\n"
	printf -- "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - \n"

	plugin_list_json=$(wp plugin list --path="$wp_path" --format=json "${WP_CLI_ARGS[@]}" 2>/dev/null)
	if ! echo "$plugin_list_json" | jq -e . >/dev/null 2>&1; then
		printf "  ${COLOR_RED}Could not retrieve plugin info (is this a valid WP install?)${COLOR_RESET}\n"
		continue
	fi

	plugin_count=$(echo "$plugin_list_json" | jq 'length')

	if [ "$plugin_count" -gt 0 ]; then
		plural_s="s"
		if [ "$plugin_count" -eq 1 ]; then
			plural_s=""
		fi
		printf "  ${COLOR_GREEN}Found ${plugin_count} plugin${plural_s}:${COLOR_RESET}\n"

		# CHANGED: Added `| tail -n +2` to remove the header line
		wp plugin list --path="$wp_path" --fields=name "${WP_CLI_ARGS[@]}" | tail -n +2 | sed 's/^/    /'
		plugin_details=$(echo "$plugin_list_json" | jq -r '.[] | "    - \(.name)"')
		SITES_PLUGIN_MAP["$wp_path"]="$plugin_details"
	else
		printf "  ${COLOR_GREEN}No matching plugins found.${COLOR_RESET}\n"
	fi

done < <(find "$SEARCH_DIR" -name "wp-config.php" -not -path "*/node_modules/*" -not -path "*/vendor/*" -print0)

print_header "Scan Complete: Summary"

printf "Total WordPress sites scanned: ${COLOR_BOLD}${COLOR_CYAN}${TOTAL_SITES_SCANNED}${COLOR_RESET}\n\n"

if [ ${#SITES_PLUGIN_MAP[@]} -gt 0 ]; then
	printf "${COLOR_YELLOW}--- Plugin Summary ---${COLOR_RESET}\n"
	for site in "${!SITES_PLUGIN_MAP[@]}"; do
		printf "\n${COLOR_BOLD}Site: ${COLOR_CYAN}%s${COLOR_RESET}\n" "$site"
		printf "%s\n" "${SITES_PLUGIN_MAP["$site"]}"
	done
else
	printf "\n${COLOR_BOLD}${COLOR_GREEN}🎉 No sites with matching plugins were found. 🎉${COLOR_RESET}\n"
fi

printf "\n${COLOR_BLUE}============================================================${COLOR_RESET}\n"
