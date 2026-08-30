"""One definition of "the repo file and the Studio source are the same thing".

Every tool that compares a mirrored file against a live `.Source` imports this
module, so the answer cannot differ between them. The rules are:

* Line endings are not content. The repo working tree is checked out CRLF on
  Windows; Studio serves LF. Both sides are normalised to LF before anything is
  hashed or compared.
* A manifest entry may be flagged `studioTrailingNewline`. For those entries,
  and ONLY those, Studio's source is allowed to be exactly the repo text plus
  one trailing "\\n". The count is deliberately not fixed: an exact write must
  remove the flag, while a verified +LF landing retains it.
* Nothing else is tolerated. Two trailing newlines, a trailing space, a changed
  line anywhere: those are drift, and every tool reports them as drift whether
  the entry is flagged or not.

The flag is therefore not decoration. `permits_trailing_newline` is what the
comparison functions below consult, and those functions are what the pull audit,
the push baseline check and the push post-write verification all call.
"""

from __future__ import annotations

import sys

import hashlib
from typing import Any


# A default Windows console is cp1252 and raises UnicodeEncodeError on anything
# it cannot represent -- including from argparse's --help, which renders the
# module docstring. Degrading those characters is always better than aborting a
# release tool, so replace rather than raise. Everything this file prints is
# ASCII anyway; this is the belt to that braces.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except (AttributeError, ValueError, OSError):
        pass
TRAILING_NEWLINE_FLAG = "studioTrailingNewline"

#: Outcomes of comparing a repo text with a live Studio source.
EXACT = "exact"
TRAILING_NEWLINE = "trailing-newline"
DRIFTED = "drifted"


def apply_trailing_newline_verdict(item: dict[str, Any], verdict: str) -> None:
    """Make the manifest flag describe the source that was actually observed.

    Callers must first verify the landing under the existing contract. This
    helper cannot bless drift: it only records the two successful outcomes.
    """
    if verdict == EXACT:
        item.pop(TRAILING_NEWLINE_FLAG, None)
        return
    if verdict == TRAILING_NEWLINE:
        item[TRAILING_NEWLINE_FLAG] = True
        return
    raise ValueError(f"cannot record trailing-newline state for {verdict!r}")


def trailing_newline_count(manifest: dict[str, Any]) -> int:
    """Return the number of manifest entries carrying the exact boolean flag."""
    return sum(
        1
        for item in manifest.get("items", [])
        if item.get(TRAILING_NEWLINE_FLAG) is True
    )


def refresh_trailing_newline_metadata(manifest: dict[str, Any]) -> int:
    """Reconcile the published count and contract prose with item-level facts."""
    count = trailing_newline_count(manifest)
    manifest.setdefault("counts", {})[TRAILING_NEWLINE_FLAG] = count
    manifest["finalNewlineContract"] = (
        "Entries flagged studioTrailingNewline hold exactly the canonical repo "
        "file plus one extra trailing newline in Studio. Exact landings remove "
        f"the flag. Current flagged entry count: {count}. Manifest hashes always "
        "describe the canonical repo file, never Studio's transport bytes."
    )
    return count


def normalize(text: str) -> str:
    """Line endings are not content."""
    return text.replace("\r\n", "\n")


def canonical_bytes(text: str) -> bytes:
    return normalize(text).encode("utf-8")


def sha256_of(text: str) -> str:
    """The hash every manifest entry records: the MIRRORED FILE, LF-normalised.

    Never the Studio copy. Recording Studio's bytes here is what once let a
    trailing-newline difference be written into the manifest and reported as
    "synced" -- the drift was blessed by the very field that was supposed to
    detect it.
    """
    return hashlib.sha256(canonical_bytes(text)).hexdigest()


def permits_trailing_newline(item: dict[str, Any] | None) -> bool:
    return bool(item and item.get(TRAILING_NEWLINE_FLAG) is True)


def classify(repo_text: str, studio_text: str, *, allow_trailing_newline: bool) -> str:
    """EXACT, TRAILING_NEWLINE (only when allowed), or DRIFTED."""
    repo = normalize(repo_text)
    studio = normalize(studio_text)
    if repo == studio:
        return EXACT
    if allow_trailing_newline and studio == repo + "\n":
        return TRAILING_NEWLINE
    return DRIFTED


def equivalent(repo_text: str, studio_text: str, *, allow_trailing_newline: bool) -> bool:
    """True when the two sides agree under the contract above."""
    return classify(
        repo_text, studio_text, allow_trailing_newline=allow_trailing_newline
    ) != DRIFTED


def matches_hash(expected_sha256: str, studio_text: str, *, allow_trailing_newline: bool) -> bool:
    """Compare a live source against a recorded repo hash, under the contract.

    Used where the repo text is not at hand -- the push tool's baseline check
    holds `studioSha256Before` rather than the old file.
    """
    studio = normalize(studio_text)
    if sha256_of(studio) == expected_sha256:
        return True
    if allow_trailing_newline and studio.endswith("\n"):
        return sha256_of(studio[:-1]) == expected_sha256
    return False


def describe(repo_text: str, studio_text: str, *, allow_trailing_newline: bool) -> str:
    """A one-line explanation for a report."""
    verdict = classify(
        repo_text, studio_text, allow_trailing_newline=allow_trailing_newline
    )
    if verdict == EXACT:
        return "identical"
    if verdict == TRAILING_NEWLINE:
        return "identical apart from the one permitted trailing newline in Studio"
    repo = normalize(repo_text)
    studio = normalize(studio_text)
    if studio == repo + "\n":
        return (
            "Studio holds one extra trailing newline, and this entry is NOT flagged "
            f"{TRAILING_NEWLINE_FLAG}"
        )
    return f"differs: repo {len(repo)} chars, Studio {len(studio)} chars"
