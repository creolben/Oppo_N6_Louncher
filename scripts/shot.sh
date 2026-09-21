#!/usr/bin/env bash
#
# shot.sh — capture a verified screenshot from a connected Android device.
#
# Why this exists
# ---------------
# The obvious way to grab a screenshot is:
#
#     adb exec-out screencap -p > shot.png
#
# On a multi-display device (any foldable, including the CPH2765 this repo
# targets) screencap writes a warning to *stdout* when no display is named:
#
#     [Warning] Multiple displays were found, but no display id was specified! ...
#
# The redirect captures those 347 bytes ahead of the real PNG data, so the file
# is not a PNG at all. Nothing complains at capture time. The damage only shows
# up later, when something tries to decode it — image viewers fail, and pasting
# one into an AI chat session returns "Could not process image" for every
# subsequent message in that session.
#
# This script closes that hole three ways:
#   1. It always passes an explicit -d <display-id>, so the warning never fires.
#   2. It captures to a file on the device and pulls it, so no image bytes ever
#      travel over stdout where they could be polluted.
#   3. It verifies the PNG signature, IEND terminator and IHDR dimensions of the
#      pulled file before it will leave it on disk. A bad capture is deleted and
#      exits non-zero instead of sitting in .agent-shots as a landmine.
#
# Usage: shot.sh --help
#
set -euo pipefail

PROG=${0##*/}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

OUT_DIR=${SHOT_OUT_DIR:-$REPO_ROOT/.agent-shots}
GROUP=""
DISPLAY_SPEC=${SHOT_DISPLAY:-active}
SERIAL=${ANDROID_SERIAL:-}
NUMBER=0
FORCE=0
QUIET=0
LIST_ONLY=0
DEV_TMP=/data/local/tmp

PNG_SIG=89504e470d0a1a0a
PNG_IEND=49454e44ae426082

# ---------------------------------------------------------------- diagnostics

die()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }
info() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

usage() {
  cat <<EOF
$PROG — capture a verified screenshot from a connected Android device.

USAGE
  $PROG [options] <name>
  $PROG --list

ARGUMENTS
  <name>                 Base filename, with or without a .png extension.
                         Unsafe characters are replaced with '-'.

OPTIONS
  -D, --display <spec>   Which display to capture. Default: active
                           active  the powered-on display (what you can see)
                           inner   the largest panel (unfolded)
                           cover   the smallest panel (folded)
                           all     every panel, suffixed -inner / -cover
                           <id>    an explicit numeric display id
  -g, --group <name>     Write into a subdirectory of the output directory.
  -o, --out <dir>        Output directory. Default: .agent-shots
  -n, --number           Prefix the file with a zero-padded sequence number,
                         continuing from the highest already in that directory.
  -s, --serial <serial>  Target device. Defaults to \$ANDROID_SERIAL, or the
                         sole attached device.
  -f, --force            Overwrite an existing file instead of refusing.
  -l, --list             Print the display table for the device and exit.
  -q, --quiet            Only print the resulting path.
  -h, --help             This message.

ENVIRONMENT
  SHOT_OUT_DIR           Default for --out.
  SHOT_DISPLAY           Default for --display.
  ANDROID_SERIAL         Default for --serial.

EXAMPLES
  $PROG home-screen
  $PROG --group polish --number lock-final
  $PROG --display inner unfolded-galaxy
  $PROG --display all ambient-layer
  $PROG --list

EXIT STATUS
  0  capture written and verified
  1  usage error, no device, or unknown display
  2  capture completed but failed verification (file was discarded)
EOF
}

# ------------------------------------------------------------------ arguments

NAME=""
while [ $# -gt 0 ]; do
  case $1 in
    -D|--display) [ $# -ge 2 ] || die "--display needs a value"; DISPLAY_SPEC=$2; shift 2 ;;
    -g|--group)   [ $# -ge 2 ] || die "--group needs a value";   GROUP=$2;        shift 2 ;;
    -o|--out)     [ $# -ge 2 ] || die "--out needs a value";     OUT_DIR=$2;      shift 2 ;;
    -s|--serial)  [ $# -ge 2 ] || die "--serial needs a value";  SERIAL=$2;       shift 2 ;;
    -n|--number)  NUMBER=1;    shift ;;
    -f|--force)   FORCE=1;     shift ;;
    -l|--list)    LIST_ONLY=1; shift ;;
    -q|--quiet)   QUIET=1;     shift ;;
    -h|--help)    usage; exit 0 ;;
    --)           shift; break ;;
    -*)           die "unknown option: $1 (try --help)" ;;
    *)            [ -z "$NAME" ] || die "unexpected extra argument: $1"; NAME=$1; shift ;;
  esac
done
[ $# -eq 0 ] || { [ -z "$NAME" ] && NAME=$1 || die "unexpected extra argument: $1"; }

# --------------------------------------------------------------- adb plumbing

command -v adb >/dev/null 2>&1 || die "adb not found on PATH"

resolve_serial() {
  # An explicit serial still gets checked. Without this the first dumpsys call
  # fails, `set -o pipefail` turns that into a silent abort, and the user sees an
  # exit code with no explanation.
  if [ -n "$SERIAL" ]; then
    local state
    state=$(adb -s "$SERIAL" get-state </dev/null 2>&1 || true)
    case $state in
      device) return 0 ;;
      *)      die "device '$SERIAL' is not usable (adb: ${state:-no response})" ;;
    esac
  fi

  local devices count
  devices=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  count=$(printf '%s\n' "$devices" | grep -c . || true)
  case $count in
    0) die "no device attached (check 'adb devices' and USB debugging)" ;;
    1) SERIAL=$devices ;;
    *) die "$count devices attached; pick one with --serial:
$(printf '%s\n' "$devices" | sed 's/^/  /')" ;;
  esac
}

# stdin is closed on every adb call. `adb shell` reads stdin, and without this it
# devours the remainder of whichever `while read` loop is driving it — which
# silently truncated --display all to a single panel.
adbd() { adb -s "$SERIAL" "$@" </dev/null; }

# Emits "<id>\t<width>\t<height>\t<state>" per physical display.
#
# Parsed out of `dumpsys display` rather than hardcoded, so this keeps working
# on a different handset or after a firmware update that reshuffles the ids.
display_table() {
  adbd shell dumpsys display 2>/dev/null | awk '
    /DisplayDeviceInfo\{/ {
      s = $0
      while (match(s, /uniqueId="local:[0-9]+"/)) {
        id   = substr(s, RSTART + 16, RLENGTH - 17)
        rest = substr(s, RSTART + RLENGTH)
        w = ""; h = ""; st = "UNKNOWN"
        if (match(rest, /^, [0-9]+ x [0-9]+,/)) {
          split(substr(rest, RSTART + 2, RLENGTH - 3), a, " x ")
          w = a[1]; h = a[2]
        }
        if (match(rest, /, state [A-Z_]+,/)) st = substr(rest, RSTART + 8, RLENGTH - 9)
        if (id != "" && w != "" && !(id in seen)) {
          seen[id] = 1
          printf "%s\t%s\t%s\t%s\n", id, w, h, st
        }
        s = rest
      }
    }' || true
  # `|| true`: an adb failure here must fall through to load_table's error
  # message rather than tripping `set -o pipefail`.
}

# Fallback for builds whose dumpsys layout we cannot parse: ids with no metadata.
display_ids_fallback() {
  adbd shell dumpsys SurfaceFlinger --display-id 2>/dev/null |
    sed -n 's/^Display \([0-9][0-9]*\) .*/\1/p' || true
}

TABLE=""
load_table() {
  TABLE=$(display_table)
  if [ -z "$TABLE" ]; then
    local id
    for id in $(display_ids_fallback); do
      TABLE="${TABLE}${id}	0	0	UNKNOWN
"
    done
  fi
  [ -n "$TABLE" ] || die "could not enumerate displays on $SERIAL"
}

# role of a display: inner = largest area, cover = smallest area
role_of() {
  printf '%s\n' "$TABLE" | awk -F'\t' -v want="$1" '
    NF >= 3 { area = $2 * $3; if (max == "" || area > max) { max = area; big = $1 }
                              if (min == "" || area < min) { min = area; small = $1 }
              n++ }
    END {
      if (n <= 1)        { print "single" }
      else if (want == big)   { print "inner" }
      else if (want == small) { print "cover" }
      else                    { print "other" }
    }'
}

field_of() { printf '%s\n' "$TABLE" | awk -F'\t' -v id="$1" -v f="$2" '$1 == id { print $f; exit }'; }

resolve_display() {
  local spec=$1
  case $spec in
    inner) printf '%s\n' "$TABLE" | awk -F'\t' 'NF>=3 { a=$2*$3; if (m=="" || a>m) { m=a; id=$1 } } END { print id }' ;;
    cover) printf '%s\n' "$TABLE" | awk -F'\t' 'NF>=3 { a=$2*$3; if (m=="" || a<m) { m=a; id=$1 } } END { print id }' ;;
    active)
      local on
      on=$(printf '%s\n' "$TABLE" | awk -F'\t' '$4 == "ON" { print $1 }' | head -1)
      if [ -n "$on" ]; then printf '%s\n' "$on"
      else printf '%s\n' "$TABLE" | awk -F'\t' 'NF { print $1; exit }'
      fi ;;
    [0-9]*)
      if [ -n "$(field_of "$spec" 1)" ]; then printf '%s\n' "$spec"
      else die "display id $spec not present on $SERIAL; run --list to see valid ids"
      fi ;;
    *) die "unknown --display value: $spec (use inner, cover, active, all, or an id)" ;;
  esac
}

print_table() {
  printf 'device %s\n' "$SERIAL"
  printf '%-22s %-12s %-8s %s\n' 'DISPLAY ID' 'RESOLUTION' 'POWER' 'ROLE'
  local id w h st
  while IFS=$'\t' read -r id w h st; do
    [ -n "$id" ] || continue
    if [ "$w" = "0" ]; then
      printf '%-22s %-12s %-8s %s\n' "$id" 'unknown' "$st" "$(role_of "$id")"
    else
      printf '%-22s %-12s %-8s %s\n' "$id" "${w}x${h}" "$st" "$(role_of "$id")"
    fi
  done <<EOF
$TABLE
EOF
}

# ------------------------------------------------------------------ png checks

hex_at()   { dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
hex_tail() { tail -c "$2" "$1" | od -An -tx1 | tr -d ' \n'; }

# Verifies structure and echoes "<width>x<height>" on success.
verify_png() {
  local f=$1 sig iend whex hhex w h

  [ -s "$f" ] || { warn "capture is empty"; return 1; }

  sig=$(hex_at "$f" 0 8)
  if [ "$sig" != "$PNG_SIG" ]; then
    warn "not a PNG: leading bytes are $sig, expected $PNG_SIG"
    # Surface the junk as text; it is almost always an adb/screencap message.
    # LC_ALL=C keeps tr from erroring on non-UTF-8 bytes in a binary file.
    warn "file begins with: $(dd if="$f" bs=1 count=120 2>/dev/null |
      LC_ALL=C tr -cd '\40-\176\n' | LC_ALL=C tr '\n' ' ')"
    return 1
  fi

  iend=$(hex_tail "$f" 8)
  if [ "$iend" != "$PNG_IEND" ]; then
    warn "PNG is truncated: missing IEND terminator (found $iend)"
    return 1
  fi

  whex=$(hex_at "$f" 16 4)
  hhex=$(hex_at "$f" 20 4)
  w=$((16#$whex))
  h=$((16#$hhex))
  if [ "$w" -le 0 ] || [ "$h" -le 0 ]; then
    warn "PNG reports a degenerate size: ${w}x${h}"
    return 1
  fi

  printf '%dx%d\n' "$w" "$h"
}

# --------------------------------------------------------------- output naming

sanitize() { printf '%s\n' "$1" | sed 's/\.[Pp][Nn][Gg]$//; s/[^A-Za-z0-9._-]/-/g; s/^-*//; s/-*$//'; }

next_number() {
  local dir=$1 highest
  highest=$(ls -1 "$dir" 2>/dev/null | sed -n 's/^\([0-9][0-9]*\)-.*/\1/p' | sort -n | tail -1)
  printf '%02d\n' $(( ${highest:-0} + 1 ))
}

# ------------------------------------------------------------------- capture

# capture <display-id> <destination>
capture() {
  local id=$1 dest=$2 remote expected_w expected_h state got role
  remote="$DEV_TMP/shot-$$-$id.png"

  state=$(field_of "$id" 4)
  role=$(role_of "$id")
  if [ "$state" != "ON" ] && [ "$state" != "UNKNOWN" ]; then
    warn "display $id ($role) is powered $state — the capture will likely be a blank frame"
  fi

  # -d is mandatory here: it is what suppresses the multi-display warning.
  # Writing to a file on device keeps image bytes off stdout entirely.
  if ! adbd shell "screencap -p -d $id '$remote'" >/dev/null 2>&1; then
    adbd shell "rm -f '$remote'" >/dev/null 2>&1 || true
    die "screencap failed on display $id"
  fi

  local tmp="$dest.part.$$"
  if ! adbd pull -a "$remote" "$tmp" >/dev/null 2>&1; then
    adbd shell "rm -f '$remote'" >/dev/null 2>&1 || true
    rm -f "$tmp"
    die "adb pull failed for display $id"
  fi
  adbd shell "rm -f '$remote'" >/dev/null 2>&1 || true

  if ! got=$(verify_png "$tmp"); then
    rm -f "$tmp"
    warn "discarded the bad capture; nothing was written to $dest"
    exit 2
  fi

  expected_w=$(field_of "$id" 2)
  expected_h=$(field_of "$id" 3)
  if [ -n "$expected_w" ] && [ "$expected_w" != "0" ] && [ "$got" != "${expected_w}x${expected_h}" ] \
     && [ "$got" != "${expected_h}x${expected_w}" ]; then
    warn "captured $got but display $id reports ${expected_w}x${expected_h}"
  fi

  # Atomic publish: callers never observe a half-written .png.
  mv -f "$tmp" "$dest"

  local bytes
  bytes=$(wc -c < "$dest" | tr -d ' ')
  info "$(printf '%-6s %-10s %8s KB  %s' "$role" "$got" "$(( bytes / 1024 ))" "$dest")"
}

# ----------------------------------------------------------------------- main

resolve_serial
load_table

if [ "$LIST_ONLY" -eq 1 ]; then
  print_table
  exit 0
fi

[ -n "$NAME" ] || { usage >&2; die "missing <name>"; }
BASE=$(sanitize "$NAME")
[ -n "$BASE" ] || die "name '$NAME' has no usable characters"

DEST_DIR=$OUT_DIR
[ -n "$GROUP" ] && DEST_DIR="$OUT_DIR/$(sanitize "$GROUP")"
mkdir -p "$DEST_DIR"

PREFIX=""
[ "$NUMBER" -eq 1 ] && PREFIX="$(next_number "$DEST_DIR")-"

if [ "$DISPLAY_SPEC" = "all" ]; then
  while IFS=$'\t' read -r id _w _h _st; do
    [ -n "$id" ] || continue
    dest="$DEST_DIR/${PREFIX}${BASE}-$(role_of "$id").png"
    [ -e "$dest" ] && [ "$FORCE" -eq 0 ] && die "$dest exists (use --force)"
    capture "$id" "$dest"
  done <<EOF
$TABLE
EOF
else
  DISPLAY_ID=$(resolve_display "$DISPLAY_SPEC")
  [ -n "$DISPLAY_ID" ] || die "could not resolve --display $DISPLAY_SPEC"
  DEST="$DEST_DIR/${PREFIX}${BASE}.png"
  [ -e "$DEST" ] && [ "$FORCE" -eq 0 ] && die "$DEST exists (use --force)"
  capture "$DISPLAY_ID" "$DEST"
  if [ "$QUIET" -eq 1 ]; then printf '%s\n' "$DEST"; fi
fi

exit 0
