# Getting ProCamera on your iPhone

The app installs as **"Shutter cam"** and requires iOS 17.0 or later.

Every push to `master` (and `claude/*` branches) triggers the
[Build IPA](../../actions/workflows/build-ipa.yml) workflow, which produces an
**unsigned** `ProCamera-unsigned.ipa` and attaches it to the rolling
[`latest-build` release](../../releases/tag/latest-build). Apple requires every
app on a device to be signed, so pick one of the paths below.

## Path A — You have a Mac (fastest)

1. Clone the repo and open `ProCamera.xcodeproj` in Xcode 15 or newer.
2. Plug in your iPhone with a cable and unlock it. Tap **Trust** if prompted.
3. In Xcode's toolbar, select your iPhone as the run destination.
4. If Xcode complains about signing: **Signing & Capabilities** tab → check
   **Automatically manage signing** → pick your personal team (sign in with
   your Apple ID under Xcode → Settings → Accounts if it's not listed).
5. Press **Cmd+R**. The app builds, installs, and launches on your phone.
6. First launch only: on the phone go to
   **Settings → General → VPN & Device Management**, tap your developer
   profile, and tap **Trust**.

With a free Apple ID the install expires after **7 days** — just hit Cmd+R
again to refresh it. A paid Apple Developer account ($99/yr) extends this to
a year and unlocks TestFlight.

## Path B — No Mac (sideload the CI build)

You need a Windows PC or Mac once to sideload; after that, re-signing can
happen over Wi-Fi depending on the tool.

1. Download `ProCamera-unsigned.ipa` from the
   [`latest-build` release](../../releases/tag/latest-build).
2. Install a sideloading tool on your computer:
   - [Sideloadly](https://sideloadly.io/) (Windows/Mac, simplest)
   - [AltStore](https://altstore.io/) (Windows/Mac, auto-refreshes over Wi-Fi)
3. Connect your iPhone by cable, open the tool, sign in with your Apple ID,
   and point it at the `.ipa`. The tool re-signs the app with your Apple ID
   and installs it.
4. On the phone, trust your certificate under
   **Settings → General → VPN & Device Management**.

Free-account limits apply: installs expire after **7 days** (AltStore can
auto-refresh over Wi-Fi) and at most 3 sideloaded apps at a time.

## Path C — TestFlight (set-and-forget, costs money)

With a paid Apple Developer account you can distribute through TestFlight:
builds last 90 days, install over the air, and update with one tap. This
requires uploading a signed archive from Xcode (Product → Archive →
Distribute App → TestFlight). Happy to wire up automated TestFlight uploads
from CI if you go this route — it needs an App Store Connect API key added
to the repo secrets.
