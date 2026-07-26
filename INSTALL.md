# Getting ProCamera on your iPhone

The app installs as **"Shutter"** and requires iOS 17.0 or later.

Every push to `master`, `claude/*`, or `cursor/*` (and PRs into `master`)
triggers the [Build IPA](../../actions/workflows/build-ipa.yml) workflow, which
produces an **unsigned** `ProCamera-unsigned.ipa` and attaches it to the rolling
[`latest-build` release](../../releases/tag/latest-build). Apple requires every
app on a device to be signed, so pick one of the paths below.

**Build 93 phone test pack (softer fullscreen fade + hist glass):**
[`ProCamera-unsigned.ipa`](../../releases/download/latest-build/ProCamera-unsigned.ipa)
from [`latest-build`](../../releases/tag/latest-build).

**Preferred:** `git pull` → Xcode **Cmd+R** → confirm build **93**.
Fullscreen bottom fade is lighter so it doesn't swallow the lower third of the
frame; the info-bar histogram glass gets the machined rim + exposure grid from
the old Build 78 polish that never landed on master.

Build 92: live-widget Photos fallback + camera-matched chrome on top of Build
91's memory jetsam guards.

Build 91: live FX preview downscales harder, Metal drawable is capped,
STACK LE is throttled, and background / memory-warning purges drop the
filtered frames so Debug stops jetsamming under liquid FX.

Build 90: bottom ISO/S classic grey + yellow majors restored; top strip
38pt (34 was stubby); shutter collar muted (mid-bright ring was too strong).

Build 88: compact top FOCUS / level / EV strip trimmed to 34pt.

Build 87: front camera / selfie Metal + LE upright mapping fixed
(mirrored landscape VDO was reading upside-down).

Build 86: sun-drag brightness lives on the trailing strip when liquid
FX is armed, so press-to-warp stops stealing vertical scrubs.

Build 85: viewfinder arch numbers clear the curve; the rail gets
half-stop ticks, dual stroke, end caps, and a mid pip.

Build 84: settings is always a dark liquid glass sheet with machined wells
(corner screws + inset lip). Compact FOCUS / level / EV share the same 40pt
black instrument face as the ISO scrubbers. Shutter collar is brushed mid
steel again so the outer ring doesn't disappear into the deck.

Build 83 fills the widgets. The App Group keeps six frames instead of two and
carries a stats blob, so the Home Screen shows a numbered contact sheet, a
seven-day frame histogram, and keep / unculled counts; the Looks widget marks
which look is armed; and the Lock Screen circular becomes a 36-exposure roll
gauge with a new inline accessory for the count above the clock.

**Note:** Release / TestFlight still uses the App Group
(`group.com.skylardann.filmcam`) for the richest meta (exposure, film, cull
marks). Debug relies on Photos for images + counts. See
[`docs/IOS_INTEGRATION.md`](docs/IOS_INTEGRATION.md). Film looks bake in the
full app only from Lock Screen (system camera path).

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

## Path C — TestFlight (best with a paid developer account)

Builds install over the air from the TestFlight app, last 90 days, and
update with one tap. The [TestFlight workflow](../../actions/workflows/testflight.yml)
automates the whole thing — every push to `master` archives, signs, and
uploads a build. One-time setup:

1. **Create the app record** in [App Store Connect](https://appstoreconnect.apple.com/)
   → My Apps → **+** → New App. Platform iOS, bundle ID
   `com.skylardann.filmcam` (register the bundle ID at
   [developer.apple.com/account](https://developer.apple.com/account/resources/identifiers/list)
   first if it isn't offered in the dropdown). Name and SKU can be anything.
2. **Create an API key**: App Store Connect → Users and Access →
   [Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
   → **+**. Role: **App Manager**. Download the `.p8` file (you only get one
   chance), and note the **Key ID** and **Issuer ID** shown on that page.
3. **Add three repo secrets** (GitHub → Settings → Secrets and variables →
   Actions → New repository secret):
   - `APP_STORE_CONNECT_KEY_ID` — the Key ID
   - `APP_STORE_CONNECT_ISSUER_ID` — the Issuer ID
   - `APP_STORE_CONNECT_KEY_P8` — the full contents of the `.p8` file
4. Re-run the TestFlight workflow (or push any commit). The build appears in
   App Store Connect → TestFlight a few minutes after upload finishes
   processing; add yourself as an internal tester and install via the
   TestFlight app on your phone.

Until the secrets are configured, the workflow skips itself with a warning
instead of failing.

Note: TestFlight installs the Release app ("Shutter",
`com.skylardann.filmcam`) — it lives side by side with a Debug
"Shutter DEV" install and won't touch it.
