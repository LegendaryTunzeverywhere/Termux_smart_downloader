#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Termux Smart Downloader
#  Shared via: Settings > Share > Termux
#  Usage: termux-downloader.sh [URL]
# ============================================================

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Config ───────────────────────────────────────────────────
DOWNLOAD_DIR="$HOME/storage/downloads/Termux-Downloader"
AUDIO_DIR="$DOWNLOAD_DIR/Audio"
VIDEO_DIR="$DOWNLOAD_DIR/Video"
IMAGE_DIR="$DOWNLOAD_DIR/Images"
FILE_DIR="$DOWNLOAD_DIR/Files"
TEMP_DIR="$DOWNLOAD_DIR/.tmp"

# ── Helpers ──────────────────────────────────────────────────
print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════╗"
  echo "║      Termux Smart Downloader         ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${RESET}"
}

print_section() {
  echo -e "\n${BLUE}${BOLD}▶ $1${RESET}"
}

success() { echo -e "${GREEN}✔ $1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $1${RESET}"; }
error()   { echo -e "${RED}✖ $1${RESET}"; }
info()    { echo -e "${CYAN}ℹ $1${RESET}"; }

ask() {
  echo -ne "${MAGENTA}${BOLD}$1${RESET} "
  read -r REPLY
  echo "$REPLY"
}

confirm() {
  # confirm "message" → returns 0 for yes, 1 for no
  local ans
  ans=$(ask "$1 [y/N]:")
  [[ "$ans" =~ ^[Yy]$ ]]
}

make_dirs() {
  mkdir -p "$AUDIO_DIR" "$VIDEO_DIR" "$IMAGE_DIR" "$FILE_DIR" "$TEMP_DIR"
}

check_deps() {
  local missing=()
  for cmd in yt-dlp ffmpeg curl wget; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Missing tools: ${missing[*]}"
    if confirm "Install missing packages now?"; then
      pkg update -y
      for pkg in "${missing[@]}"; do
        case "$pkg" in
          yt-dlp) pip install -U yt-dlp ;;
          ffmpeg) pkg install -y ffmpeg ;;
          curl)   pkg install -y curl ;;
          wget)   pkg install -y wget ;;
        esac
      done
    else
      error "Cannot continue without required tools."
      exit 1
    fi
  fi
}

setup_storage() {
  if [[ ! -d "$HOME/storage" ]]; then
    warn "Storage not set up. Running termux-setup-storage..."
    termux-setup-storage
    sleep 2
  fi
}

human_size() {
  local file="$1"
  if [[ -f "$file" ]]; then
    du -sh "$file" 2>/dev/null | cut -f1
  else
    echo "unknown"
  fi
}

# ── Compression ──────────────────────────────────────────────
compress_audio() {
  local input="$1"
  local output="${input%.*}_compressed.mp3"

  print_section "Audio Compression"
  echo -e "  ${BOLD}1)${RESET} Low quality   (~64k  — smallest)"
  echo -e "  ${BOLD}2)${RESET} Medium quality (~128k — balanced)"
  echo -e "  ${BOLD}3)${RESET} High quality   (~192k — larger)"
  echo -e "  ${BOLD}4)${RESET} Custom bitrate"
  local choice
  choice=$(ask "Choose compression level [1-4]:")

  local bitrate
  case "$choice" in
    1) bitrate="64k"  ;;
    2) bitrate="128k" ;;
    3) bitrate="192k" ;;
    4) bitrate=$(ask "Enter bitrate (e.g. 96k):") ;;
    *) warn "Invalid choice, skipping compression."; return ;;
  esac

  info "Compressing audio to ${bitrate}..."
  ffmpeg -i "$input" -b:a "$bitrate" -y "$output" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    success "Compressed: $output ($(human_size "$output"))"
    if confirm "Delete original uncompressed file?"; then
      rm -f "$input"
      success "Original deleted."
    fi
  else
    error "Compression failed."
  fi
}

compress_video() {
  local input="$1"

  print_section "Video Compression"
  echo -e "  ${BOLD}1)${RESET} Low quality    (CRF 35 — smallest file)"
  echo -e "  ${BOLD}2)${RESET} Medium quality (CRF 28 — balanced)"
  echo -e "  ${BOLD}3)${RESET} High quality   (CRF 22 — larger file)"
  echo -e "  ${BOLD}4)${RESET} Custom CRF value (18=best, 51=worst)"
  echo -e "  ${BOLD}5)${RESET} Target file size (MB)"
  local choice
  choice=$(ask "Choose compression level [1-5]:")

  local output="${input%.*}_compressed.mp4"
  local crf

  case "$choice" in
    1) crf=35 ;;
    2) crf=28 ;;
    3) crf=22 ;;
    4) crf=$(ask "Enter CRF value [18-51]:") ;;
    5)
      local target_mb
      target_mb=$(ask "Target size in MB:")
      local duration
      duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$input" 2>/dev/null)
      local bitrate
      bitrate=$(echo "scale=0; ($target_mb * 8192) / $duration" | bc)
      info "Targeting ~${target_mb}MB with bitrate ${bitrate}k..."
      ffmpeg -i "$input" -b:v "${bitrate}k" -bufsize "${bitrate}k" \
        -maxrate "${bitrate}k" -y "$output" 2>/dev/null
      if [[ $? -eq 0 ]]; then
        success "Compressed: $output ($(human_size "$output"))"
        if confirm "Delete original?"; then rm -f "$input"; fi
      else
        error "Compression failed."
      fi
      return
      ;;
    *) warn "Invalid choice, skipping compression."; return ;;
  esac

  info "Compressing video (CRF=$crf)..."
  ffmpeg -i "$input" -vcodec libx264 -crf "$crf" -preset fast \
    -acodec aac -b:a 128k -y "$output" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    success "Compressed: $output ($(human_size "$output"))"
    if confirm "Delete original?"; then rm -f "$input"; fi
  else
    error "Compression failed."
  fi
}

compress_image() {
  local input="$1"
  local ext="${input##*.}"
  local output="${input%.*}_compressed.jpg"

  print_section "Image Compression"
  echo -e "  ${BOLD}1)${RESET} Low quality    (quality 40 — smallest)"
  echo -e "  ${BOLD}2)${RESET} Medium quality (quality 65 — balanced)"
  echo -e "  ${BOLD}3)${RESET} High quality   (quality 85 — larger)"
  echo -e "  ${BOLD}4)${RESET} Custom quality [1-100]"
  local choice
  choice=$(ask "Choose compression level [1-4]:")

  local quality
  case "$choice" in
    1) quality=40 ;;
    2) quality=65 ;;
    3) quality=85 ;;
    4) quality=$(ask "Enter quality [1-100]:") ;;
    *) warn "Invalid choice, skipping compression."; return ;;
  esac

  info "Compressing image (quality=$quality)..."
  ffmpeg -i "$input" -q:v "$quality" -y "$output" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    success "Compressed: $output ($(human_size "$output"))"
    if confirm "Delete original?"; then rm -f "$input"; fi
  else
    error "Compression failed."
  fi
}

# ── Download functions ────────────────────────────────────────

download_audio() {
  local url="$1"
  print_section "Audio Download"

  echo -e "  ${BOLD}Format:${RESET}"
  echo -e "  ${BOLD}1)${RESET} MP3"
  echo -e "  ${BOLD}2)${RESET} M4A"
  echo -e "  ${BOLD}3)${RESET} OPUS"
  echo -e "  ${BOLD}4)${RESET} WAV"
  echo -e "  ${BOLD}5)${RESET} FLAC"
  local fmt_choice
  fmt_choice=$(ask "Choose format [1-5]:")
  local fmt
  case "$fmt_choice" in
    1) fmt="mp3"  ;;
    2) fmt="m4a"  ;;
    3) fmt="opus" ;;
    4) fmt="wav"  ;;
    5) fmt="flac" ;;
    *) fmt="mp3"  ;;
  esac

  echo ""
  echo -e "  ${BOLD}Quality:${RESET}"
  echo -e "  ${BOLD}1)${RESET} Best available"
  echo -e "  ${BOLD}2)${RESET} High   (~192kbps)"
  echo -e "  ${BOLD}3)${RESET} Medium (~128kbps)"
  echo -e "  ${BOLD}4)${RESET} Low    (~64kbps)"
  local q_choice
  q_choice=$(ask "Choose quality [1-4]:")
  local quality_arg
  case "$q_choice" in
    1) quality_arg="0" ;;
    2) quality_arg="2" ;;
    3) quality_arg="5" ;;
    4) quality_arg="7" ;;
    *) quality_arg="0" ;;
  esac

  info "Downloading audio as ${fmt}..."
  local out_file
  out_file=$(yt-dlp \
    --extract-audio \
    --audio-format "$fmt" \
    --audio-quality "$quality_arg" \
    --output "$AUDIO_DIR/%(title)s.%(ext)s" \
    --print after_move:filepath \
    "$url" 2>/dev/null | tail -1)

  if [[ -f "$out_file" ]]; then
    success "Saved: $out_file ($(human_size "$out_file"))"
    if confirm "Compress this audio file?"; then
      compress_audio "$out_file"
    fi
  else
    # fallback: find the most recently modified file
    out_file=$(find "$AUDIO_DIR" -name "*.${fmt}" -newer "$TEMP_DIR" 2>/dev/null | head -1)
    if [[ -f "$out_file" ]]; then
      success "Saved: $out_file ($(human_size "$out_file"))"
      if confirm "Compress this audio file?"; then
        compress_audio "$out_file"
      fi
    else
      error "Audio download failed. Check the URL and try again."
    fi
  fi
}

download_video() {
  local url="$1"
  print_section "Video Download"

  info "Fetching available formats..."
  echo ""
  yt-dlp -F "$url" 2>/dev/null | grep -E "^[0-9]|ID |---"
  echo ""

  echo -e "  ${BOLD}Quick quality select:${RESET}"
  echo -e "  ${BOLD}1)${RESET} Best quality (video+audio)"
  echo -e "  ${BOLD}2)${RESET} 1080p"
  echo -e "  ${BOLD}3)${RESET} 720p"
  echo -e "  ${BOLD}4)${RESET} 480p"
  echo -e "  ${BOLD}5)${RESET} 360p"
  echo -e "  ${BOLD}6)${RESET} Audio only (best)"
  echo -e "  ${BOLD}7)${RESET} Enter format code manually (from list above)"
  local q_choice
  q_choice=$(ask "Choose quality [1-7]:")

  local format_arg
  case "$q_choice" in
    1) format_arg="bestvideo+bestaudio/best" ;;
    2) format_arg="bestvideo[height<=1080]+bestaudio/best[height<=1080]" ;;
    3) format_arg="bestvideo[height<=720]+bestaudio/best[height<=720]" ;;
    4) format_arg="bestvideo[height<=480]+bestaudio/best[height<=480]" ;;
    5) format_arg="bestvideo[height<=360]+bestaudio/best[height<=360]" ;;
    6) format_arg="bestaudio" ;;
    7) format_arg=$(ask "Enter format code(s) (e.g. 137+140):") ;;
    *) format_arg="bestvideo+bestaudio/best" ;;
  esac

  echo ""
  echo -e "  ${BOLD}Output container:${RESET}"
  echo -e "  ${BOLD}1)${RESET} MP4 (recommended)"
  echo -e "  ${BOLD}2)${RESET} MKV"
  echo -e "  ${BOLD}3)${RESET} WEBM"
  echo -e "  ${BOLD}4)${RESET} Original (no remux)"
  local cont_choice
  cont_choice=$(ask "Choose container [1-4]:")
  local merge_fmt
  case "$cont_choice" in
    1) merge_fmt="mp4"  ;;
    2) merge_fmt="mkv"  ;;
    3) merge_fmt="webm" ;;
    4) merge_fmt=""     ;;
    *) merge_fmt="mp4"  ;;
  esac

  local merge_arg=""
  [[ -n "$merge_fmt" ]] && merge_arg="--merge-output-format $merge_fmt"

  info "Downloading video..."
  touch "$TEMP_DIR/.marker"
  yt-dlp \
    -f "$format_arg" \
    $merge_arg \
    --output "$VIDEO_DIR/%(title)s.%(ext)s" \
    "$url"

  local exit_code=$?
  local out_file
  out_file=$(find "$VIDEO_DIR" -newer "$TEMP_DIR/.marker" -type f 2>/dev/null | head -1)

  if [[ $exit_code -eq 0 && -f "$out_file" ]]; then
    success "Saved: $out_file ($(human_size "$out_file"))"
    if confirm "Compress this video?"; then
      compress_video "$out_file"
    fi
  else
    error "Video download failed. Check the URL or format code."
  fi
}

download_image() {
  local url="$1"
  print_section "Image Download"

  # Detect if it's a gallery/social media link (yt-dlp supported)
  local is_gallery=false
  if echo "$url" | grep -qiE "instagram|pinterest|flickr|reddit|imgur|twitter|x\.com|tumblr|500px"; then
    is_gallery=true
  fi

  if $is_gallery; then
    echo -e "  ${BOLD}1)${RESET} Download all images from gallery/post"
    echo -e "  ${BOLD}2)${RESET} Download single image (direct URL)"
    local g_choice
    g_choice=$(ask "Choose [1-2]:")

    if [[ "$g_choice" == "1" ]]; then
      echo ""
      echo -e "  ${BOLD}Quality/Size preference:${RESET}"
      echo -e "  ${BOLD}1)${RESET} Best available"
      echo -e "  ${BOLD}2)${RESET} Medium"
      echo -e "  ${BOLD}3)${RESET} Thumbnail only"
      local img_q
      img_q=$(ask "Choose quality [1-3]:")

      local fmt_arg
      case "$img_q" in
        1) fmt_arg="--format best" ;;
        2) fmt_arg="--format medium" ;;
        3) fmt_arg="--write-thumbnail --skip-download" ;;
        *) fmt_arg="--format best" ;;
      esac

      info "Downloading images..."
      touch "$TEMP_DIR/.marker"
      yt-dlp \
        $fmt_arg \
        --output "$IMAGE_DIR/%(uploader)s/%(title)s.%(ext)s" \
        "$url"

      local out_file
      out_file=$(find "$IMAGE_DIR" -newer "$TEMP_DIR/.marker" -type f 2>/dev/null | head -1)
      if [[ -f "$out_file" ]]; then
        success "Images saved to: $IMAGE_DIR"
        if confirm "Compress downloaded images?"; then
          find "$IMAGE_DIR" -newer "$TEMP_DIR/.marker" -type f \
            \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | \
            while read -r img; do
              compress_image "$img"
            done
        fi
      else
        error "No images downloaded."
      fi
      return
    fi
  fi

  # Direct image URL download
  local filename
  filename=$(basename "$url" | sed 's/[?#].*//')
  [[ -z "${filename##*.}" || "${filename}" == "$filename" ]] && filename="image_$(date +%s).jpg"

  echo ""
  echo -e "  Direct image download → ${BOLD}$filename${RESET}"

  info "Downloading image..."
  curl -L --progress-bar -o "$IMAGE_DIR/$filename" "$url"
  if [[ $? -eq 0 && -f "$IMAGE_DIR/$filename" ]]; then
    success "Saved: $IMAGE_DIR/$filename ($(human_size "$IMAGE_DIR/$filename"))"
    if confirm "Compress this image?"; then
      compress_image "$IMAGE_DIR/$filename"
    fi
  else
    error "Image download failed."
  fi
}

download_file() {
  local url="$1"
  print_section "File Download"

  local filename
  filename=$(ask "Save filename (leave blank for auto-detect):")
  [[ -z "$filename" ]] && filename=$(basename "$url" | sed 's/[?#].*//')
  [[ -z "$filename" ]] && filename="file_$(date +%s)"

  local out_path="$FILE_DIR/$filename"

  echo ""
  echo -e "  ${BOLD}Download tool:${RESET}"
  echo -e "  ${BOLD}1)${RESET} curl  (shows progress, most compatible)"
  echo -e "  ${BOLD}2)${RESET} wget  (resume support)"
  echo -e "  ${BOLD}3)${RESET} yt-dlp (for media sites)"
  local tool_choice
  tool_choice=$(ask "Choose tool [1-3]:")

  case "$tool_choice" in
    1)
      info "Downloading with curl..."
      curl -L --progress-bar -C - -o "$out_path" "$url"
      ;;
    2)
      info "Downloading with wget..."
      wget -c --show-progress -O "$out_path" "$url"
      ;;
    3)
      info "Downloading with yt-dlp..."
      yt-dlp --output "$FILE_DIR/%(title)s.%(ext)s" "$url"
      ;;
    *)
      info "Downloading with curl..."
      curl -L --progress-bar -C - -o "$out_path" "$url"
      ;;
  esac

  if [[ $? -eq 0 ]]; then
    success "Download complete!"
    if [[ -f "$out_path" ]]; then
      info "Saved: $out_path ($(human_size "$out_path"))"
      # Offer ffmpeg compression for known media types
      local ext="${filename##*.}"
      if echo "$ext" | grep -qiE "^(mp4|mkv|avi|mov|webm|flv)$"; then
        if confirm "Compress this video file?"; then
          compress_video "$out_path"
        fi
      elif echo "$ext" | grep -qiE "^(mp3|m4a|aac|wav|flac|ogg)$"; then
        if confirm "Compress this audio file?"; then
          compress_audio "$out_path"
        fi
      elif echo "$ext" | grep -qiE "^(jpg|jpeg|png|webp|bmp)$"; then
        if confirm "Compress this image?"; then
          compress_image "$out_path"
        fi
      fi
    fi
  else
    error "Download failed."
  fi
}

# ── Main ─────────────────────────────────────────────────────
main() {
  clear
  print_banner

  # Get URL
  local url="${1:-}"
  if [[ -z "$url" ]]; then
    url=$(ask "Enter URL to download:")
  fi

  if [[ -z "$url" ]]; then
    error "No URL provided."
    exit 1
  fi

  info "URL: $url"

  # Setup
  setup_storage
  make_dirs
  check_deps

  # Choose download type
  echo ""
  print_section "What would you like to download?"
  echo -e "  ${BOLD}1)${RESET} 🎵  Audio       (MP3, M4A, FLAC, etc.)"
  echo -e "  ${BOLD}2)${RESET} 🎬  Video       (MP4, MKV, WEBM, etc.)"
  echo -e "  ${BOLD}3)${RESET} 🖼️   Image(s)    (JPG, PNG, gallery)"
  echo -e "  ${BOLD}4)${RESET} 📁  File        (any file / direct link)"
  echo ""

  local type_choice
  type_choice=$(ask "Choose type [1-4]:")

  case "$type_choice" in
    1) download_audio "$url" ;;
    2) download_video "$url" ;;
    3) download_image "$url" ;;
    4) download_file  "$url" ;;
    *)
      error "Invalid choice."
      exit 1
      ;;
  esac

  echo ""
  echo -e "${GREEN}${BOLD}═══════════════════════════════════════${RESET}"
  success "All done! Files saved under: $DOWNLOAD_DIR"
  echo -e "${GREEN}${BOLD}═══════════════════════════════════════${RESET}"
  echo ""
}

main "$@"
