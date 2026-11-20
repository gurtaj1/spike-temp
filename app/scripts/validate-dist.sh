#!/bin/bash
# Checks a build output folder before anything deploys it. Stage D runs it on artifacts
# built from untrusted PR code, so it trusts nothing in the folder. It refuses:
#   - a top level other than exactly worker.js (file), assets/ and migrations/ (folders)
#   - anything that isn't a regular file or a folder: symlinks, devices, FIFOs, sockets
#   - hard links (a regular file with more than one link)
#   - names outside [A-Za-z0-9._-], ".", "..", and paths deeper than MAX_DEPTH
#   - files in migrations/ not named *.sql
#   - a file over MAX_FILE bytes, more than MAX_FILES files, or over MAX_TOTAL bytes in all
# Prints counts and a verdict only, never file contents or names from the folder.
#
# Usage: validate-dist.sh <dir>     exit 0 accepted, 1 refused
# Works with bash and the find/wc of both macOS and Linux.
set -u
export LC_ALL=C
MAX_FILE=$((5 * 1024 * 1024))
MAX_TOTAL=$((10 * 1024 * 1024))
MAX_FILES=500
MAX_DEPTH=8

refuse() {
  echo "validate-dist: REFUSED: $1"
  exit 1
}

[ $# = 1 ] || refuse "usage: validate-dist.sh <dir>"
D=${1%/}
[ -n "$D" ] && [ -d "$D" ] && [ ! -L "$D" ] || refuse "not a plain folder"

# find never follows symlinks here (-P is the default), so -type sees the link itself
odd=$(find "$D" ! -type f ! -type d -print | wc -l | tr -d ' ')
[ "$odd" = 0 ] || refuse "$odd entries are not regular files or folders"
hard=$(find "$D" -type f -links +1 -print | wc -l | tr -d ' ')
[ "$hard" = 0 ] || refuse "$hard files are hard links"

top=$(cd "$D" && find . -mindepth 1 -maxdepth 1 -print | sort | tr '\n' ' ')
[ "$top" = "./assets ./migrations ./worker.js " ] || refuse "top level must be exactly worker.js, assets/, migrations/"
[ -f "$D/worker.js" ] && [ -d "$D/assets" ] && [ -d "$D/migrations" ] || refuse "wrong type at the top level"

files=0
total=0
while IFS= read -r -d '' p; do
  rel=${p#"$D"/}
  IFS=/ read -r -a parts <<<"$rel"
  [ "${#parts[@]}" -le "$MAX_DEPTH" ] || refuse "a path is deeper than $MAX_DEPTH"
  for part in "${parts[@]}"; do
    [[ "$part" =~ ^[A-Za-z0-9._-]+$ ]] || refuse "a name has characters outside [A-Za-z0-9._-]"
    [ "$part" != . ] && [ "$part" != .. ] || refuse "a name is . or .."
  done
  # A name with a newline would split into two lines above; this catches it
  [ "$(printf '%s' "$rel" | wc -l | tr -d ' ')" = 0 ] || refuse "a name contains a newline"
  if [ -f "$p" ]; then
    case $rel in
      migrations/*) [[ "$rel" =~ ^migrations/[A-Za-z0-9_-]+\.sql$ ]] || refuse "migrations/ holds a file that isn't a top-level .sql" ;;
    esac
    size=$(wc -c <"$p" | tr -d ' ')
    [ "$size" -le "$MAX_FILE" ] || refuse "a file is over $MAX_FILE bytes"
    files=$((files + 1))
    total=$((total + size))
    [ "$files" -le "$MAX_FILES" ] || refuse "more than $MAX_FILES files"
    [ "$total" -le "$MAX_TOTAL" ] || refuse "over $MAX_TOTAL bytes in all"
  fi
done < <(find "$D" -mindepth 1 -print0)

[ "$files" -ge 2 ] || refuse "too few files"
echo "validate-dist: OK, $files files, $total bytes"
