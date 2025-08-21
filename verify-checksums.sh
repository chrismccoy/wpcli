#!/bin/bash

# This script iterates through subdirectories, identify WordPress installs,
# and run `wp core verify-checksums`. It provides a final summary that
# lists the specific sites with errors.

SITES_DIR="/home/chris/webapps"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

LOG_FILE=""
MAIL_TO=""
if [ "$1" ]; then
  LOG_FILE="$1"
fi
if [ "$2" ]; then
  MAIL_TO="$2"
fi

if ! command -v wp &>/dev/null; then
  echo -e "${RED}Error: 'wp' command not found.${NC}"
  exit 1
fi

if [ ! -d "$SITES_DIR" ]; then
  echo -e "${RED}Error: Base directory '${SITES_DIR}' not found.${NC}"
  exit 1
fi

if [ -n "$MAIL_TO" ] && ! command -v mail &>/dev/null; then
  echo -e "${RED}Error: 'mail' command not found, but an email address was provided.${NC}"
  exit 1
fi

if [ -n "$MAIL_TO" ] && [ -z "$LOG_FILE" ]; then
  echo -e "${RED}Error: An email address was provided, but no log file was specified.${NC}"
  exit 1
fi

if [ -n "$LOG_FILE" ]; then
  touch "$LOG_FILE" >/dev/null 2>&1 || {
    echo -e "${RED}Error: Cannot write to log file: ${LOG_FILE}${NC}"
    exit 1
  }
  echo "WordPress Checksum Verification Log - $(date)" >"$LOG_FILE"
  echo "========================================================================" >>"$LOG_FILE"
fi

echo -e "Starting WordPress core checksum verification in ${YELLOW}${SITES_DIR}${NC}"

if [ -n "$LOG_FILE" ]; then
  echo -e "Logging detailed output to: ${YELLOW}${LOG_FILE}${NC}"
fi

echo "========================================================================"

if [ -n "$LOG_FILE" ]; then
  exec 3>&1
  exec >>"$LOG_FILE" 2>&1
fi

sites_checked=0
sites_skipped=0
sites_with_errors=0

declare -a sites_with_errors_list=()

while read -r SITE_PATH; do
  if [ ! -r "$SITE_PATH" ]; then
    echo "-> Skipping: $(basename "$SITE_PATH") (Permission denied to read directory)"
    ((sites_skipped++))
  elif [ -f "$SITE_PATH/wp-config.php" ]; then
    echo "-> Found WordPress site: $(basename "$SITE_PATH")"
    echo "   Running checksum verification..."

    if ! wp core verify-checksums --path="$SITE_PATH"; then
      echo "   Warning: Checksum verification failed for $(basename "$SITE_PATH")"
      ((sites_with_errors++))
      sites_with_errors_list+=("$(basename "$SITE_PATH")")
    else
      echo "   Success: Core files verified."
    fi
    ((sites_checked++))
  else
    echo "-> Skipping: $(basename "$SITE_PATH") (wp-config.php not found)"
    ((sites_skipped++))
  fi
  echo "------------------------------------------------------------------------"
done < <(find "$SITES_DIR" -mindepth 1 -maxdepth 1 -type d)

if [ -n "$LOG_FILE" ]; then
  exec 1>&3
fi

if [ -n "$MAIL_TO" ]; then
  echo "--> Preparing to mail log..."
  SUBJECT="WordPress Checksum Report for $(hostname) - $(date)"
  if mail -s "$SUBJECT" "$MAIL_TO" <"$LOG_FILE"; then
    echo -e "    ${GREEN}Log file successfully sent to ${MAIL_TO}${NC}"
  else
    echo -e "    ${RED}Error: The 'mail' command failed to send the log file.${NC}"
  fi
fi

echo "========================================================================"
echo -e "${GREEN}Verification Complete.${NC}"
echo "Summary:"
echo "  - WordPress Sites Checked: ${sites_checked}"
echo "  - Directories Skipped: ${sites_skipped}"

echo "  - Sites with Errors/Mismatches: ${sites_with_errors}"

if [ ${sites_with_errors} -gt 0 ]; then
  echo -e "    ${YELLOW}The following sites reported errors:${NC}"
  for site in "${sites_with_errors_list[@]}"; do
    echo -e "    - ${RED}${site}${NC}"
  done
fi

if [ -n "$LOG_FILE" ]; then
  echo -e "A detailed log has been saved to: ${YELLOW}${LOG_FILE}${NC}"
fi

echo "========================================================================"
