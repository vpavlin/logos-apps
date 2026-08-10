#!/usr/bin/env bash
#
# Publish an Android APK to the apps.vpavlin.xyz F-Droid repo.
#
# One command: copies the APK into the F-Droid source dir, writes/updates its
# metadata, re-signs the index with `fdroid update`, then syncs the built repo
# into vpavlin/logos-apps and pushes — which auto-rebuilds the storefront.
# Package name + versionCode + versionName are read from the APK itself.
#
# Usage:
#   scripts/publish-app.sh --apk PATH --name "App Name" --summary "one line" \
#       [--description "..."] [--category Internet] [--icon PATH] [--source URL] \
#       [--no-push]
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

APK="" NAME="" SUMMARY="" DESC="" CATEGORY="Internet" ICON="" SOURCE="" PUSH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --apk) APK="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --summary) SUMMARY="$2"; shift 2;;
    --description) DESC="$2"; shift 2;;
    --category) CATEGORY="$2"; shift 2;;
    --icon) ICON="$2"; shift 2;;
    --source) SOURCE="$2"; shift 2;;
    --no-push) PUSH=0; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$APK" ] && [ -f "$APK" ] || { echo "ERROR: --apk PATH (existing file) required" >&2; exit 2; }
[ -n "$NAME" ] && [ -n "$SUMMARY" ] || { echo "ERROR: --name and --summary required" >&2; exit 2; }
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
echo ">> $NAME  package=$PKG  version=$VERNAME ($VERCODE)"

# --- 1. drop the APK into the F-Droid source repo ---
cp "$APK" "$FD/repo/${SLUG}-${VERNAME}.apk"

# --- 2. metadata (REQUIRED — no yml => fdroid drops the APK silently) ---
mkdir -p "$FD/metadata"
{
  echo "AuthorName: vpavlin"
  echo "Categories:"
  echo "  - $CATEGORY"
  echo "Name: $NAME"
  echo "Summary: $SUMMARY"
  echo "Description: |-"
  echo "  ${DESC:-$SUMMARY}"
  [ -n "$SOURCE" ] && echo "SourceCode: $SOURCE"
  echo "CurrentVersionCode: $VERCODE"
} > "$FD/metadata/${PKG}.yml"

# --- 3. optional real icon (fdroid can't extract Expo/adaptive icons) ---
if [ -n "$ICON" ] && [ -f "$ICON" ]; then
  mkdir -p "$FD/metadata/${PKG}/en-US"
  cp "$ICON" "$FD/metadata/${PKG}/en-US/icon.png"
fi

# --- 4. regenerate the signed index ---
( cd "$FD" && "$FDROID" update )
python3 - "$FD/repo/index-v2.json" "$PKG" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert sys.argv[2] in d["packages"], f"{sys.argv[2]} MISSING from index — metadata problem"
print(f"   index OK: {sys.argv[2]} present ({len(d['packages'])} apps total)")
PY

# --- 5. publish to vpavlin/logos-apps (serves apps.vpavlin.xyz) ---
if [ ! -d "$WORK/.git" ]; then git clone "$REPO_GIT" "$WORK"; else git -C "$WORK" pull --ff-only; fi
rsync -a --delete "$FD/repo/" "$WORK/fdroid/repo/"
cd "$WORK"
git add -A
if git diff --cached --quiet; then echo ">> no changes to publish"; exit 0; fi
git -c user.name=vpavlin -c user.email=vaclav@status.im commit -q -m "F-Droid: publish $NAME $VERNAME ($PKG)"
if [ "$PUSH" = 1 ]; then git push -q origin main && echo ">> pushed — storefront will rebuild in ~2-3 min"; else echo ">> committed locally (--no-push)"; fi
