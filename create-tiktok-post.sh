#!/bin/bash

#   Creates a WordPress post from a given TikTok URL.
#   It uses the tikwm.com API to fetch video details
#   then imports both the video and its cover image into the WordPress Media Library
#   The cover is set as the featured image.

POST_STATUS="draft"

echo "Initializing script..."

for cmd in wp curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' is not installed. Please install it and try again."
    exit 1
  fi
done

if [ -z "$1" ]; then
  echo "Usage: $0 <TIKTOK_URL>"
  exit 1
fi

if ! wp core is-installed >/dev/null 2>&1; then
  echo "Error: This does not appear to be a WordPress installation."
  echo "Please run this script from the root directory of your WordPress site."
  exit 1
fi

echo "🔎 Performing advanced editor check for post type 'post'..."

IS_CLASSIC_EDITOR_ACTIVE=false
REASON=""

if wp plugin is-active classic-editor >/dev/null 2>&1; then
  IS_CLASSIC_EDITOR_ACTIVE=true
  REASON="The 'classic-editor' plugin is active."
elif [[ $(wp eval "echo apply_filters('use_block_editor_for_post', true, null) ? 'enabled' : 'disabled';") == "disabled" ]]; then
  IS_CLASSIC_EDITOR_ACTIVE=true
  REASON="A global filter on 'use_block_editor_for_post' is disabling the Block Editor."
elif [[ $(wp eval "echo apply_filters('use_block_editor_for_post_type', true, 'post') ? 'enabled' : 'disabled';") == "disabled" ]]; then
  IS_CLASSIC_EDITOR_ACTIVE=true
  REASON="A filter on 'use_block_editor_for_post_type' is disabling the Block Editor for 'post'."
fi

if [ "$IS_CLASSIC_EDITOR_ACTIVE" = true ]; then
  echo "   - Detected: Classic Editor will be used."
  echo "   - Reason: $REASON"
else
  echo "   - Detected: Block Editor (Gutenberg) will be used."
fi

TIKTOK_URL="$1"
POST_ID=$(echo "$TIKTOK_URL" | grep -oP '(?<=video/)\d+')

echo "Processing TikTok URL: $TIKTOK_URL"

if [ -z "$POST_ID" ]; then
  echo "Error: Could not extract a valid TikTok post ID from the URL."
  exit 1
fi

echo "✅ Found TikTok Post ID: $POST_ID"

API_URL="https://www.tikwm.com/api/?url=${POST_ID}"
JSON_RESPONSE=$(curl -s "$API_URL")

echo "➡️  Fetching data from API..."

API_CODE=$(echo "$JSON_RESPONSE" | jq -r '.code')
if [ "$API_CODE" -ne 0 ]; then
  API_MSG=$(echo "$JSON_RESPONSE" | jq -r '.msg')
  echo "Error: API call failed. Message: $API_MSG"
  exit 1
fi

POST_TITLE=$(echo "$JSON_RESPONSE" | jq -r '.data.title')
VIDEO_URL=$(echo "$JSON_RESPONSE" | jq -r '.data.play')
COVER_URL=$(echo "$JSON_RESPONSE" | jq -r '.data.cover')
AUTHOR_NICKNAME=$(echo "$JSON_RESPONSE" | jq -r '.data.author.nickname')

if [ -z "$VIDEO_URL" ] || [ "$VIDEO_URL" == "null" ] || [ -z "$COVER_URL" ] || [ "$COVER_URL" == "null" ]; then
  echo "Error: Could not parse required video or cover URL from API response. Aborting."
  exit 1
fi

echo "✅ Successfully parsed API data."

echo "📝 Creating initial draft post..."

NEW_POST_ID=$(wp post create --post_type=post --post_title="$POST_TITLE" --post_content="[Importing content...]" --post_status="$POST_STATUS" --porcelain)

if [ $? -ne 0 ] || ! [[ "$NEW_POST_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: Failed to create initial WordPress post via WP-CLI."
  exit 1
fi

echo "✅ Post created with ID: $NEW_POST_ID (Status: $POST_STATUS)"

LOCAL_COVER_URL=""
LOCAL_VIDEO_URL=""
COVER_ATTACHMENT_ID=""
VIDEO_ATTACHMENT_ID=""

TMP_COVER_FILE="/tmp/tiktok_cover_${POST_ID}.jpeg"
curl -s -L -o "$TMP_COVER_FILE" "$COVER_URL"

echo "🖼️  Downloading cover image..."

if [ -f "$TMP_COVER_FILE" ]; then
  echo "   - Importing cover image into Media Library..."
  COVER_ATTACHMENT_ID=$(wp media import "$TMP_COVER_FILE" --post_id="$NEW_POST_ID" --title="Cover for TikTok ${POST_ID}" --porcelain)
  rm "$TMP_COVER_FILE"

  if [ $? -eq 0 ] && [[ "$COVER_ATTACHMENT_ID" =~ ^[0-9]+$ ]]; then
    wp post meta set "$NEW_POST_ID" _thumbnail_id "$COVER_ATTACHMENT_ID"
    LOCAL_COVER_URL=$(wp post get "$COVER_ATTACHMENT_ID" --field=guid)
    echo "   - ✅ Set as featured image."
  else
    echo "   - ⚠️ Warning: Failed to import cover image."
  fi
else
  echo "   - ⚠️ Warning: Failed to download cover image."
fi

TMP_VIDEO_FILE="/tmp/tiktok_video_${POST_ID}.mp4"
curl -s -L -o "$TMP_VIDEO_FILE" "$VIDEO_URL"

echo "📹 Downloading video (this may take a moment)..."

if [ -f "$TMP_VIDEO_FILE" ]; then
  echo "   - Importing video into Media Library..."
  VIDEO_ATTACHMENT_ID=$(wp media import "$TMP_VIDEO_FILE" --post_id="$NEW_POST_ID" --title="Video for TikTok ${POST_ID}" --porcelain)
  rm "$TMP_VIDEO_FILE"

  if [ $? -eq 0 ] && [[ "$VIDEO_ATTACHMENT_ID" =~ ^[0-9]+$ ]]; then
    LOCAL_VIDEO_URL=$(wp post get "$VIDEO_ATTACHMENT_ID" --field=guid)
    echo "   - ✅ Video import successful."
  else
    echo "   - ⚠️ Warning: Failed to import video file."
  fi
else
  echo "   - ⚠️ Warning: Failed to download video."
fi

if [ -n "$LOCAL_VIDEO_URL" ]; then
  POST_CONTENT=""
  if [ "$IS_CLASSIC_EDITOR_ACTIVE" = true ]; then
    echo "✍️  Constructing content for Classic Editor ([video] shortcode)..."
    POST_CONTENT="[video src=\"${LOCAL_VIDEO_URL}\" poster=\"${LOCAL_COVER_URL}\"]"
  else
    echo "✍️  Constructing content for Block Editor (wp:video block)..."
    POST_CONTENT="<!-- wp:video {\"id\":${VIDEO_ATTACHMENT_ID},\"poster\":\"${LOCAL_COVER_URL}\"} -->
<figure class=\"wp-block-video\">
    <video controls poster=\"${LOCAL_COVER_URL}\" src=\"${LOCAL_VIDEO_URL}\"></video>
    <figcaption class=\"wp-element-caption\">TikTok by ${AUTHOR_NICKNAME}</figcaption>
</figure>
<!-- /wp:video -->"
  fi

  echo "   - Updating post with final content..."
  wp post update "$NEW_POST_ID" --post_content="$POST_CONTENT"
  echo "   - ✅ Post content updated."
else
  echo "   - ⚠️ Error: Could not get local video URL. Post content will be empty."
  wp post update "$NEW_POST_ID" --post_content="[Video import failed.]"
fi

SITE_URL=$(wp option get siteurl)
EDIT_LINK="${SITE_URL}/wp-admin/post.php?post=${NEW_POST_ID}&action=edit"

echo "🎉 All done!"
echo "You can edit the new draft here: $EDIT_LINK"

exit 0
