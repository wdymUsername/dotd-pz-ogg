#!/usr/bin/bash

export LC_ALL=en_US.UTF-8 #Use en_US locale, mainly to force date format for songList

webhooksfile="webhooks"
webhookmain=$(head -n 1 "$webhooksfile")
webhooktest=$(tail -n 1 "$webhooksfile")
deps=(yt-dlp ffmpeg zip)
dirs=(ogg raw archive)
tempfile=$(mktemp)

if [ -s "$webhooksfile" ]; then
  :
else
  echo "Error: The file '$webhooksfile' does not exist or is empty."
  exit 1
fi

if [ $# -eq 1 ]; then
  if [ "$1" = "--test" ]; then
    webhook=$webhooktest
  else
    echo "Invalid argument: $1"
    exit 1
  fi
else
  webhook=$webhookmain
fi

check_deps() {
  for dep in "${deps[@]}"; do
    command -v "$dep" &>/dev/null || {
      echo "$dep is not installed. Please install it before running this script."
      exit 1
    }
  done
}

create_dirs() {
  for dir in "${dirs[@]}"; do
    [ ! -d "$dir" ] && mkdir "$dir"
  done
}

fix_links() {
  if [ ! -f "links.txt" ]; then
    echo "links.txt file not found. Creating an empty file..."
    touch links.txt
    read -p "Please add valid YouTube links to download in links.txt and press Enter when ready... "
  else
    echo "Fixing links..."
    extract_com_id
    extract_be_id
    store_video_id
  fi
}

extract_com_id() {
  awk '{ 
    if ($0 ~ /watch\?v=([^&]+)/) {
      match($0, /watch\?v=([^&]+)/, arr)
      print arr[1]
    }
  }' links.txt >> $tempfile
}

extract_be_id() {
  awk '{ 
    if ($0 ~ /youtu.be\/([^\/]+)/) {
      match($0, /youtu.be\/([^\/]+)/, arr)
      print arr[1]
    }
  }' links.txt | awk -F'[?#]' '{print $1}' >> $tempfile
}

store_video_id() {
  > links.txt
  sort -u "$tempfile" | while IFS= read -r id; do
    echo "https://youtu.be/$id" >> links.txt
  done
  rm "$tempfile"
  count=$(grep -c '^https://youtu.be/[a-zA-Z0-9_-]*$' links.txt)
  echo "Valid links found: $count"
}

download_files() {
  yt-dlp -q --no-warnings --progress -o "./raw/%(title)s.%(ext)s" -f 139 -a links.txt -x --audio-format m4a --no-keep-video
}

convert_files() {
  count=0
  total=$(ls raw/*.m4a | wc -l)
  for i in raw/*.m4a; do
    ((count++))
    echo "Converting (${count}/${total}): $(basename "$i")"
    ffmpeg -loglevel error -i "$i" -b:a 48k -acodec libvorbis "ogg/$(basename "${i%.m4a}").ogg"
  done
}

fix_filenames() {
  for file in ogg/*.ogg; do
    filename=$(basename "${file%.ogg}")
    newfilename=$(echo "$filename" | 
      iconv -c -t ascii//translit |
      sed -r '
        s/\b(Ft\.|Feat\.|Official Music Video|Lyrics|Audio|HD|HQ)\b//gi
        s/\[.*\]//g
        s/\(.*\)//g
        s/^[^a-zA-Z0-9_ -]+//g
        s/ +$//g
      ')
    newfilename=${newfilename:-$filename}
    mv "$file" "ogg/${newfilename}.ogg"
  done
}

move_files() {
  while true; do
    read -p "Enter a name for the new directory or input name of existing directory: " -r dirname
    if [ -z "$dirname" ]; then
      echo "Directory name cannot be empty. Please try again."
    elif [[ $dirname =~ ^[a-zA-Z0-9_\-]+$ ]]; then
      break
    else
      echo "Invalid directory name. Please use only letters, numbers, underscores, and hyphens."
    fi
  done
  [ ! -d "ogg/$dirname" ] && mkdir "ogg/$dirname"
  for file in ogg/*.ogg; do
    read -p "Enter a new name for $(basename "${file%.ogg}"): " -r newname
    newname=${newname:-$(basename "${file%.ogg}")}
    mv "$file" "ogg/$dirname/${newname}.ogg"
  done
}

add_to_songlist() {
  timestamp=$(date +"%Y-%b-%d")
  echo "REDEEMED BY $dirname on [$timestamp]" > temp
  for file in "ogg/$dirname"/*.ogg; do
    echo "$(basename "${file%.ogg}")" >> temp
  done
  echo >> temp
  cat songListS12.txt >> temp
  mv temp songListS12.txt
}

upload_files() {
  scriptroot=$(pwd)
  cd "ogg/$dirname"
  zip -r "$dirname.zip" .
  curl -s -o /dev/null -X POST $webhook -F "file1=@$dirname.zip"
  mv "$dirname.zip" "$scriptroot/archive"
  cd "$scriptroot"
  curl -s -o /dev/null -X POST $webhook -F "file1=@songListS12.txt"
  curl -s -o /dev/null -X POST "$webhook" -H "Content-Type:application/json" --data "{\"content\": \"-# More tapes <@745598591757713458>! <a:catdance:1287017623036624947>\"}"
  rm -r raw && rm -r ogg
  echo "Files sent! Exiting..."
}

check_deps
create_dirs
fix_links
download_files
convert_files
fix_filenames
move_files
add_to_songlist
upload_files