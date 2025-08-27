#!/bin/bash

C_INFO='\033[0;36m'
C_SUCCESS='\033[0;32m'
C_WARN='\033[0;33m'
C_ERROR='\033[0;31m'
C_RESET='\033[0m'

info() {
  echo -e "${C_INFO}[INFO]${C_RESET} $1"
}
success() {
  echo -e "${C_SUCCESS}[SUCCESS]${C_RESET} $1"
}
warn() {
  echo -e "${C_WARN}[WARNING]${C_RESET} $1"
}
error() {
  echo -e "${C_ERROR}[ERROR]${C_RESET} $1" >&2
}

if ! command -v wp &>/dev/null; then
  error "wp-cli is not installed or not in the system's PATH."
  info "Please install wp-cli to use this script: https://wp-cli.org/"
  exit 1
fi

if [ ! -f "wp-config.php" ]; then
  error "wp-config.php not found in the current directory."
  info "Please run this script from the root of your WordPress installation."
  exit 1
fi

if [ "$#" -ne 2 ]; then
  error "Invalid number of arguments."
  echo "Usage: $0 <start_date> <end_date>"
  echo "Format: YYYY-MM-DD"
  echo "Example: $0 2024-01-01 2024-01-31"
  exit 1
fi

START_DATE=$1
END_DATE=$2
DATE_REGEX="^[0-9]{4}-[0-9]{2}-[0-9]{2}$"

if ! [[ $START_DATE =~ $DATE_REGEX ]] || ! [[ $END_DATE =~ $DATE_REGEX ]]; then
  error "Invalid date format. Please use YYYY-MM-DD."
  exit 1
fi

echo
warn "This script will permanently delete comments from the WordPress site in this directory: $(pwd)"
warn "Date Range for Deletion: ${START_DATE} to ${END_DATE} (inclusive)."
echo
read -p "Are you absolutely sure you want to continue? [y/N] " -r CONFIRM
echo

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  info "Operation cancelled by user."
  exit 0
fi

TOTAL_DELETED=0

info "Processing site in current directory..."

DATE_QUERY="{\"after\":\"${START_DATE} 00:00:00\", \"before\":\"${END_DATE} 23:59:59\", \"inclusive\":true}"

info "Checking for comments to delete..."
COMMENT_COUNT=$(wp comment list --format=count --date_query="$DATE_QUERY" --allow-root 2>/dev/null)

if [[ $? -ne 0 ]]; then
  error "Failed to query comments."
  error "Possible issues: DB connection error in wp-config.php, or user permissions."
  exit 1
fi

if [ "$COMMENT_COUNT" -eq 0 ]; then
  success "No comments found in the specified date range."
else
  info "Found ${COMMENT_COUNT} comments to delete. Proceeding with deletion..."
  DELETION_RESULT=$(wp comment delete $(wp comment list --format=ids --date_query="$DATE_QUERY" --allow-root) --force --allow-root)

  if [[ $? -eq 0 ]]; then
    success "Successfully deleted ${COMMENT_COUNT} comments."
    TOTAL_DELETED=$((TOTAL_DELETED + COMMENT_COUNT))
  else
    error "An error occurred during comment deletion."
    warn "Output from wp-cli: ${DELETION_RESULT}"
  fi
fi

echo -e "\n${C_SUCCESS}======================= SUMMARY =======================${C_RESET}"

success "Script finished."
success "Permanently deleted a total of ${TOTAL_DELETED} comments from this site."

echo -e "${C_SUCCESS}=======================================================${C_RESET}"
