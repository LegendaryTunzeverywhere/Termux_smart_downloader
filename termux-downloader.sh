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
  echo -ne "${MAGENTA}${BOLD}$1${RESET} " >/dev/tty
  read -r REPLY </dev/tty
}

confirm() {
  ask "$1 [y/N]:"
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

make_dirs() {
  mkdir -p "$AUDIO_DIR" "$VIDEO_DIR" "$IMAGE_DIR" "$FILE_DIR" "$TEMP_DIR"
}

check_deps() {
  local missing=()
  for cmd in yt-dlp ffmpeg curl wget bc; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Missing tools: ${missing[*]}"
    confirm "Install missing packages now?" || { error "Cannot continue without required tools."; exit 1; }
    pkg update -y
    for tool in "${missing[@]}"; do
      case "$tool" in
        yt-dlp)
          if command -v pip &>/dev/null; then
            pip install -U yt-dlp
          else
            warn "pip not found. Installing python first..."
            pkg install -y python
            pip install -U yt-dlp
          fi
          ;;
        ffmpeg) pkg install -y ffmpeg ;;
        curl)   pkg install -y curl   ;;
        wget)   pkg install -y wget   ;;
        bc)     pkg install -y bc     ;;
      esac
    done
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

# ── Progress Utilities ────────────────────────────────────────

# Spinner — used for near-instant operations (image compress, format fetch)
SPINNER_PID=""

spinner_start() {
  local label="$1"
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  (
    local i=0
    while true; do
      printf "\r  ${CYAN}${frames[$i]}${RESET}  %s..." "$label" >/dev/tty
      i=$(( (i+1) % ${#frames[@]} ))
      sleep 0.1
    done
  ) &
  SPINNER_PID=$!
  disown "$SPINNER_PID" 2>/dev/null
}

spinner_stop() {
  local label="${1:-Done}"
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
    SPINNER_PID=""
  fi
  printf "\r%-70s\r" " " >/dev/tty
  success "$label"
}

# Draw a [████░░░] bar — called by ffmpeg_progress loop
# Usage: draw_bar <percent 0-100> <label>
draw_bar() {
  local pct="$1"
  local label="$2"
  local width=30
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  local i
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty;  i++ )); do bar+="░"; done
  printf "\r  ${CYAN}[%s]${RESET} ${BOLD}%3d%%${RESET}  %s" "$bar" "$pct" "$label" >/dev/tty
}

# ffmpeg with a live percentage bar.
# Usage: ffmpeg_progress <duration_seconds> <label> <output_file> <ffmpeg_args...>
# The output file must NOT be in ffmpeg_args — it is appended here so we can
# inject -progress and -y cleanly.
ffmpeg_progress() {
  local duration_s="$1"
  local label="$2"
  local output_file="$3"
  shift 3
  # remaining args = all ffmpeg flags except -y and the output path

  local progress_pipe="$TEMP_DIR/.ffprogress_$$"
  rm -f "$progress_pipe"

  # Run ffmpeg in background; -progress writes machine-readable key=value lines
  ffmpeg "$@" \
    -progress "$progress_pipe" \
    -nostats -loglevel error \
    -y "$output_file" &
  local ffmpeg_pid=$!

  draw_bar 0 "$label"

  local pct=0
  while kill -0 "$ffmpeg_pid" 2>/dev/null; do
    if [[ -f "$progress_pipe" ]]; then
      # out_time_us = microseconds of encoded output so far
      local out_us
      out_us=$(grep '^out_time_us=' "$progress_pipe" 2>/dev/null | tail -1 | cut -d= -f2)
      if [[ -n "$out_us" && "$out_us" =~ ^[0-9]+$ && "$duration_s" -gt 0 ]]; then
        # convert µs → centiseconds, divide by duration in centiseconds → %
        pct=$(( out_us / 10000 / duration_s ))
        [[ $pct -gt 100 ]] && pct=100
        draw_bar "$pct" "$label"
      fi
    fi
    sleep 0.3
  done

  wait "$ffmpeg_pid"
  local exit_code=$?
  rm -f "$progress_pipe"

  if [[ $exit_code -eq 0 ]]; then
    draw_bar 100 "$label"
    printf "\n" >/dev/tty
  else
    printf "\r%-70s\r" " " >/dev/tty
  fi
  return $exit_code
}

# Probe media duration in whole seconds; returns 1 on failure (avoids div/0)
get_duration() {
  local file="$1"
  local d
  d=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  local secs="${d%.*}"
  [[ "$secs" =~ ^[0-9]+$ && "$secs" -gt 0 ]] && echo "$secs" || echo 1
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
  ask "Choose compression level [1-4]:"
  local choice="$REPLY"

  local bitrate
  case "$choice" in
    1) bitrate="64k"  ;;
    2) bitrate="128k" ;;
    3) bitrate="192k" ;;
    4) ask "Enter bitrate (e.g. 96k):"; bitrate="$REPLY" ;;
    *) warn "Invalid choice, skipping compression."; return ;;
  esac

  local duration
  duration=$(get_duration "$input")

  info "Compressing audio → ${bitrate}..."
  ffmpeg_progress "$duration" "Compressing audio" "$output" \
    -i "$input" -b:a "$bitrate"

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
  ask "Choose compression level [1-5]:"
  local choice="$REPLY"

  local output="${input%.*}_compressed.mp4"
  local duration
  duration=$(get_duration "$input")
  local crf

  case "$choice" in
    1) crf=35 ;;
    2) crf=28 ;;
    3) crf=22 ;;
    4) ask "Enter CRF value [18-51]:"; crf="$REPLY" ;;
    5)
      ask "Target size in MB:"; local target_mb="$REPLY"
      local bitrate
      bitrate=$(echo "scale=0; ($target_mb * 8192) / $duration - 128" | bc)
      [[ "$bitrate" -lt 100 ]] && bitrate=100
      info "Targeting ~${target_mb}MB (video ${bitrate}k + audio 128k)..."
      ffmpeg_progress "$duration" "Compressing video" "$output" \
        -i "$input" -b:v "${bitrate}k" -bufsize "${bitrate}k" \
        -maxrate "${bitrate}k" -b:a 128k
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
  ffmpeg_progress "$duration" "Compressing video" "$output" \
    -i "$input" -vcodec libx264 -crf "$crf" -preset fast \
    -acodec aac -b:a 128k

  if [[ $? -eq 0 ]]; then
    success "Compressed: $output ($(human_size "$output"))"
    if confirm "Delete original?"; then rm -f "$input"; fi
  else
    error "Compression failed."
  fi
}

compress_image() {
  local input="$1"
  local output="${input%.*}_compressed.jpg"

  print_section "Image Compression"
  echo -e "  ${BOLD}1)${RESET} Low quality    (quality 40 — smallest)"
  echo -e "  ${BOLD}2)${RESET} Medium quality (quality 65 — balanced)"
  echo -e "  ${BOLD}3)${RESET} High quality   (quality 85 — larger)"
  echo -e "  ${BOLD}4)${RESET} Custom quality [1-100]"
  ask "Choose compression level [1-4]:"
  local choice="$REPLY"

  local quality
  case "$choice" in
    1) quality=40 ;;
    2) quality=65 ;;
    3) quality=85 ;;
    4) ask "Enter quality [1-100]:"; quality="$REPLY" ;;
    *) warn "Invalid choice, skipping compression."; return ;;
  esac

  # Images compress in under a second — spinner is more appropriate than a bar
  info "Compressing image (quality=$quality)..."
  spinner_start "Compressing image"
  ffmpeg -i "$input" -q:v "$quality" -y "$output" 2>/dev/null
  local exit_code=$?
  spinner_stop "Image compressed"

  if [[ $exit_code -eq 0 ]]; then
    success "Saved: $output ($(human_size "$output"))"
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
  ask "Choose format [1-5]:"
  local fmt_choice="$REPLY"
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
  ask "Choose quality [1-4]:"
  local q_choice="$REPLY"
  local quality_arg
  case "$q_choice" in
    1) quality_arg="0" ;;
    2) quality_arg="2" ;;
    3) quality_arg="5" ;;
    4) quality_arg="7" ;;
    *) quality_arg="0" ;;
  esac

  touch "$TEMP_DIR/.marker"
  info "Downloading audio as ${fmt^^}..."
  echo ""

  # yt-dlp has a rich built-in progress display; --newline keeps each update
  # on its own line which works best in Termux (no ANSI cursor tricks needed).
  # We capture the final saved path via --print after_move:filepath.
  local out_file
  out_file=$(yt-dlp \
    --extract-audio \
    --audio-format "$fmt" \
    --audio-quality "$quality_arg" \
    --output "$AUDIO_DIR/%(title)s.%(ext)s" \
    --print after_move:filepath \
    --newline \
    "$url" 2>&1 | tee /dev/tty | grep -v '^\[' | grep -v '^$' | tail -1)

  # Strip ANSI escape codes and whitespace from captured path
  out_file=$(printf '%s' "$out_file" | sed 's/\x1b\[[0-9;]*[mK]//g' | tr -d '\r' | xargs 2>/dev/null)

  echo ""
  if [[ -f "$out_file" ]]; then
    success "Saved: $out_file ($(human_size "$out_file"))"
    if confirm "Compress this audio file?"; then
      compress_audio "$out_file"
    fi
  else
    # Fallback: find the newest matching file created after our marker
    out_file=$(find "$AUDIO_DIR" -name "*.${fmt}" -newer "$TEMP_DIR/.marker" 2>/dev/null | head -1)
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

  # Spinner while fetching format list (network call, unknown duration)
  spinner_start "Fetching available formats"
  local fmt_list
  fmt_list=$(yt-dlp -F "$url" 2>/dev/null)
  spinner_stop "Formats ready"

  echo ""
  echo "$fmt_list" | grep -E "^[0-9]|ID |---"
  echo ""

  echo -e "  ${BOLD}Quick quality select:${RESET}"
  echo -e "  ${BOLD}1)${RESET} Best quality (video+audio)"
  echo -e "  ${BOLD}2)${RESET} 1080p"
  echo -e "  ${BOLD}3)${RESET} 720p"
  echo -e "  ${BOLD}4)${RESET} 480p"
  echo -e "  ${BOLD}5)${RESET} 360p"
  echo -e "  ${BOLD}6)${RESET} Audio only (best)"
  echo -e "  ${BOLD}7)${RESET} Enter format code manually (from list above)"
  ask "Choose quality [1-7]:"
  local q_choice="$REPLY"

  local format_arg
  case "$q_choice" in
    1) format_arg="bestvideo+bestaudio/best" ;;
    2) format_arg="bestvideo[height<=1080]+bestaudio/best[height<=1080]" ;;
    3) format_arg="bestvideo[height<=720]+bestaudio/best[height<=720]"   ;;
    4) format_arg="bestvideo[height<=480]+bestaudio/best[height<=480]"   ;;
    5) format_arg="bestvideo[height<=360]+bestaudio/best[height<=360]"   ;;
    6) format_arg="bestaudio" ;;
    7) ask "Enter format code(s) (e.g. 137+140):"; format_arg="$REPLY" ;;
    *) format_arg="bestvideo+bestaudio/best" ;;
  esac

  echo ""
  echo -e "  ${BOLD}Output container:${RESET}"
  echo -e "  ${BOLD}1)${RESET} MP4 (recommended)"
  echo -e "  ${BOLD}2)${RESET} MKV"
  echo -e "  ${BOLD}3)${RESET} WEBM"
  echo -e "  ${BOLD}4)${RESET} Original (no remux)"
  ask "Choose container [1-4]:"
  local cont_choice="$REPLY"
  local merge_fmt
  case "$cont_choice" in
    1) merge_fmt="mp4"  ;;
    2) merge_fmt="mkv"  ;;
    3) merge_fmt="webm" ;;
    4) merge_fmt=""     ;;
    *) merge_fmt="mp4"  ;;
  esac

  local merge_args=()
  [[ -n "$merge_fmt" ]] && merge_args=(--merge-output-format "$merge_fmt")

  info "Downloading video..."
  echo ""
  touch "$TEMP_DIR/.marker"

  # yt-dlp's native progress display; --newline = one update per line (Termux-safe)
  yt-dlp \
    -f "$format_arg" \
    "${merge_args[@]}" \
    --output "$VIDEO_DIR/%(title)s.%(ext)s" \
    --newline \
    "$url"

  local exit_code=$?
  echo ""
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

  local is_gallery=false
  if echo "$url" | grep -qiE "instagram|pinterest|flickr|reddit|imgur|twitter|x\.com|tumblr|500px"; then
    is_gallery=true
  fi

  if $is_gallery; then
    echo -e "  ${BOLD}1)${RESET} Download all images from gallery/post"
    echo -e "  ${BOLD}2)${RESET} Download single image (direct URL)"
    ask "Choose [1-2]:"
    local g_choice="$REPLY"

    if [[ "$g_choice" == "1" ]]; then
      echo ""
      echo -e "  ${BOLD}Quality/Size preference:${RESET}"
      echo -e "  ${BOLD}1)${RESET} Best available"
      echo -e "  ${BOLD}2)${RESET} Medium (re-encoded to 720p)"
      echo -e "  ${BOLD}3)${RESET} Thumbnail only"
      ask "Choose quality [1-3]:"
      local img_q="$REPLY"

      local extra_args=()
      case "$img_q" in
        1) extra_args=() ;;
        2) extra_args=(--format "bestvideo[height<=720]+bestaudio/best[height<=720]") ;;
        3) extra_args=(--write-thumbnail --skip-download) ;;
        *) extra_args=() ;;
      esac

      info "Downloading images..."
      echo ""
      touch "$TEMP_DIR/.marker"
      yt-dlp \
        "${extra_args[@]}" \
        --output "$IMAGE_DIR/%(uploader)s/%(title)s.%(ext)s" \
        --newline \
        "$url"

      echo ""
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

  # Direct image URL — curl's --progress-bar gives a native ASCII bar
  local filename
  filename=$(basename "$url" | sed 's/[?#].*//')
  local ext="${filename##*.}"
  if [[ -z "$ext" || "$ext" == "$filename" ]]; then
    filename="image_$(date +%s).jpg"
  fi

  echo ""
  echo -e "  Direct image download → ${BOLD}$filename${RESET}"
  echo ""
  info "Downloading image..."
  # --progress-bar = native curl progress bar (####    )
  curl -L --progress-bar -o "$IMAGE_DIR/$filename" "$url"

  if [[ $? -eq 0 && -f "$IMAGE_DIR/$filename" ]]; then
    echo ""
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

  ask "Save filename (leave blank for auto-detect):"
  local filename="$REPLY"
  [[ -z "$filename" ]] && filename=$(basename "$url" | sed 's/[?#].*//')
  [[ -z "$filename" ]] && filename="file_$(date +%s)"

  local out_path="$FILE_DIR/$filename"

  echo ""
  echo -e "  ${BOLD}Download tool:${RESET}"
  echo -e "  ${BOLD}1)${RESET} curl  (progress bar, most compatible)"
  echo -e "  ${BOLD}2)${RESET} wget  (progress bar + resume support)"
  echo -e "  ${BOLD}3)${RESET} yt-dlp (for media sites)"
  ask "Choose tool [1-3]:"
  local tool_choice="$REPLY"
  echo ""

  case "$tool_choice" in
    1)
      info "Downloading with curl..."
      # --progress-bar = native curl [####    ] bar
      curl -L --progress-bar -C - -o "$out_path" "$url"
      ;;
    2)
      info "Downloading with wget..."
      # --show-progress = native wget progress bar
      wget -c --show-progress -O "$out_path" "$url"
      ;;
    3)
      info "Downloading with yt-dlp..."
      # --newline keeps each progress update on its own line (Termux-safe)
      yt-dlp --output "$FILE_DIR/%(title)s.%(ext)s" --newline "$url"
      ;;
    *)
      info "Downloading with curl..."
      curl -L --progress-bar -C - -o "$out_path" "$url"
      ;;
  esac

  local dl_exit=$?
  echo ""

  if [[ $dl_exit -eq 0 ]]; then
    success "Download complete!"
    if [[ -f "$out_path" ]]; then
      info "Saved: $out_path ($(human_size "$out_path"))"
      local ext="${filename##*.}"
      if echo "$ext" | grep -qiE "^(mp4|mkv|avi|mov|webm|flv)$"; then
        if confirm "Compress this video file?"; then compress_video "$out_path"; fi
      elif echo "$ext" | grep -qiE "^(mp3|m4a|aac|wav|flac|ogg)$"; then
        if confirm "Compress this audio file?"; then compress_audio "$out_path"; fi
      elif echo "$ext" | grep -qiE "^(jpg|jpeg|png|webp|bmp)$"; then
        if confirm "Compress this image?"; then compress_image "$out_path"; fi
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

  local url="${1:-}"
  if [[ -z "$url" ]]; then
    ask "Enter URL to download:"
    url="$REPLY"
  fi

  if [[ -z "$url" ]]; then
    error "No URL provided."
    exit 1
  fi

  info "URL: $url"

  setup_storage
  make_dirs
  check_deps

  echo ""
  print_section "What would you like to download?"
  echo -e "  ${BOLD}1)${RESET} 🎵  Audio       (MP3, M4A, FLAC, etc.)"
  echo -e "  ${BOLD}2)${RESET} 🎬  Video       (MP4, MKV, WEBM, etc.)"
  echo -e "  ${BOLD}3)${RESET} 🖼️   Image(s)    (JPG, PNG, gallery)"
  echo -e "  ${BOLD}4)${RESET} 📁  File        (any file / direct link)"
  echo ""

  ask "Choose type [1-4]:"
  local type_choice="$REPLY"

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
