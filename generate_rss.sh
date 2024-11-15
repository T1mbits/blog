#!/bin/bash

# Set variables
OUTPUT_FILE="./book/rss.xml"
LAST_BUILD_DATE=$(date -R)

# Prepare feed items by parsing .md files in your `mdbook` content folder
FEED_ITEMS=""

for file in $(find src -mindepth 2 -name "*.md" -type f | xargs -I{} git log -1 --format="%at {}" {} | sort -nr | awk '{print $2}'); do
    # Extract title and link
    TITLE=$(head -n 1 "$file" | sed 's/# //') # Assumes first line is the title
    LINK="https://t1mbits.github.io/blog${file#src}"
    LINK="${LINK%.md}.html"
    PUB_DATE=$(git log -1 --format="%aD" "$file") # Gets last commit date for each file

    # Create RSS item
    FEED_ITEMS+="
    <item>
        <title>${TITLE}</title>
        <link>${LINK}</link>
        <pubDate>${PUB_DATE}</pubDate>
        <description>Now see this is automated and I'm too lazy to create an automated description system, and if I pasted the contents of my posts into a description tag it would most definitely cause problems</description>
    </item>"
done

cat <<EOF > "$OUTPUT_FILE"
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">
  <channel>
    <title>timbits wont stop yapping</title>
    <link>https://t1mbits.github.io/blog/</link>
    <description>timbits yaps about things in great detail every once in a while</description>
    <lastBuildDate>${LAST_BUILD_DATE}</lastBuildDate>
    ${FEED_ITEMS}
  </channel>
</rss>
EOF