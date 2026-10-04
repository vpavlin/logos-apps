# Publishing an app to the F-Droid repo (apps.vpavlin.xyz)

This repo (`vpavlin/logos-apps`) is the **storefront + F-Droid repo**. Adding an
app is: drop the signed APK into the F-Droid source dir, write its metadata, run
`fdroid update` to re-sign the index, then sync the built `repo/` into this repo
and push. The storefront rebuilds automatically and the app appears in the
**Android** tab.

## Setup (already in place on this host)

| Thing | Value |
|-------|-------|
| F-Droid **source** dir | `~/logos-apps-fdroid` (has `config.yml`, `keystore.p12`, keyalias `logosapps`) |
| `fdroid` binary | `~/fdroid-venv/bin/fdroid` (needs `ANDROID_HOME=~/Android/Sdk`) |
| Repo **fingerprint** | `2373710A76ACB09F287F053E99E533F9D3685529C44E9027CDBC79B1DC0C9105` |
| Published to | `github.com/vpavlin/logos-apps` → `apps.vpavlin.xyz/fdroid/repo` |

The APK is signed with the **app's** release key; the **index** is signed with
the **repo** keystore (`logosapps`) — two different keys. That's expected.

## One command (recommended — for you or an agent)

From a checkout of this repo (`vpavlin/logos-apps`):

```sh
scripts/publish-app.sh \
  --apk     path/to/shrooms-release.apk \
  --name    "Shrooms" \
  --summary "Mesh VPN on Logos" \
  --source  "https://github.com/<owner>/<repo>" \
  [--description "..."] [--category Internet] [--icon path/to/icon.png]
```

It reads the `applicationId` + `versionCode` + `versionName` straight from the
APK, creates the metadata if it doesn't exist yet, runs `fdroid update`, syncs
the built repo into this repo and pushes — the storefront rebuilds and the app appears in the **Android**
tab in ~2–3 min. Add `--no-push` to stage without publishing. It verifies the
new versionCode actually landed in `index-v2.json` (and is the newest) and fails
loudly if the metadata is wrong.

**Updating an app that's already published** needs only the APK:

```sh
scripts/publish-app.sh --apk path/to/app-release.apk
```

An existing `metadata/<pkg>.yml` is kept as is (hand-written description,
License, IssueTracker…). Only fields you pass a flag for are changed
(`--name`, `--summary`, `--description`, `--category`, `--source`, `--website`).
`--name` and `--summary` are required only when the yml doesn't exist yet.
The script never writes `CurrentVersionCode` and removes one if it finds it
(see Gotchas).

## Manual steps (what the script does under the hood)

```sh
export ANDROID_HOME=$HOME/Android/Sdk
FD=$HOME/logos-apps-fdroid
PKG=<applicationId>          # e.g. dev.logos.vpn, or the new Shrooms id if renamed
VER=<versionName>            # e.g. 0.3.0

# 1. Build the signed release APK (however Shrooms builds — Expo: `gradlew :app:assembleRelease`).
#    Then copy it in with a clear name:
cp path/to/shrooms-release.apk "$FD/repo/shrooms-$VER.apk"

# 2. Metadata — REQUIRED, or `fdroid update` silently drops the APK and the app never shows.
[ -f "$FD/metadata/$PKG.yml" ] || cat > "$FD/metadata/$PKG.yml" <<YML
AuthorName: vpavlin
Categories:
  - Internet
Name: Shrooms
Summary: Mesh VPN on Logos
Description: |-
  Shrooms (formerly Logos VPN) — a peer-to-peer mesh VPN on Logos.
SourceCode: https://github.com/<owner>/<repo>
WebSite: https://<app>.vpavlin.xyz/
YML
#    Do NOT add CurrentVersionCode (see Gotchas). For an app that already has a
#    yml, skip this step: an update needs no metadata change.

# 3. (Optional) real icon — F-Droid can't extract Expo/adaptive icons, so add one:
mkdir -p "$FD/metadata/$PKG/en-US"
cp path/to/icon.png "$FD/metadata/$PKG/en-US/icon.png"

# 4. Regenerate the signed index (extracts icons, rescans every APK):
( cd "$FD" && ~/fdroid-venv/bin/fdroid update )
#   sanity: the app should now be in the index
python3 -c "import json;d=json.load(open('$FD/repo/index-v2.json'));print(list(d['packages']))"

# 5. Publish to GitHub (this repo serves apps.vpavlin.xyz):
git clone https://github.com/vpavlin/logos-apps ~/tmp-logos-apps   # or reuse a clone
rsync -a --checksum --delete "$FD/repo/" ~/tmp-logos-apps/fdroid/repo/
cd ~/tmp-logos-apps
git add -A && git commit -m "F-Droid: publish Shrooms $VER" && git push
```

Pushing `fdroid/repo/index-v2.json` triggers the **Build storefront** workflow,
which regenerates the page — Shrooms shows up in the **Android** tab within a few
minutes (the deploy re-bundles the whole F-Droid repo, so give it ~2–3 min).

## Gotchas

- **No `metadata/<pkg>.yml` → empty/incomplete index.** Always have one.
- **Never set `CurrentVersionCode`.** Any pin (even the current version) makes
  F-Droid treat that version as "current" and it then never offers newer
  versions: the app shows in the repo but phones get no update. Leave it unset
  and F-Droid suggests the highest versionCode in the repo.
- **Don't overwrite an existing yml** for a version bump. It carries
  hand-written fields (descriptions, License, IssueTracker) that a regenerated
  file would lose.
- **Publish to _this_ repo's `fdroid/repo/`**, not a stray copy — this is what
  `apps.vpavlin.xyz` serves.
- **In-place update** (same app, new version) needs the **same app signing key**
  as the installed version, or F-Droid won't offer the update.
- A brand-new `applicationId` (if Shrooms is renamed from `dev.logos.vpn`) is a
  **new app** to Android — a fresh install, not an upgrade.

There's a reusable `publish.sh` + the `logos-publish-artifacts` skill that
automate steps 2–4 for both F-Droid and Basecamp.
