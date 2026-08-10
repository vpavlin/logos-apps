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

## Steps — publishing Shrooms (formerly Logos VPN)

```sh
export ANDROID_HOME=$HOME/Android/Sdk
FD=$HOME/logos-apps-fdroid
PKG=<applicationId>          # e.g. dev.logos.vpn, or the new Shrooms id if renamed
VER=<versionName>            # e.g. 0.3.0

# 1. Build the signed release APK (however Shrooms builds — Expo: `gradlew :app:assembleRelease`).
#    Then copy it in with a clear name:
cp path/to/shrooms-release.apk "$FD/repo/shrooms-$VER.apk"

# 2. Metadata — REQUIRED, or `fdroid update` silently drops the APK and the app never shows.
cat > "$FD/metadata/$PKG.yml" <<YML
AuthorName: vpavlin
Categories:
  - Internet
Name: Shrooms
Summary: Mesh VPN on Logos
Description: |-
  Shrooms (formerly Logos VPN) — a peer-to-peer mesh VPN on Logos.
SourceCode: https://github.com/<owner>/<repo>
CurrentVersionCode: <versionCode>
YML

# 3. (Optional) real icon — F-Droid can't extract Expo/adaptive icons, so add one:
mkdir -p "$FD/metadata/$PKG/en-US"
cp path/to/icon.png "$FD/metadata/$PKG/en-US/icon.png"

# 4. Regenerate the signed index (extracts icons, rescans every APK):
( cd "$FD" && ~/fdroid-venv/bin/fdroid update )
#   sanity: the app should now be in the index
python3 -c "import json;d=json.load(open('$FD/repo/index-v2.json'));print(list(d['packages']))"

# 5. Publish to GitHub (this repo serves apps.vpavlin.xyz):
git clone https://github.com/vpavlin/logos-apps ~/tmp-logos-apps   # or reuse a clone
rsync -a --delete "$FD/repo/" ~/tmp-logos-apps/fdroid/repo/
cd ~/tmp-logos-apps
git add -A && git commit -m "F-Droid: publish Shrooms $VER" && git push
```

Pushing `fdroid/repo/index-v2.json` triggers the **Build storefront** workflow,
which regenerates the page — Shrooms shows up in the **Android** tab within a few
minutes (the deploy re-bundles the whole F-Droid repo, so give it ~2–3 min).

## Gotchas

- **No `metadata/<pkg>.yml` → empty/incomplete index.** Always write it.
- **Publish to _this_ repo's `fdroid/repo/`**, not a stray copy — this is what
  `apps.vpavlin.xyz` serves.
- **In-place update** (same app, new version) needs the **same app signing key**
  as the installed version, or F-Droid won't offer the update.
- A brand-new `applicationId` (if Shrooms is renamed from `dev.logos.vpn`) is a
  **new app** to Android — a fresh install, not an upgrade.

There's a reusable `publish.sh` + the `logos-publish-artifacts` skill that
automate steps 2–4 for both F-Droid and Basecamp.
