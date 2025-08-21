#!/bin/bash

# Find and deletes users with a specific role who have zero published posts.

SEARCH_DIR="webapps"
TARGET_ROLE="subscriber"
DRY_RUN=1

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "A utility to find and delete users with a specific role and 0 posts across multiple WordPress sites."
  echo
  echo "Options:"
  echo "  -p, --path <directory>   The directory to scan for WordPress installs. (Default: \"${SEARCH_DIR}\")"
  echo "  -r, --role <role>        The user role to target for deletion. (Default: \"${TARGET_ROLE}\")"
  echo "      --dry-run            Run the script without deleting any users; only shows what would be done."
  echo "  -h, --help               Display this help message and exit."
  echo
  echo "Example: $0 --path /var/www --role contributor --dry-run"
}

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -p|--path)
      SEARCH_DIR="$2"
      shift
      shift
      ;;
    -r|--role)
      TARGET_ROLE="$2"
      shift
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option '$1'"
      usage
      exit 1
      ;;
  esac
done

if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "🚀 DRY RUN MODE ENABLED: No users will be deleted. The script will only report what it would do."
fi

if [ ! -d "$SEARCH_DIR" ]; then
  echo "❌ FATAL ERROR: Search directory '$SEARCH_DIR' not found. Please check the path. Exiting."
  exit 1
fi

if ! command -v wp &> /dev/null; then
  echo "❌ FATAL ERROR: The 'wp' command (WP-CLI) was not found. Please install it to continue. Exiting."
  exit 1
fi

declare -A site_deletion_counts

overall_deleted_count=0
overall_skipped_count=0
sites_processed_count=0
sites_affected_count=0

echo "======================================================================"
echo "WP User Purge Utility - Initializing Scan"
echo "======================================================================"
echo "Searching for WordPress sites in: $SEARCH_DIR"
echo "Targeting users with role:        $TARGET_ROLE"
echo "----------------------------------------------------------------------"

while IFS= read -r -d '' config_file; do
  site_path=$(dirname "$config_file")
  ((sites_processed_count++))

  echo
  echo "--- Processing Site ($sites_processed_count): $site_path ---"

  site_results=$(
    (
      cd "$site_path" || exit 1

      if ! wp core is-installed > /dev/null 2>&1; then
        echo "STATUS:Invalid"
        exit
      fi

      user_ids=$(wp user list --role="${TARGET_ROLE}" --field=ID --skip-columns)

      if [ -z "$user_ids" ]; then
        echo "STATUS:NoMatchingUsers"
        exit
      fi

      deleted_this_site=0
      skipped_this_site=0

      for user_id in $user_ids; do
        user_login=$(wp user get "${user_id}" --field=user_login --format=csv | tail -n 1)
        post_count=$(wp post list --author="${user_id}" --post_type=any --format=count)

        if [ "${post_count}" -eq 0 ]; then
          if [ ${DRY_RUN} -eq 1 ]; then
            echo "[DRY RUN] 👉 Would delete user: ${user_login} (ID: ${user_id}) - 0 posts."
          else
            echo "🔥 Deleting user: ${user_login} (ID: ${user_id}) - 0 posts."
            wp user delete "${user_id}" --yes
          fi
          ((deleted_this_site++))
        else
          echo "👍 Skipping user: ${user_login} (ID: ${user_id}) - ${post_count} post(s) found."
          ((skipped_this_site++))
        fi
      done

      echo "DELETED:${deleted_this_site} SKIPPED:${skipped_this_site}"
    )
  )

  if [[ $site_results == *"STATUS:Invalid"* ]]; then
    echo "⚠️  Skipping: Directory does not contain a valid WordPress installation or has a DB error."
    continue
  fi

  if [[ $site_results == *"STATUS:NoMatchingUsers"* ]]; then
    echo "✅ No users found with the '${TARGET_ROLE}' role on this site."
    continue
  fi

  deleted_on_site=0
  skipped_on_site=0

  if [[ $site_results =~ DELETED:([0-9]+) ]]; then
    deleted_on_site=${BASH_REMATCH[1]}
  fi

  if [[ $site_results =~ SKIPPED:([0-9]+) ]]; then
    skipped_on_site=${BASH_REMATCH[1]}
  fi

  overall_deleted_count=$((overall_deleted_count + deleted_on_site))
  overall_skipped_count=$((overall_skipped_count + skipped_on_site))

  if [ "$deleted_on_site" -gt 0 ]; then
    ((sites_affected_count++))
    site_deletion_counts["$site_path"]=$deleted_on_site
  fi

done < <(find "$SEARCH_DIR" -name "wp-config.php" -print0 | sort -z)

echo
echo "======================================================================"
echo "✅ SCAN COMPLETE: FINAL SUMMARY"
echo "======================================================================"
echo
echo "📊 Overall Statistics:"
echo "   - Total WordPress sites processed: ${sites_processed_count}"
echo "   - Total users deleted across all sites: ${overall_deleted_count}"
echo "   - Total users skipped across all sites: ${overall_skipped_count}"
echo "   - Total sites with user deletions: ${sites_affected_count}"
echo

if [ ${sites_affected_count} -gt 0 ]; then
  echo "📈 Sites With Deleted Users:"
  printf '%s\n' "${!site_deletion_counts[@]}" | sort | while read -r site; do
    count=${site_deletion_counts[$site]}
    printf "   - %s: %d users deleted\n" "$site" "$count"
  done
else
  echo "👍 No users matching the criteria were found for deletion on any site."
fi

echo
echo "======================================================================"
echo "WP User Purge Utility has finished."
