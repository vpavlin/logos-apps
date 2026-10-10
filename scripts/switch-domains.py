#!/usr/bin/env python3
"""Point every app website link at its own <app>.vpavlin.xyz domain, in one go.

NOT run yet: use it once the per-app domains (scala.vpavlin.xyz, ...) have DNS +
GitHub Pages CNAMEs with HTTPS enforced.

Rewrites, in the given files (default: site/overrides.json and README.md):
  * https://vpavlin.github.io/<repo>[/...]       -> https://<app>.vpavlin.xyz/[...]
  * "website": "https://github.com/vpavlin/<repo>" -> "website": "https://<app>.vpavlin.xyz/"
    (KYM and WhisperBox have no site yet, so their Website link is the repo for now.
    Only "website" values are touched; "repo"/Source links keep pointing at GitHub.)

Usage:
    python3 scripts/switch-domains.py            # dry run: print what would change
    python3 scripts/switch-domains.py --write    # apply
    python3 scripts/switch-domains.py --write path/to/file ...
"""
import argparse, difflib, os, re, sys

# GitHub repo name -> app subdomain
REPO_TO_APP = {
    "scala": "scala",
    "qaku-logos": "qaku",
    "kym": "kym",
    "perun": "perun",
    "kith": "kith",
    "loam": "loam",
    "whisperbox-logos": "whisperbox",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FILES = ["site/overrides.json", "README.md"]

_alt = "|".join(re.escape(r) for r in sorted(REPO_TO_APP, key=len, reverse=True))
# vpavlin.github.io/<repo>, optionally followed by /path; the repo must end at a
# path/quote/space boundary so e.g. "loam-basecamp" never matches "loam".
PAGES_RE = re.compile(r"https?://vpavlin\.github\.io/(" + _alt + r")(?=[/\"'\s)\]>]|$)/?")
WEBSITE_RE = re.compile(
    r'("website"\s*:\s*")https://github\.com/vpavlin/(' + _alt + r')/?(")')


def rewrite(text):
    text = PAGES_RE.sub(lambda m: f"https://{REPO_TO_APP[m.group(1)]}.vpavlin.xyz/", text)
    text = WEBSITE_RE.sub(
        lambda m: f"{m.group(1)}https://{REPO_TO_APP[m.group(2)]}.vpavlin.xyz/{m.group(3)}", text)
    return text


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="files to rewrite (default: %s)" % ", ".join(DEFAULT_FILES))
    ap.add_argument("--write", action="store_true", help="apply the changes (default: dry run)")
    args = ap.parse_args()

    changed = 0
    for f in args.files or [os.path.join(ROOT, p) for p in DEFAULT_FILES]:
        if not os.path.exists(f):
            print(f"skip (missing): {f}", file=sys.stderr)
            continue
        old = open(f, encoding="utf-8").read()
        new = rewrite(old)
        if new == old:
            continue
        changed += 1
        sys.stdout.writelines(difflib.unified_diff(
            old.splitlines(True), new.splitlines(True), f, f + " (new)", n=0))
        if args.write:
            open(f, "w", encoding="utf-8").write(new)
    print(f"\n{changed} file(s) {'rewritten' if args.write else 'would change (dry run; add --write)'}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
