#!/bin/bash

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
NC="\033[0m"

check_editor_status() {

  if ! command -v wp &>/dev/null; then
    echo -e "${RED}Error: wp-cli is not installed or not in your PATH.${NC}"
    exit 1
  fi
  if ! wp core is-installed >/dev/null 2>/dev/null; then
    echo -e "${RED}Error: This does not appear to be a WordPress installation.${NC}"
    exit 1
  fi

  echo "🔎 Performing hybrid check of editor status..."

  if wp plugin is-active classic-editor >/dev/null 2>&1; then
    echo -e "\n✅ ${YELLOW}Classic Editor is ENABLED${NC} (globally)."
    echo -e "   Reason: The 'classic-editor' plugin is installed and ${GREEN}active${NC}."
    exit 0
  fi

  echo -e "\nℹ️  'classic-editor' plugin not active. Checking filters..."

  local global_post_filter_disables
  global_post_filter_disables=$(wp eval "echo apply_filters('use_block_editor_for_post', true, null) ? '0' : '1';" 2>/dev/null)

  if [[ "$global_post_filter_disables" == "1" ]]; then
    echo -e "\n${MAGENTA}--- Global Override Detected ---${NC}"
    echo -e "The ${YELLOW}'use_block_editor_for_post'${NC} filter is globally disabling the Block Editor."
    echo -e "All post types will use the ${YELLOW}Classic Editor${NC}.\n"
    exit 0
  fi

  echo -e "\n${CYAN}--- Checking by Post Type ('use_block_editor_for_post_type') ---${NC}"
  local classic_is_used_by_type=false

  while read -r post_type; do
    if [[ "$post_type" == "attachment" ]]; then
      continue
    fi

    local type_filter_allows_block
    type_filter_allows_block=$(wp eval "echo apply_filters('use_block_editor_for_post_type', true, '$post_type') ? '1' : '0';" 2>/dev/null)

    if [[ "$type_filter_allows_block" == "1" ]]; then
      printf "%-25s ${GREEN}%s${NC}\n" "For '$post_type':" "Block Editor is ENABLED"
    else
      printf "%-25s ${YELLOW}%s${NC}\n" "For '$post_type':" "Classic Editor is ENABLED"
      classic_is_used_by_type=true
    fi
  done < <(wp post-type list --field=name --public=true)

  echo -e "\n${CYAN}--- Summary ---${NC}"

  if [[ "$classic_is_used_by_type" == true ]]; then
    echo "The Classic Editor has been enabled for one or more post types via the"
    echo "'use_block_editor_for_post_type' filter."
    echo -e "\n   Check your theme's functions.php or a custom plugin for this filter."
  else
    echo "The Block Editor appears to be fully enabled for all public post types."
  fi
}

check_editor_status
