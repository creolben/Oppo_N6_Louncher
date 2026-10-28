#!/bin/sh
# Extracts every PDF in a folder the way the app does on device (see
# ColumnTextExtract.java), writing <name>.txt files for the parser tests.
#
#   tool/pdf_text/extract.sh <pdf-dir> <out-dir>
#
# Downloads PDFBox 2.0.27 from Maven Central into ~/.cache/pdfbox-2.0.27 once.
set -eu
[ $# -eq 2 ] || { echo "usage: $0 <pdf-dir> <out-dir>" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/pdfbox-2.0.27"
mkdir -p "$cache" "$2"
fetch() {
  [ -f "$cache/$2" ] || curl -sfL -o "$cache/$2" "https://repo1.maven.org/maven2/$1/$2"
}
fetch org/apache/pdfbox/pdfbox/2.0.27 pdfbox-2.0.27.jar
fetch org/apache/pdfbox/fontbox/2.0.27 fontbox-2.0.27.jar
fetch commons-logging/commons-logging/1.2 commons-logging-1.2.jar
cp="$cache/pdfbox-2.0.27.jar:$cache/fontbox-2.0.27.jar:$cache/commons-logging-1.2.jar"
for pdf in "$1"/*.pdf; do
  [ -e "$pdf" ] || continue
  name=$(basename "$pdf" .pdf)
  java -cp "$cp" "$here/ColumnTextExtract.java" "$pdf" > "$2/$name.txt"
  echo "$2/$name.txt"
done
