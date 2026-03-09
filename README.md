# 📥 Termux Smart Downloader

A powerful, interactive Bash script for **Termux on Android** that lets you download audio, video, images, and files from virtually any URL — with built-in quality selection and FFmpeg compression at every step.

---

## ✨ Features

- 🎵 **Audio downloads** — MP3, M4A, OPUS, WAV, FLAC with quality selection
- 🎬 **Video downloads** — Lists all available formats live; quick-select 360p–1080p or enter a format code manually
- 🖼️ **Image downloads** — Direct URLs and gallery sites (Instagram, Pinterest, Reddit, Imgur, Twitter/X, Tumblr, Flickr, 500px)
- 📁 **File downloads** — Any direct file link via `curl`, `wget` (with resume), or `yt-dlp`
- 🗜️ **FFmpeg compression** — Always offered after every download, with presets and custom options for audio, video, and images
- 📂 **Organised output** — Files sorted automatically into `Audio/`, `Video/`, `Images/`, `Files/` subdirectories
- 🎨 **Coloured, interactive UI** — Clean menus, progress indicators, and prompts throughout

---

## 📋 Requirements

| Tool | Purpose |
|------|---------|
| `yt-dlp` | Audio & video downloading |
| `ffmpeg` | Compression & format conversion |
| `curl` | Direct file/image downloads |
| `wget` | File downloads with resume support |
| `termux-setup-storage` | Access to Android shared storage |

> The script will detect any missing tools and offer to install them automatically on first run.

---

## 🚀 Installation

### 1. Clone the repo

```bash
git clone https://github.com/LegendaryTunzeverywhere/Termux_smart_downloader.git
cd Termux_smart_downloader
```

### 2. Install to Termux bin

```bash
cp termux-downloader.sh $PREFIX/bin/termux-downloader
chmod +x $PREFIX/bin/termux-downloader
```

### 3. Install dependencies

```bash
pkg update && pkg install ffmpeg curl wget -y
pip install -U yt-dlp
```

### 4. Set up storage (first time only)

```bash
termux-setup-storage
```

---

## 🔗 Share from Browser (Optional but Recommended)

Set up a Termux share handler so you can share any link directly from Chrome or any other app:

```bash
# Requires the Termux:Widget app from F-Droid
mkdir -p ~/.shortcuts/tasks

cat > ~/.shortcuts/tasks/Download.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-downloader "$TERMUX_SHARED_URL"
EOF

chmod +x ~/.shortcuts/tasks/Download.sh
```

Then long-press the Termux:Widget on your home screen and select **Download**.  
Or share any URL from your browser → **Share → Termux**.

---

## 🎮 Usage

### Run directly

```bash
termux-downloader
# then paste a URL when prompted
```

### Pass URL as argument

```bash
termux-downloader "https://www.youtube.com/watch?v=..."
```

---

## 🎛️ Download Modes

### 🎵 Audio
| Option | Detail |
|--------|--------|
| Formats | MP3, M4A, OPUS, WAV, FLAC |
| Quality | Best / High (~192kbps) / Medium (~128kbps) / Low (~64kbps) |
| Compression | Bitrate presets (64k / 128k / 192k) or custom |

### 🎬 Video
| Option | Detail |
|--------|--------|
| Format listing | Live `yt-dlp -F` output shown before selection |
| Quick select | Best / 1080p / 720p / 480p / 360p / Audio only |
| Manual | Enter any format code (e.g. `137+140`) |
| Containers | MP4, MKV, WEBM, or original |
| Compression | CRF presets, custom CRF, or target file size in MB |

### 🖼️ Images
| Option | Detail |
|--------|--------|
| Direct URL | Downloads any image from a direct link |
| Gallery mode | Auto-detected for Instagram, Pinterest, Reddit, Imgur, Twitter/X, Tumblr, Flickr, 500px |
| Quality | Best / Medium / Thumbnail only |
| Compression | JPEG quality presets (40 / 65 / 85) or custom 1–100 |

### 📁 Files
| Option | Detail |
|--------|--------|
| Tools | curl (with progress), wget (resume support), yt-dlp |
| Auto-detect | Offers media compression if a video/audio/image file is downloaded |

---

## 🗜️ Compression Details

FFmpeg compression is **always offered** after every download. You are never forced to compress — it's your choice each time.

**Audio compression**
- Presets: 64k · 128k · 192k
- Custom: enter any bitrate (e.g. `96k`)
- Output: compressed `.mp3` alongside original

**Video compression**
- Presets: CRF 35 (smallest) · CRF 28 (balanced) · CRF 22 (high quality)
- Custom CRF: any value from 18 (best) to 51 (worst)
- Target size: specify a size in MB and the script calculates the required bitrate
- Codec: H.264 (`libx264`) + AAC audio

**Image compression**
- Presets: quality 40 · 65 · 85
- Custom: any value from 1 to 100
- Output: compressed `.jpg`

After compression, you are asked whether to delete the original file.

---

## 📂 Output Structure

```
~/storage/downloads/Termux-Downloader/
├── Audio/
│   └── Song Title.mp3
├── Video/
│   └── Video Title.mp4
├── Images/
│   └── username/
│       └── post_title.jpg
└── Files/
    └── filename.zip
```

---

## 🛠️ Troubleshooting

**"Storage not set up"**  
Run `termux-setup-storage` and grant storage permission when prompted.

**yt-dlp fails on a URL**  
Update yt-dlp: `pip install -U yt-dlp`. Sites change their APIs frequently and yt-dlp releases fixes regularly.

**ffmpeg compression fails**  
Make sure ffmpeg is installed: `pkg install ffmpeg`. Some input formats may not be supported for the chosen output — try a different format.

**Video download missing audio**  
Choose `bestvideo+bestaudio/best` (option 1) or a format code that includes both streams (e.g. `137+140`).

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Credits

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — the backbone of audio/video downloading
- [FFmpeg](https://ffmpeg.org/) — compression and format conversion
- [Termux](https://termux.dev/) — the Android terminal that makes all of this possible
