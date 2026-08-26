#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pack_dir="$repo_root/assets/source-packs/live-assets-2026-08-26"
parts_dir="$pack_dir/parts"
output_dir=${1:-"$repo_root/restored-assets"}
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/rblx-live-assets.XXXXXX")
archive_path="$work_dir/live-assets-2026-08-26.tar.gz"

cleanup() {
  find "$work_dir" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

(
  cd "$parts_dir"
  shasum -a 256 -c SHA256SUMS
)

cat "$parts_dir"/live-assets-2026-08-26.tar.gz.part-* > "$archive_path"
expected='4b083e73ec4606822299e245e2651f82dab48939a51f636aa5e9c6761405302e'
actual=$(shasum -a 256 "$archive_path" | awk '{print $1}')

if [ "$actual" != "$expected" ]; then
  printf 'Archive checksum mismatch: expected %s, got %s\n' "$expected" "$actual" >&2
  exit 1
fi

mkdir -p "$output_dir"
tar -xzf "$archive_path" -C "$output_dir" --strip-components=1
(
  cd "$output_dir"
  shasum -a 256 -c SHA256SUMS
)

printf 'Restored verified live assets to %s\n' "$output_dir"
