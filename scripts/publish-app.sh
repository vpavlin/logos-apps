#!/usr/bin/env bash
#
# Publish an Android APK to the apps.vpavlin.xyz F-Droid repo.
#
# One command: copies the APK into the F-Droid source dir, creates its metadata
# if missing, re-signs the index with `fdroid update`, then syncs the built repo
# into vpavlin/logos-apps and pushes — which auto-rebuilds the storefront.
# Package name + versionCode + versionName are read from the APK itself.
#
# Metadata (metadata/<pkg>.yml):
#   * missing  -> created from the flags (--name and --summary required).
#   * existing -> left as is; only the fields whose flags you pass are updated
#                 (--name, --summary, --description, --category, --source, --website).
#                 A plain version bump needs just --apk.
#   * CurrentVersionCode is NEVER written, and an existing one is removed: any pin
#     makes F-Droid stop offering newer versions (the update-stranding trap).
#
# Usage:
#   scripts/publish-app.sh --apk PATH [--name "App Name"] [--summary "one line"] \
#       [--description "..."] [--category Internet] [--icon PATH] [--source URL] \
#       [--website URL] [--no-push]
#
# Env overrides (defaults suit this host):
#   FD=~/logos-apps-fdroid  FDROID=~/fdroid-venv/bin/fdroid  ANDROID_HOME=~/Android/Sdk
#   REPO_GIT=https://github.com/vpavlin/logos-apps  WORK=~/.cache/logos-apps-checkout
set -euo pipefail

FD="${FD:-$HOME/logos-apps-fdroid}"
FDROID="${FDROID:-$HOME/fdroid-venv/bin/fdroid}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
REPO_GIT="${REPO_GIT:-https://github.com/vpavlin/logos-apps}"
WORK="${WORK:-$HOME/.cache/logos-apps-checkout}"

APK="" NAME="" SUMMARY="" DESC="" CATEGORY="" ICON="" SOURCE="" WEBSITE="" PUSH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --apk) APK="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --summary) SUMMARY="$2"; shift 2;;
    --description) DESC="$2"; shift 2;;
    --category) CATEGORY="$2"; shift 2;;
    --icon) ICON="$2"; shift 2;;
    --source) SOURCE="$2"; shift 2;;
    --website) WEBSITE="$2"; shift 2;;
    --no-push) PUSH=0; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$APK" ] && [ -f "$APK" ] || { echo "ERROR: --apk PATH (existing file) required" >&2; exit 2; }
[ -x "$FDROID" ] || { echo "ERROR: fdroid not found at $FDROID" >&2; exit 2; }

# --- read identity from the APK (no need to pass it) ---
AAPT="$(ls "$ANDROID_HOME"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)"
[ -x "$AAPT" ] || { echo "ERROR: aapt not found under $ANDROID_HOME/build-tools" >&2; exit 2; }
BADGING="$("$AAPT" dump badging "$APK")"
PKG="$(sed -n "s/.*package: name='\([^']*\)'.*/\1/p" <<<"$BADGING" | head -1)"
VERCODE="$(sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" <<<"$BADGING" | head -1)"
VERNAME="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$BADGING" | head -1)"
[ -n "$PKG" ] || { echo "ERROR: could not read applicationId from APK" >&2; exit 2; }
SLUG="$(cut -d. -f3- <<<"$PKG" | tr '._' '--')"; [ -n "$SLUG" ] || SLUG="$PKG"
META="$FD/metadata/${PKG}.yml"
if [ ! -f "$META" ] && { [ -z "$NAME" ] || [ -z "$SUMMARY" ]; }; then
  echo "ERROR: $META does not exist yet: --name and --summary are required to create it" >&2; exit 2
fi
echo ">> ${NAME:-$PKG}  package=$PKG  version=$VERNAME ($VERCODE)"

# --- 1. drop the APK into the F-Droid source repo ---
cp "$APK" "$FD/repo/${SLUG}-${VERNAME}.apk"

# --- 2. metadata (REQUIRED — no yml => fdroid drops the APK silently) ---
# Create it if missing; otherwise update only the fields passed as flags and keep
# everything else (hand-written descriptions, License, IssueTracker, ...) intact.
mkdir -p "$FD/metadata"
NAME="$NAME" SUMMARY="$SUMMARY" DESC="$DESC" CATEGORY="$CATEGORY" SOURCE="$SOURCE" WEBSITE="$WEBSITE" \
python3 - "$META" <<'PY'
import json, os, re, sys
path = sys.argv[1]
env = lambda k: os.environ.get(k, "")

def scalar(v):
    # plain YAML scalar when unambiguous, else a JSON (= YAML double-quoted) string
    if (re.fullmatch(r"[A-Za-z0-9][^\n]*", v) and ": " not in v and " #" not in v
            and not v.endswith((" ", ":"))):
        return v
    return json.dumps(v, ensure_ascii=False)

def block(key, value):
    if key == "Description":
        return ["Description: |-\n"] + [("  " + l).rstrip() + "\n" for l in value.splitlines()]
    if key == "Categories":
        return ["Categories:\n", f"  - {scalar(value)}\n"]
    return [f"{key}: {scalar(value)}\n"]

# top-level key -> its lines (key line + indented continuation lines), order kept
blocks, order = {}, []
if os.path.exists(path):
    cur = None
    for line in open(path, encoding="utf-8"):
        m = re.match(r"([A-Za-z][A-Za-z0-9]*):", line)
        if m and not line[0].isspace():
            cur = m.group(1); order.append(cur); blocks[cur] = [line]
        elif cur:
            blocks[cur].append(line)
    created = False
else:
    created = True

want = {"Name": env("NAME"), "Summary": env("SUMMARY"), "Description": env("DESC"),
        "Categories": env("CATEGORY"), "SourceCode": env("SOURCE"), "WebSite": env("WEBSITE")}
if created:
    want["Description"] = want["Description"] or want["Summary"]
    want["Categories"] = want["Categories"] or "Internet"
    blocks["AuthorName"] = ["AuthorName: vpavlin\n"]; order.append("AuthorName")
changed = []
for key in ("Categories", "Name", "Summary", "Description", "SourceCode", "WebSite"):
    if not want[key]:
        continue                      # flag not given: keep the existing field
    new = block(key, want[key])
    if blocks.get(key) != new:
        if key not in blocks:
            order.append(key)
        blocks[key] = new; changed.append(key)
if "CurrentVersionCode" in blocks:    # any pin strands updates; never keep one
    print(f"   WARNING: removing CurrentVersionCode pin from {path}", file=sys.stderr)
    order.remove("CurrentVersionCode"); del blocks["CurrentVersionCode"]; changed.append("-CurrentVersionCode")
if created or changed:
    open(path, "w", encoding="utf-8").write("".join(l for k in order for l in blocks[k]))
print(f"   metadata {'created' if created else ('updated: ' + ', '.join(changed) if changed else 'unchanged')}: {path}")
PY
[ -n "$NAME" ] || NAME="$(sed -n 's/^Name: *//p' "$META" | head -1 | sed 's/^"\(.*\)"$/\1/')"

# --- 3. optional real icon (fdroid can't extract Expo/adaptive icons) ---
if [ -n "$ICON" ] && [ -f "$ICON" ]; then
  mkdir -p "$FD/metadata/${PKG}/en-US"
  cp "$ICON" "$FD/metadata/${PKG}/en-US/icon.png"
fi

# --- 4. regenerate the signed index ---
( cd "$FD" && "$FDROID" update )
python3 - "$FD/repo/index-v2.json" "$PKG" "$VERCODE" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert sys.argv[2] in d["packages"], f"{sys.argv[2]} MISSING from index — metadata problem"
p = d["packages"][sys.argv[2]]
codes = sorted(v["manifest"]["versionCode"] for v in p["versions"].values())
assert int(sys.argv[3]) in codes, f"versionCode {sys.argv[3]} MISSING from index (have {codes})"
assert int(sys.argv[3]) == codes[-1], f"versionCode {sys.argv[3]} is not the newest in the index (have {codes})"
print(f"   index OK: {sys.argv[2]} versionCode {sys.argv[3]} present + newest ({len(d['packages'])} apps total)")
PY

# --- 5. publish to vpavlin/logos-apps (serves apps.vpavlin.xyz) ---
if [ ! -d "$WORK/.git" ]; then git clone "$REPO_GIT" "$WORK"; else git -C "$WORK" pull --ff-only; fi
rsync -a --checksum --delete "$FD/repo/" "$WORK/fdroid/repo/"
cd "$WORK"
git add -A
if git diff --cached --quiet; then echo ">> no changes to publish"; exit 0; fi
git -c user.name=vpavlin -c user.email=vaclav@status.im commit -q -m "F-Droid: publish $NAME $VERNAME ($PKG)"
if [ "$PUSH" = 1 ]; then git push -q origin main && echo ">> pushed — storefront will rebuild in ~2-3 min"; else echo ">> committed locally (--no-push)"; fi
