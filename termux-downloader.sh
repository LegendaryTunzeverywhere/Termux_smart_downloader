#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Termux Smart Downloader  v2.1
#  Usage: termux-downloader.sh [URL]
# ============================================================

# ── Colors ───────────────────────────────────────────────────
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

SCRIPT_VERSION="2.1"
SCRIPT_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"

# Summary tracking
SUMMARY_FILE=""
SUMMARY_COMPRESSED=""
SUMMARY_TYPE=""
SUMMARY_START_TIME=""

# ── Cleanup on exit / interrupt ──────────────────────────────
SPINNER_PID=""
cleanup() {
  if [[ -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
  fi
  [[ -t 1 ]] && printf "\r%-70s\r" " " >/dev/tty 2>/dev/null
}
on_interrupt() {
  cleanup
  printf "\n" >/dev/tty 2>/dev/null
  exit 130
}
trap cleanup EXIT
trap on_interrupt INT TERM

# ── Helpers ──────────────────────────────────────────────────
print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════╗"
  echo "║    Termux Smart Downloader v${SCRIPT_VERSION}     ║"
  echo "╚══════════════════════════════════════╝"
  echo -e "${RESET}"
}

print_section() { echo -e "\n${BLUE}${BOLD}▶ $1${RESET}"; }
success()        { echo -e "${GREEN}✔ $1${RESET}"; }
warn()           { echo -e "${YELLOW}⚠ $1${RESET}"; }
error()          { echo -e "${RED}✖ $1${RESET}"; }
info()           { echo -e "${CYAN}ℹ $1${RESET}"; }

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

# ── Spinner ───────────────────────────────────────────────────
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

spinner_fail() {
  local label="${1:-Failed}"
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
    SPINNER_PID=""
  fi
  printf "\r%-70s\r" " " >/dev/tty
  error "$label"
}

# ── Progress bar ─────────────────────────────────────────────
draw_bar() {
  local pct="$1" label="$2"
  local width=30
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar="" i
  for (( i=0; i<filled; i++ )); do bar+="█"; done
  for (( i=0; i<empty;  i++ )); do bar+="░"; done
  printf "\r  ${CYAN}[%s]${RESET} ${BOLD}%3d%%${RESET}  %s" "$bar" "$pct" "$label" >/dev/tty
}

# ── ffmpeg with progress bar ──────────────────────────────────
ffmpeg_progress() {
  local duration_s="$1" label="$2" output_file="$3"
  shift 3

  local progress_pipe="$TEMP_DIR/.ffprogress_$$"
  rm -f "$progress_pipe"
  mkfifo "$progress_pipe" 2>/dev/null || { rm -f "$progress_pipe"; touch "$progress_pipe"; }

  ffmpeg "$@" \
    -progress "$progress_pipe" \
    -nostats -loglevel error \
    -y "$output_file" &
  local ffmpeg_pid=$!

  draw_bar 0 "$label"

  local pct_file="$TEMP_DIR/.ffpct_$$"
  echo 0 > "$pct_file"
  (
    while IFS= read -r line; do
      if [[ "$line" == out_time_us=* ]]; then
        local val="${line#out_time_us=}"
        if [[ "$val" =~ ^[0-9]+$ && "$duration_s" -gt 0 ]]; then
          local p=$(( val / 10000 / duration_s ))
          [[ $p -gt 100 ]] && p=100
          echo "$p" > "$pct_file"
        fi
      fi
    done < "$progress_pipe"
  ) &
  local reader_pid=$!

  while kill -0 "$ffmpeg_pid" 2>/dev/null; do
    local pct
    pct=$(cat "$pct_file" 2>/dev/null || echo 0)
    draw_bar "$pct" "$label"
    sleep 0.3
  done

  wait "$ffmpeg_pid"
  local exit_code=$?
  wait "$reader_pid" 2>/dev/null
  rm -f "$progress_pipe" "$pct_file"

  if [[ $exit_code -eq 0 ]]; then
    draw_bar 100 "$label"
    printf "\n" >/dev/tty
  else
    printf "\r%-70s\r" " " >/dev/tty
  fi
  return $exit_code
}

# ── Duration via ffprobe ──────────────────────────────────────
get_duration() {
  local file="$1"
  local d
  d=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  local secs="${d%.*}"
  [[ "$secs" =~ ^[0-9]+$ && "$secs" -gt 0 ]] && echo "$secs" || echo 1
}

# ── Latest file in dir newer than marker ─────────────────────
latest_in_dir() {
  local dir="$1" marker="$2"
  find "$dir" -newer "$marker" -type f 2>/dev/null \
    | while IFS= read -r f; do
        printf '%s\t%s\n' "$(stat -c '%Y' "$f" 2>/dev/null)" "$f"
      done \
    | sort -rn | head -1 | cut -f2-
}

# ── Human readable size ───────────────────────────────────────
human_size() {
  local file="$1"
  if [[ -f "$file" ]]; then
    du -sh "$file" 2>/dev/null | cut -f1
  else
    echo "unknown"
  fi
}

# ── Elapsed time ─────────────────────────────────────────────
elapsed_time() {
  local start="${SUMMARY_START_TIME:-0}"
  local secs=$(( $(date +%s) - start ))
  [[ $secs -lt 0 ]] && secs=0
  if [[ $secs -lt 60 ]]; then
    echo "${secs}s"
  else
    echo "$(( secs/60 ))m $(( secs%60 ))s"
  fi
}

# ── Storage setup ─────────────────────────────────────────────
setup_storage() {
  if [[ ! -d "$HOME/storage/downloads" ]]; then
    warn "Termux storage permission not set up yet."
    info "Running termux-setup-storage. Tap ALLOW on the Android permission dialog."
    termux-setup-storage
    local i=0
    while (( i < 60 )) && [[ ! -d "$HOME/storage/downloads" ]]; do
      sleep 1; i=$(( i + 1 ))
    done
    if [[ ! -d "$HOME/storage/downloads" ]]; then
      error "Storage not granted. Run 'termux-setup-storage', allow, then re-run."
      exit 1
    fi
    success "Storage permission granted."
  fi
}

# ── Dependency install helper ─────────────────────────────────
_install_pkg() {
  local name="$1"
  spinner_start "Installing $name"
  pkg install -y "$name" &>/dev/null
  spinner_stop "$name installed"
}

_install_ytdlp() {
  if ! command -v pip &>/dev/null; then
    _install_pkg python
  fi
  spinner_start "Installing yt-dlp"
  pip install -U yt-dlp &>/dev/null
  spinner_stop "yt-dlp installed"
}

# ── Check & install missing deps ─────────────────────────────
check_deps() {
  local missing=()
  for cmd in yt-dlp ffmpeg curl wget bc; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Missing tools: ${missing[*]}"
    confirm "Install missing packages now?" || {
      error "Cannot continue without required tools."
      exit 1
    }
    spinner_start "Updating package lists"
    pkg update -y &>/dev/null
    spinner_stop "Package lists updated"
    for tool in "${missing[@]}"; do
      case "$tool" in
        yt-dlp)  _install_ytdlp ;;
        ffmpeg)  _install_pkg ffmpeg ;;
        curl)    _install_pkg curl ;;
        wget)    _install_pkg wget ;;
        bc)      _install_pkg bc ;;
      esac
    done
  fi
}

# ════════════════════════════════════════════════════════════
#  VERSION CHECK & UPDATE SYSTEM
# ════════════════════════════════════════════════════════════

# Returns installed version string for a tool (empty if not found)
get_installed_version() {
  local tool="$1"
  case "$tool" in
    yt-dlp)  yt-dlp  --version 2>/dev/null | head -1 ;;
    ffmpeg)  ffmpeg  -version  2>/dev/null | grep -oP 'ffmpeg version \K\S+' | head -1 ;;
    curl)    curl    --version 2>/dev/null | grep -oP 'curl \K[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    wget)    wget    --version 2>/dev/null | grep -oP 'GNU Wget \K[0-9]+\.[0-9]+' | head -1 ;;
    bc)      bc      --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+' | head -1 ;;
    python)  python  --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    *) echo "?" ;;
  esac
}

# Returns "latest" version available from pkg/pip (best-effort)
get_latest_version() {
  local tool="$1"
  case "$tool" in
    yt-dlp)
      # pip index versions is the cleanest way; fallback to PyPI JSON API
      pip index versions yt-dlp 2>/dev/null \
        | grep -oP 'Available versions: \K[^\n]+' \
        | tr ',' ' ' | awk '{print $1}' \
      || curl -sf "https://pypi.org/pypi/yt-dlp/json" 2>/dev/null \
           | grep -oP '"version":"\K[^"]+' | head -1
      ;;
    ffmpeg|curl|wget|bc|python)
      # pkg show returns Installed/Latest lines; grab Latest
      pkg show "$tool" 2>/dev/null \
        | grep -i '^Version:' | awk '{print $2}' | head -1
      ;;
    *) echo "?" ;;
  esac
}

# Update a single tool
update_tool() {
  local tool="$1"
  case "$tool" in
    yt-dlp)
      spinner_start "Updating yt-dlp"
      pip install -U yt-dlp &>/dev/null
      spinner_stop "yt-dlp updated to $(get_installed_version yt-dlp)"
      ;;
    ffmpeg|curl|wget|bc|python)
      spinner_start "Updating $tool"
      pkg install -y "$tool" &>/dev/null
      spinner_stop "$tool updated to $(get_installed_version "$tool")"
      ;;
    *)
      warn "Don't know how to update: $tool"
      ;;
  esac
}

# Full version-check & update menu
check_versions() {
  print_section "Dependency Versions"

  local tools=(yt-dlp ffmpeg curl wget bc python)
  local -A installed
  local -A latest

  # Collect versions with spinners
  for tool in "${tools[@]}"; do
    spinner_start "Checking $tool"
    if command -v "$tool" &>/dev/null; then
      installed[$tool]=$(get_installed_version "$tool")
      latest[$tool]=$(get_latest_version "$tool")
    else
      installed[$tool]="NOT INSTALLED"
      latest[$tool]="n/a"
    fi
    # Kill spinner manually so we can print the table row cleanly
    if [[ -n "$SPINNER_PID" ]]; then
      kill "$SPINNER_PID" 2>/dev/null
      wait "$SPINNER_PID" 2>/dev/null
      SPINNER_PID=""
    fi
    printf "\r%-70s\r" " " >/dev/tty
  done

  # Print table
  echo ""
  printf "  ${BOLD}%-10s  %-20s  %-20s  %s${RESET}\n" "Tool" "Installed" "Latest (pkg)" "Status"
  printf "  %s\n" "──────────────────────────────────────────────────────────"
  for tool in "${tools[@]}"; do
    local inst="${installed[$tool]:-?}"
    local lat="${latest[$tool]:-?}"
    local status

    if [[ "$inst" == "NOT INSTALLED" ]]; then
      status="${RED}✖ missing${RESET}"
    elif [[ -z "$lat" || "$lat" == "?" || "$lat" == "n/a" ]]; then
      status="${YELLOW}? unknown${RESET}"
    elif [[ "$inst" == "$lat" ]]; then
      status="${GREEN}✔ up to date${RESET}"
    else
      status="${YELLOW}↑ update available${RESET}"
    fi

    printf "  %-10s  %-20s  %-20s  " "$tool" "$inst" "${lat:-?}"
    echo -e "$status"
  done
  echo ""

  # Offer to update outdated / install missing
  local to_update=()
  for tool in "${tools[@]}"; do
    local inst="${installed[$tool]:-?}"
    local lat="${latest[$tool]:-?}"
    if [[ "$inst" == "NOT INSTALLED" ]]; then
      to_update+=("$tool")
    elif [[ -n "$lat" && "$lat" != "?" && "$lat" != "n/a" && "$inst" != "$lat" ]]; then
      to_update+=("$tool")
    fi
  done

  if [[ ${#to_update[@]} -eq 0 ]]; then
    success "All tools are up to date!"
    return
  fi

  echo -e "  ${YELLOW}Tools needing attention:${RESET} ${to_update[*]}"
  echo ""
  echo -e "  ${BOLD}1)${RESET} Update / install all of the above"
  echo -e "  ${BOLD}2)${RESET} Choose which ones to update"
  echo -e "  ${BOLD}3)${RESET} Skip (do nothing)"
  ask "Choose [1-3]:"
  local uchoice="$REPLY"

  case "$uchoice" in
    1)
      spinner_start "Refreshing pkg lists"
      pkg update -y &>/dev/null
      spinner_stop "pkg lists refreshed"
      for tool in "${to_update[@]}"; do
        update_tool "$tool"
      done
      success "All done!"
      ;;
    2)
      spinner_start "Refreshing pkg lists"
      pkg update -y &>/dev/null
      spinner_stop "pkg lists refreshed"
      for tool in "${to_update[@]}"; do
        if confirm "Update $tool (${installed[$tool]} → ${latest[$tool]})?"; then
          update_tool "$tool"
        fi
      done
      ;;
    *)
      info "Skipped."
      ;;
  esac
}

# ════════════════════════════════════════════════════════════
#  SUMMARY SCREEN
# ════════════════════════════════════════════════════════════
print_summary() {
  local elapsed
  elapsed=$(elapsed_time)

  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}║           Download Summary           ║${RESET}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Type:${RESET}       $SUMMARY_TYPE"

  if [[ -n "$SUMMARY_FILE" && -f "$SUMMARY_FILE" ]]; then
    echo -e "  ${BOLD}File:${RESET}       $(basename "$SUMMARY_FILE")"
    echo -e "  ${BOLD}Size:${RESET}       $(human_size "$SUMMARY_FILE")"
    echo -e "  ${BOLD}Saved to:${RESET}   $(dirname "$SUMMARY_FILE")"
  elif [[ -n "$SUMMARY_FILE" ]]; then
    echo -e "  ${BOLD}Saved to:${RESET}   $SUMMARY_FILE"
  fi

  if [[ -n "$SUMMARY_COMPRESSED" && -f "$SUMMARY_COMPRESSED" ]]; then
    echo -e "  ${BOLD}Compressed:${RESET} $(basename "$SUMMARY_COMPRESSED") ($(human_size "$SUMMARY_COMPRESSED"))"
  fi

  echo -e "  ${BOLD}Duration:${RESET}   $elapsed"
  echo ""
  echo -e "${GREEN}${BOLD}  ✔ All done!${RESET}"
  echo ""
  echo -e "${BLUE}──────────────────────────────────────────${RESET}"
  echo -ne "  Press ${BOLD}[Enter]${RESET} to close... " >/dev/tty
  read -r </dev/tty
}

# ════════════════════════════════════════════════════════════
#  COMPRESSION
# ════════════════════════════════════════════════════════════
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

  ffmpeg_progress "$duration" "Compressing audio" "$output" \
    -i "$input" -b:a "$bitrate"

  if [[ $? -eq 0 ]]; then
    success "Compressed: $output ($(human_size "$output"))"
    SUMMARY_COMPRESSED="$output"
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
      bitrate=$(echo "scale=0; ($target_mb * 8192) / $duration - 128" | bc 2>/dev/null \
                | grep -oE '^-?[0-9]+' | head -1)
      [[ -z "$bitrate" || "$bitrate" -lt 100 ]] && bitrate=100
      info "Targeting ~${target_mb}MB (video ${bitrate}k + audio 128k)..."
      ffmpeg_progress "$duration" "Compressing video" "$output" \
        -i "$input" -b:v "${bitrate}k" -bufsize "${bitrate}k" \
        -maxrate "${bitrate}k" -b:a 128k
      if [[ $? -eq 0 ]]; then
        success "Compressed: $output ($(human_size "$output"))"
        SUMMARY_COMPRESSED="$output"
        if confirm "Delete original?"; then rm -f "$input"; fi
      else
        error "Compression failed."
      fi
      return
      ;;
    *) warn "Invalid choice, skipping compression."; return ;;
  esac

  ffmpeg_progress "$duration" "Compressing video" "$output" \
    -i "$input" -vcodec libx264 -crf "$crf" -preset fast \
    -acodec aac -b:a 128k

  if [[ $? -eq 0 ]]; then
    success "Compressed: $output ($(human_size "$output"))"
    SUMMARY_COMPRESSED="$output"
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

  local quality_pct qscale
  case "$choice" in
    1) quality_pct=40 ;;
    2) quality_pct=65 ;;
    3) quality_pct=85 ;;
    4) ask "Enter quality [1-100]:"; quality_pct="$REPLY" ;;
    *) warn "Invalid choice, skipping compression."; return ;;
  esac

  # ffmpeg mjpeg qscale: 2 (best) ... 31 (worst). Map user 1-100 -> 31-2.
  qscale=$(( 31 - ( quality_pct * 29 / 100 ) ))
  [[ $qscale -lt 2  ]] && qscale=2
  [[ $qscale -gt 31 ]] && qscale=31

  spinner_start "Compressing image"
  ffmpeg -i "$input" -qscale:v "$qscale" -y "$output" 2>/dev/null
  local exit_code=$?
  spinner_stop "Image compressed"

  if [[ $exit_code -eq 0 ]]; then
    success "Saved: $output ($(human_size "$output"))"
    SUMMARY_COMPRESSED="$output"
    if confirm "Delete original?"; then rm -f "$input"; fi
  else
    error "Compression failed."
  fi
}

# ════════════════════════════════════════════════════════════
#  DOWNLOAD FUNCTIONS
# ════════════════════════════════════════════════════════════

download_audio() {
  local url="$1"
  print_section "Audio Download"
  SUMMARY_TYPE="🎵 Audio"

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

  local out_file
  out_file=$(yt-dlp \
    --extract-audio \
    --audio-format "$fmt" \
    --audio-quality "$quality_arg" \
    --output "$AUDIO_DIR/%(title)s.%(ext)s" \
    --print after_move:filepath \
    --newline \
    --no-warnings \
    "$url" 2>/dev/tty)

  out_file=$(printf '%s' "$out_file" | tr -d '\r' | tail -1 | xargs 2>/dev/null)

  echo ""
  if [[ -f "$out_file" ]]; then
    SUMMARY_FILE="$out_file"
    success "Saved: $out_file ($(human_size "$out_file"))"
    if confirm "Compress this audio file?"; then compress_audio "$out_file"; fi
  else
    out_file=$(find "$AUDIO_DIR" -name "*.${fmt}" -newer "$TEMP_DIR/.marker" 2>/dev/null | head -1)
    if [[ -f "$out_file" ]]; then
      SUMMARY_FILE="$out_file"
      success "Saved: $out_file ($(human_size "$out_file"))"
      if confirm "Compress this audio file?"; then compress_audio "$out_file"; fi
    else
      error "Audio download failed. Check the URL and try again."
    fi
  fi
}

# ── fetch_formats: yt-dlp -F with timeout & error capture ────
# The root cause of the "stuck" bug:
#   yt-dlp -F run inside $() swallows stderr (errors/warnings) and
#   has no timeout — on Facebook share links it can hang indefinitely
#   because yt-dlp follows redirects, hits login walls, then retries.
#
# Fix: run yt-dlp -F with a 30s timeout, show stderr live on tty,
#   and only capture stdout (the format table).
fetch_formats() {
  local url="$1"
  local fmt_list_file="$TEMP_DIR/.fmtlist_$$"
  local fmt_err_file="$TEMP_DIR/.fmterr_$$"

  info "Fetching available formats (30s timeout)..."
  echo ""

  # Run yt-dlp with a timeout; stdout → file, stderr → tty so user sees errors
  timeout 30 yt-dlp -F "$url" \
    --no-warnings \
    >"$fmt_list_file" \
    2>/dev/tty
  local exit_code=$?

  if [[ $exit_code -eq 124 ]]; then
    error "Timed out fetching formats. The site may require login or is slow."
    rm -f "$fmt_list_file"
    return 1
  elif [[ $exit_code -ne 0 ]]; then
    warn "Could not fetch format list (exit $exit_code). Proceeding with quality presets only."
    rm -f "$fmt_list_file"
    return 1
  fi

  cat "$fmt_list_file"
  rm -f "$fmt_list_file"
  return 0
}

download_video() {
  local url="$1"
  print_section "Video Download"
  SUMMARY_TYPE="🎬 Video"

  # ── Format listing (no spinner — output goes to tty live) ──
  local fmt_list
  fmt_list=$(fetch_formats "$url")
  local fetch_ok=$?

  if [[ $fetch_ok -eq 0 && -n "$fmt_list" ]]; then
    echo ""
    echo "$fmt_list" | grep -E "^[0-9]|ID |---"
    echo ""
    success "Format list loaded"
  else
    echo ""
    warn "Skipping format table — using quality presets."
  fi

  # ── Quality selection ──────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}Quick quality select:${RESET}"
  echo -e "  ${BOLD}1)${RESET} Best quality (video+audio)"
  echo -e "  ${BOLD}2)${RESET} 1080p"
  echo -e "  ${BOLD}3)${RESET} 720p"
  echo -e "  ${BOLD}4)${RESET} 480p"
  echo -e "  ${BOLD}5)${RESET} 360p"
  echo -e "  ${BOLD}6)${RESET} Audio only (best)"
  echo -e "  ${BOLD}7)${RESET} Enter format code manually"
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

  # ── Container ─────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}Output container:${RESET}"
  echo -e "  ${BOLD}1)${RESET} MP4 (recommended)"
  echo -e "  ${BOLD}2)${RESET} MKV"
  echo -e "  ${BOLD}3)${RESET} WEBM"
  echo -e "  ${BOLD}4)${RESET} Let yt-dlp decide"
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

  yt-dlp \
    -f "$format_arg" \
    "${merge_args[@]}" \
    --output "$VIDEO_DIR/%(title)s.%(ext)s" \
    --newline \
    "$url"

  local exit_code=$?
  echo ""
  local out_file
  out_file=$(latest_in_dir "$VIDEO_DIR" "$TEMP_DIR/.marker")
  if [[ -z "$out_file" || ! -f "$out_file" ]]; then
    out_file=$(find "$VIDEO_DIR" -newer "$TEMP_DIR/.marker" -type f 2>/dev/null | head -1)
  fi

  if [[ $exit_code -eq 0 && -f "$out_file" ]]; then
    SUMMARY_FILE="$out_file"
    success "Saved: $out_file ($(human_size "$out_file"))"
    if confirm "Compress this video?"; then compress_video "$out_file"; fi
  else
    error "Video download failed. Check the URL or format code."
  fi
}

download_image() {
  local url="$1"
  print_section "Image Download"
  SUMMARY_TYPE="🖼️  Image"

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
      echo -e "  ${BOLD}1)${RESET} Best available (full resolution)"
      echo -e "  ${BOLD}2)${RESET} Thumbnails only (smallest, fastest)"
      ask "Choose quality [1-2]:"
      local img_q="$REPLY"

      local extra_args=()
      case "$img_q" in
        1) extra_args=() ;;
        2) extra_args=(--write-thumbnail --skip-download) ;;
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
      out_file=$(latest_in_dir "$IMAGE_DIR" "$TEMP_DIR/.marker")
      if [[ -f "$out_file" ]]; then
        SUMMARY_FILE="$IMAGE_DIR"
        success "Images saved to: $IMAGE_DIR"
        if confirm "Compress downloaded images?"; then
          find "$IMAGE_DIR" -newer "$TEMP_DIR/.marker" -type f \
            \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | \
            while read -r img; do compress_image "$img"; done
        fi
      else
        error "No images downloaded."
      fi
      return
    fi
  fi

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
  curl -L --progress-bar -o "$IMAGE_DIR/$filename" "$url"

  if [[ $? -eq 0 && -f "$IMAGE_DIR/$filename" ]]; then
    echo ""
    SUMMARY_FILE="$IMAGE_DIR/$filename"
    success "Saved: $IMAGE_DIR/$filename ($(human_size "$IMAGE_DIR/$filename"))"
    if confirm "Compress this image?"; then compress_image "$IMAGE_DIR/$filename"; fi
  else
    error "Image download failed."
  fi
}

download_file() {
  local url="$1"
  print_section "File Download"
  SUMMARY_TYPE="📁 File"

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
      curl -L --progress-bar -C - -o "$out_path" "$url"
      ;;
    2)
      info "Downloading with wget..."
      wget -q --show-progress -c -O "$out_path" "$url"
      ;;
    3)
      info "Downloading with yt-dlp..."
      touch "$TEMP_DIR/.marker"
      yt-dlp --output "$FILE_DIR/%(title)s.%(ext)s" --newline "$url"
      local _yt_file
      _yt_file=$(latest_in_dir "$FILE_DIR" "$TEMP_DIR/.marker")
      [[ -f "$_yt_file" ]] && out_path="$_yt_file"
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
      SUMMARY_FILE="$out_path"
      info "Saved: $out_path ($(human_size "$out_path"))"
      local ext_check="${out_path##*.}"
      if echo "$ext_check" | grep -qiE "^(mp4|mkv|avi|mov|webm|flv)$"; then
        if confirm "Compress this video file?"; then compress_video "$out_path"; fi
      elif echo "$ext_check" | grep -qiE "^(mp3|m4a|aac|wav|flac|ogg)$"; then
        if confirm "Compress this audio file?"; then compress_audio "$out_path"; fi
      elif echo "$ext_check" | grep -qiE "^(jpg|jpeg|png|webp|bmp)$"; then
        if confirm "Compress this image?"; then compress_image "$out_path"; fi
      fi
    fi
  else
    error "Download failed."
  fi
}

# ════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════
main() {
  clear
  print_banner

  # ── Pre-flight: version check option ──────────────────────
  if [[ "${1:-}" == "--check-updates" || "${1:-}" == "--update" ]]; then
    setup_storage
    make_dirs
    check_deps
    check_versions
    exit 0
  fi

  local url="${1:-}"
  if [[ -z "$url" ]]; then
    ask "Enter URL to download (or 'u' to check for updates):"
    if [[ "$REPLY" == "u" || "$REPLY" == "U" ]]; then
      setup_storage
      make_dirs
      check_deps
      check_versions
      exit 0
    fi
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

  # Reset summary
  SUMMARY_FILE=""
  SUMMARY_COMPRESSED=""
  SUMMARY_TYPE=""
  SUMMARY_START_TIME=$(date +%s)

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

  print_summary
}

main "$@"
