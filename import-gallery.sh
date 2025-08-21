#!/bin/bash

# Example: ./import-gallery.sh ./my_images.txt "A Beautiful New Gallery"

set -e
set -u
set -o pipefail

POST_STATUS="publish"

if [ "$#" -ne 2 ]; then
  echo "Error: Invalid number of arguments."
  echo "Usage: $0 <path_to_urls_file> \"Your Post Title\""
  exit 1
fi

URL_FILE="$1"
POST_TITLE="$2"

if ! command -v wp &>/dev/null; then
  echo "Error: wp-cli is not installed or not in your PATH."
  echo "Please install wp-cli: https://wp-cli.org/"
  exit 1
fi

if [ ! -f "$URL_FILE" ] || [ ! -r "$URL_FILE" ]; then
  echo "Error: URL file '$URL_FILE' not found or is not readable."
  exit 1
fi

echo "Starting image import process from '$URL_FILE'..."

attachment_ids=()

while IFS= read -r url || [[ -n "$url" ]]; do
  if [[ -z "${url// }" ]]; then
    continue
  fi

  echo "-> Importing URL: $url"

  attachment_id=$(wp media import "$url" --porcelain) || true

  if [ -n "$attachment_id" ] && [[ "$attachment_id" =~ ^[0-9]+$ ]]; then
    echo "   ✅ Success! Attachment ID: $attachment_id"
    attachment_ids+=("$attachment_id")
  else
    echo "   ⚠️ Warning: Failed to import URL: $url. Skipping."
  fi
done <"$URL_FILE"

if [ ${#attachment_ids[@]} -eq 0 ]; then
  echo "Error: No images were successfully imported. Aborting post creation."
  exit 1
fi

echo "----------------------------------------"
echo "Total images imported: ${#attachment_ids[@]}"

(
  IFS=,
  id_string="${attachment_ids[*]}"
)

echo "Generated attachment ID string: $id_string"

gallery_shortcode="[gallery ids=\"$id_string\"]"

echo "Creating post with title: \"$POST_TITLE\""

new_post_id=$(
  wp post create --post_title="$POST_TITLE" --post_content="$gallery_shortcode" --post_status="$POST_STATUS" --porcelain
)

if [ $? -eq 0 ] && [ -n "$new_post_id" ]; then
  post_url=$(wp post get "$new_post_id" --field=url)
  echo "----------------------------------------"
  echo "🚀 Success! Post created."
  echo "Post ID:  $new_post_id"
  echo "Post URL: $post_url"
  echo "----------------------------------------"
else
  echo "Error: Failed to create the WordPress post."
  exit 1
fi
