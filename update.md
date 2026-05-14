1. Image gallery option 2 — replaced the bogus bestvideo[height<=720]+bestaudio/... selector with a real "Thumbnails
  only" preset; the menu is now 1‑2 instead of 1‑3.
  2. Newest-file detection — added a latest_in_dir helper (find -printf '%T@\t%p' | sort -rn | head -1) and wired it
  into download_video and the image gallery branch instead of find … | head -1.
  3. wget -c -O — dropped -c; added a comment that -O is incompatible with resume.
  4. Audio filepath capture — --print after_move:filepath --no-warnings now goes to stdout while progress goes to
  /dev/tty; no more grep chain that could swallow the path or pick up a warning line.
  5. "Original (no remux)" — relabelled to "Let yt-dlp decide (default container)" so the option matches what actually
  happens.
  6. Cleanup trap — added a top-level trap cleanup EXIT and trap on_interrupt INT TERM that kills the spinner and clears
  the line.
  7. disown removed from spinner_start; the trap now handles hang-up safety, and the existing wait in spinner_stop is no
  longer fighting disown.
  8. Storage permission race — setup_storage now polls $HOME/storage/downloads for up to 60s instead of sleep 2, and
  exits with a clear message if the user never grants permission.
