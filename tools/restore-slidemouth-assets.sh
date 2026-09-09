#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pack_dir="$repo_root/assets/source-packs/slidemouth-2026-08-28"
parts_dir="$pack_dir/parts"
output_dir=${1:-"$repo_root/restored-assets/slidemouth-2026-08-28"}
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/rblx-slidemouth-assets.XXXXXX")
archive_path="$work_dir/slidemouth-2026-08-28.tar.gz"

cleanup() {
  find "$work_dir" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

(
  cd "$parts_dir"
  shasum -a 256 -c SHA256SUMS
)

cat "$parts_dir"/slidemouth-2026-08-28.tar.gz.part-* > "$archive_path"
expected='742d7324f0604e8bd6ea3500c3c2ba51f5774e2296dcdd88263b13f88a563f44'
actual=$(shasum -a 256 "$archive_path" | awk '{print $1}')

if [ "$actual" != "$expected" ]; then
  printf 'Archive checksum mismatch: expected %s, got %s\n' "$expected" "$actual" >&2
  exit 1
fi

mkdir -p "$output_dir"
tar -xzf "$archive_path" -C "$output_dir"
(
  cd "$output_dir"
  shasum -a 256 -c SHA256SUMS
)

printf 'Restored verified Slidemouth assets to %s\n' "$output_dir"
