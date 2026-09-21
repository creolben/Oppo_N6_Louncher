#!/usr/bin/env bash
#
# verify-shots.sh — audit (and optionally repair) screenshot PNGs.
#
# Companion to shot.sh. shot.sh prevents corrupt captures going forward; this
# catches anything already on disk, including files captured before the fix or
# by hand with `adb exec-out screencap -p > file.png`.
#
# The signature failure mode: a multi-display device prints a warning on stdout,
# the shell redirect stores it ahead of the PNG data, and the file silently stops
# being an image. The real PNG usually survives intact behind the junk, so --fix
# recovers it by discarding everything before the PNG signature.
#
# Usage: verify-shots.sh [--fix] [path ...]
#
set -euo pipefail

PROG=${0##*/}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

FIX=0
QUIET=0
MAX_BYTES=$((10 * 1024 * 1024))   # documented per-image limit for chat attachments
PNG_SIG=89504e470d0a1a0a
PNG_IEND=49454e44ae426082

die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
$PROG — audit (and optionally repair) screenshot PNGs.

USAGE
  $PROG [options] [path ...]

  With no path, scans .agent-shots in the repository root. Paths may be files
  or directories; directories are searched recursively.

OPTIONS
      --fix      Repair recoverable files in place. A repaired file is only
                 installed after the recovered bytes pass every check.
  -q, --quiet    Report problems only; stay silent about healthy files.
  -h, --help     This message.

CHECKS
  PNG signature, junk prefixed ahead of the signature, IEND terminator,
  IHDR dimensions, and size against the ${MAX_BYTES} byte attachment limit.

EXIT STATUS
  0  no corruption, or every corrupt file was repaired. Oversize files are
     reported but do not fail the run: they are valid images, just too large
     to attach.
  1  corruption remains (unrepaired, or not recoverable by prefix stripping)
EOF
}

TARGETS=""
while [ $# -gt 0 ]; do
  case $1 in
    --fix)      FIX=1;   shift ;;
    -q|--quiet) QUIET=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         die "unknown option: $1 (try --help)" ;;
    *)          TARGETS="${TARGETS}${1}
"; shift ;;
  esac
done
[ -n "$TARGETS" ] || TARGETS="$REPO_ROOT/.agent-shots
"

command -v perl >/dev/null 2>&1 || die "perl is required for byte-level repair"

hex_at()   { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
hex_tail() { tail -c "$2" "$1" | od -An -tx1 | tr -d ' \n'; }

# Byte offset of the PNG signature, or -1.
sig_offset() {
  perl -e 'binmode STDIN; local $/; my $d = <STDIN>; print index($d, "\x89PNG\r\n\x1a\n")' < "$1"
}

# Copy everything from the PNG signature onward.
strip_prefix() {
  perl -e 'binmode STDIN; binmode STDOUT; local $/; my $d = <STDIN>;
           my $i = index($d, "\x89PNG\r\n\x1a\n"); exit 1 if $i < 0; print substr($d, $i)' \
    < "$1" > "$2"
}

# structural_check <file> -> echoes "<w>x<h>" on success, reason on failure
structural_check() {
  local f=$1 sig iend w h
  [ -s "$f" ] || { echo "empty file"; return 1; }
  sig=$(hex_at "$f" 0 8)
  [ "$sig" = "$PNG_SIG" ] || { echo "bad signature ($sig)"; return 1; }
  iend=$(hex_tail "$f" 8)
  [ "$iend" = "$PNG_IEND" ] || { echo "truncated, no IEND"; return 1; }
  w=$((16#$(hex_at "$f" 16 4)))
  h=$((16#$(hex_at "$f" 20 4)))
  { [ "$w" -gt 0 ] && [ "$h" -gt 0 ]; } || { echo "degenerate size ${w}x${h}"; return 1; }
  printf '%dx%d\n' "$w" "$h"
}

total=0; clean=0; repaired=0; failed=0; oversize=0

report() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

check_file() {
  local f=$1 bytes offset result recovered tmp
  total=$((total + 1))
  bytes=$(wc -c < "$f" | tr -d ' ')

  if result=$(structural_check "$f"); then
    if [ "$bytes" -gt "$MAX_BYTES" ]; then
      printf 'OVERSIZE  %s  (%s, %d MB exceeds the %d MB attachment limit)\n' \
        "$f" "$result" "$((bytes / 1024 / 1024))" "$((MAX_BYTES / 1024 / 1024))"
      oversize=$((oversize + 1))
    else
      report "$(printf 'ok        %s  (%s)' "$f" "$result")"
      clean=$((clean + 1))
    fi
    return 0
  fi

  # Stripping a prefix only helps when there IS a prefix. An offset of 0 means the
  # signature is already correct and the damage is elsewhere (truncation, bad
  # IHDR) — nothing this script can repair.
  offset=$(sig_offset "$f")
  if [ "$offset" -lt 0 ]; then
    printf 'BROKEN    %s  (%s; no PNG data found, not recoverable)\n' "$f" "$result"
    failed=$((failed + 1))
    return 1
  fi
  if [ "$offset" -eq 0 ]; then
    printf 'BROKEN    %s  (%s; signature is intact so this is not prefix junk, not recoverable)\n' \
      "$f" "$result"
    failed=$((failed + 1))
    return 1
  fi

  if [ "$FIX" -eq 0 ]; then
    printf 'BROKEN    %s  (%s; %d bytes of junk prefix, recoverable with --fix)\n' \
      "$f" "$result" "$offset"
    printf '            junk: %s\n' \
      "$(dd if="$f" bs=1 count=100 2>/dev/null |
         LC_ALL=C tr -cd '\40-\176\n' | LC_ALL=C tr '\n' ' ')"
    failed=$((failed + 1))
    return 1
  fi

  tmp="$f.repair.$$"
  if ! strip_prefix "$f" "$tmp"; then
    rm -f "$tmp"
    printf 'BROKEN    %s  (could not extract PNG payload)\n' "$f"
    failed=$((failed + 1))
    return 1
  fi

  if recovered=$(structural_check "$tmp"); then
    mv -f "$tmp" "$f"
    printf 'REPAIRED  %s  (dropped %d junk bytes, now %s)\n' "$f" "$offset" "$recovered"
    repaired=$((repaired + 1))
    return 0
  fi

  rm -f "$tmp"
  printf 'BROKEN    %s  (recovered payload still invalid: %s; original untouched)\n' "$f" "$recovered"
  failed=$((failed + 1))
  return 1
}

while IFS= read -r target; do
  [ -n "$target" ] || continue
  if [ -f "$target" ]; then
    check_file "$target" || true
  elif [ -d "$target" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      check_file "$f" || true
    done <<EOF
$(find "$target" -type f -iname '*.png' | LC_ALL=C sort)
EOF
  else
    printf '%s: warning: no such path: %s\n' "$PROG" "$target" >&2
  fi
done <<EOF
$TARGETS
EOF

printf '\n%d scanned: %d clean' "$total" "$clean"
if [ "$repaired" -gt 0 ]; then printf ', %d repaired' "$repaired"; fi
if [ "$oversize" -gt 0 ]; then printf ', %d oversize' "$oversize"; fi
if [ "$failed" -gt 0 ];   then printf ', %d broken' "$failed";     fi
printf '\n'

if [ "$failed" -gt 0 ]; then
  if [ "$FIX" -eq 0 ]; then printf 'Re-run with --fix to repair the recoverable ones.\n'; fi
  exit 1
fi
exit 0
