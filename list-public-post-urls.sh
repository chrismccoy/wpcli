#!/bin/bash

## wp post-type list --field=name,public --format=csv | tail -n +2 | awk -F, '$2 == 1 {print $1}'

if ! command -v wp &>/dev/null; then
  echo "Error: WP-CLI is not installed or not in your PATH." >&2
  echo "Please install it from https://wp-cli.org/" >&2
  exit 1
fi

if ! wp core is-installed &>/dev/null; then
  echo "Error: This does not appear to be a WordPress installation." >&2
  echo "Please run this script from the root of your WordPress directory." >&2
  exit 1
fi

echo "Fetching all public post types and their URLs..."

wp post-type list --field=name,public --format=csv | tail -n +2 | awk -F, '$2 == 1 {print $1}' | while read -r post_type; do
  post_count=$(wp post list --post_type="$post_type" --post_status=publish --format=count)

  if [ "$post_count" -gt 0 ]; then
    echo ""
    echo "--- Post Type: $post_type ---"

    wp post list --post_type="$post_type" --post_status=publish --field=url
  fi
done

echo ""
echo "Script finished."
