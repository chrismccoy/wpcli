#!/bin/bash

# Bulk create WordPress multisite sites

C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_NONE='\033[0m' # No Color

if [ "$#" -ne 2 ]; then
    echo -e "${C_RED}Error: Invalid number of arguments.${C_NONE}"
    echo -e "Usage: ${C_CYAN}$0 <sites_file.txt> <admin_email@domain.com>${C_NONE}"
    echo -e "  ${C_CYAN}<sites_file.txt>${C_NONE} : A plain text file with one site title per line."
    echo -e "  ${C_CYAN}<admin_email@domain.com>${C_NONE} : The email of an existing Administrator user."
    exit 1
fi

SITES_FILE="$1"
ADMIN_EMAIL="$2"

if [ ! -f "$SITES_FILE" ]; then
    echo -e "${C_RED}Error: The specified file '$SITES_FILE' does not exist.${C_NONE}"
    exit 1
fi

created_sites=()
skipped_sites=()
failed_sites=()
invalid_titles=()
total_lines_processed=0

echo "Starting site creation process..."
echo "Sites file: $SITES_FILE"
echo "Admin user: $ADMIN_EMAIL"
echo "---------------------------------"

USER_ROLES=$(wp user get "$ADMIN_EMAIL" --field=roles 2>/dev/null)

if [ -z "$USER_ROLES" ]; then
    echo -e "${C_RED}Error: User with email '$ADMIN_EMAIL' not found. Aborting script.${C_NONE}"
    exit 1
fi

if [[ "$USER_ROLES" != *administrator* ]]; then
    echo -e "${C_RED}Error: User '$ADMIN_EMAIL' exists but is not an administrator. Aborting script.${C_NONE}"
    echo -e "${C_YELLOW}Found roles for this user: $USER_ROLES${C_NONE}"
    exit 1
fi

echo -e "${C_GREEN}Admin user '$ADMIN_EMAIL' validated successfully.${C_NONE}"
echo "---------------------------------"

while IFS= read -r title || [[ -n "$title" ]]; do
    if [ -z "$title" ]; then
        continue
    fi

    ((total_lines_processed++))

    slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]+/-/g' | sed 's/^-//;s/-$//')

    if [ -z "$slug" ]; then
        echo -e "${C_YELLOW}Skipping invalid title: '$title' (results in empty slug).${C_NONE}"
        invalid_titles+=("$title")
        continue
    fi

    if wp site exists --slug="$slug" &>/dev/null; then
        echo -e "${C_YELLOW}Site '$title' (slug: /$slug/) already exists. Skipping.${C_NONE}"
        skipped_sites+=("$title")
    else
        echo "Creating site for '$title'..."
        output=$(wp site create --title="$title" --slug="$slug" --email="$ADMIN_EMAIL" 2>&1)

        if [ $? -eq 0 ]; then
            echo -e "${C_GREEN}Successfully created site '$title'.${C_NONE}"
            created_sites+=("$title")
        else
            echo -e "${C_RED}Failed to create site '$title'. WP-CLI gave this error:${C_NONE}"
            echo -e "$output"
            failed_sites+=("$title")
        fi
    fi
    echo
done < "$SITES_FILE"

echo "---------------------------------"
echo "---     Summary               ---"
echo "---------------------------------"
echo -e "Processed ${C_CYAN}$total_lines_processed${C_NONE} site titles from the file."
echo

echo -e "${C_GREEN}Created: ${#created_sites[@]}${C_NONE}"

if [ ${#created_sites[@]} -gt 0 ]; then
    for site in "${created_sites[@]}"; do
        echo "  - $site"
    done
fi

echo -e "${C_YELLOW}Skipped (already exist): ${#skipped_sites[@]}${C_NONE}"

if [ ${#skipped_sites[@]} -gt 0 ]; then
    for site in "${skipped_sites[@]}"; do
        echo "  - $site"
    done
fi

echo -e "${C_RED}Failed: ${#failed_sites[@]}${C_NONE}"

if [ ${#failed_sites[@]} -gt 0 ]; then
    for site in "${failed_sites[@]}"; do
        echo "  - $site"
    done
fi

echo -e "${C_YELLOW}Invalid Titles (skipped): ${#invalid_titles[@]}${C_NONE}"

if [ ${#invalid_titles[@]} -gt 0 ]; then
    for site in "${invalid_titles[@]}"; do
        echo "  - $site"
    done
fi

echo "---------------------------------"
echo -e "${C_GREEN}Finished.${C_NONE}"
