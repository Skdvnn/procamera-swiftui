# Phase 0 — Gallery Inventory Report

**Date:** 2026-07-23  
**Repo:** ProCamera / ShutterCraft (`com.skylardann.filmcam`)  
**Branch:** `cursor/gallery-phase0-inventory-8641`  
**Status:** Inventory complete. **Do not start Phase 1 until owner re-scopes migration.**

---

## 1. Where does the existing gallery live?

| Piece | Location |
|---|---|
| App entry | `ProCameraApp.swift` → `FingerTipSceneDelegate` hosts `ContentView` |
| Gallery entry | `ContentView` → `@State showPhotoBook` → `.fullScreenCover` → `LibraryView` |
| Trigger | Thumbnail / film-strip control sets `showPhotoBook = true` |
| Main gallery file | `PhotoBook.swift` (~2,362 lines) |
| Cloud sharing | `CloudBooks.swift` (~836 lines) — CloudKit Field Book shares |

**View hierarchy (current):**

```
ContentView
└─ fullScreenCover → LibraryView(store: GalleryStore)
   ├─ Apple Books–style shelf (local covers + Shared With Me)
   └─ PhotoBookView (open book)
      ├─ ContactSheetPage (3-col index leaf)
      ├─ PrintPage (full-bleed leaf + EXIF caption)
      └─ Lightbox (pinch zoom)
```

There is **no** session-based cull UI, keep/reject marks, loupe, or compare mode.

---

## 2. Where do captured photos currently go? ⚠️ CRITICAL

**Both places — dual write. The gallery reads only the sandbox.**

### A. App sandbox (gallery source of truth)

On every capture, `ContentView.recordShot(_:)` → `GalleryStore.add(image:metadata:)`:

- Directory: `Documents/PhotoBook/`
- Full image: `{uuid}.jpg` (JPEG quality 0.9)
- Thumbnail: `{uuid}_thumb.jpg` (long edge 900, quality 0.8)
- Index: `index.json` (`[ShotMetadata]`)
- Books: `books.json` (`[Book]`)

Deleting the app **destroys** these files. The in-app gallery goes with them.

### B. System Photos library (fire-and-forget)

`CameraManager.saveToPhotoLibrary(_:)` also runs on capture:

- `PHPhotoLibrary.requestAuthorization(for: .addOnly)`
- `PHAssetCreationRequest.creationRequestForAsset(from: image)`
- RAW path: `saveRawDataToPhotoLibrary` writes DNG similarly
- **No custom album** (nothing named `ShutterCraft`)
- Gallery never reads back via Photos; no `PHFetchResult`, no change observer

### Verdict for Phase 1

Photos **are** stored in the app sandbox as the product’s working library. Per the rebuild plan:

> If photos are currently stored in the app sandbox, Phase 1 becomes a migration and needs to be re-scoped with the owner before starting.

**Stop here for implementation.** Owner decisions needed:

1. One-time migration of sandbox JPEGs into a `ShutterCraft` Photos album?
2. Or cut over for new captures only (existing Field Book frames stay sandboxed until deleted)?
3. What happens to Field Books / CloudKit shares that key off sandbox `ShotMetadata.id`?

---

## 3. Current data model / local metadata store

**No SwiftData, Core Data, or SQLite.** JSON + files only.

### `ShotMetadata` (`PhotoBook.swift`)

```
id: UUID
date: Date
iso: Int
shutter: String
aperture: Float
ev: Float
filmFilter: String
lensFX: String
focalLength: Int
```

### `Book`

```
id, title, createdAt, shotIDs: [UUID], pinnedShotIDs: Set<UUID>
```

### Gaps vs Phase 1c `FrameMark`

- No keep / reject / unmarked state
- No `PHAsset.localIdentifier` linkage
- No favorite mirroring
- Rich capture metadata already exists (valuable for Phase 3 strip) but is UUID-keyed to sandbox files, not Photos assets

CloudKit (`CloudBooks.swift`) uploads sandbox JPEGs as `CKAsset`s for shared books — orthogonal to Photos, and a non-goal conflict if sharing stays.

---

## 4. Image loading

| Mechanism | In use? |
|---|---|
| `PHCachingImageManager` | **No** |
| `PHImageManager` | **No** |
| Manual file load | **Yes** — `UIImage(contentsOfFile:)` |
| Thumb cache | `NSCache` in `GalleryStore` |
| Grid thumbs | Pre-baked 900px JPEG on disk |

Performance model today is “load our own small files,” not PhotosKit prefetch. Phase 2’s ±30-asset `PHCachingImageManager` window is net-new.

---

## 5. What in the current gallery is worth keeping?

### Aligns with “darkroom / contact sheet”

| Asset | Why keep / adapt |
|---|---|
| `ContactSheetPage` | Already a 3-col proof sheet with monospaced `Nº 001` frame numbers, warm dark ground (`#1c1916` → `#141210`), index header — closest existing metaphor |
| `PrintPage` caption | Monospaced ISO / shutter / EV / film / FX strip — directly useful for Phase 3 metadata strip |
| `DS.accent` gold (`1.0, 0.85, 0.35`) | Matches amber affirmative language |
| `ControlsGrain` | Existing control grain in `ContentView` — reuse at low opacity on sheet (do not invent a second texture) |
| `DS.mono` / monospaced captions | Already the house face for numbers |
| `ContactCellButtonStyle` | Short ease-out press (0.12s) — closer to “mechanical” than springs |

### Conflicts / discard for cull front door

| Asset | Issue |
|---|---|
| Field Book shelf (`LibraryView`) | Albums-as-collections + CloudKit sharing — explicit non-goals for the cull product |
| Page-curl book UX | Beautiful, wrong job for post-shoot cull |
| Widespread `.spring(...)` | Spec: no spring / bounce; motion should be damped ease-out |
| Per-frame delete mid-browse | Spec: rejection is local mark only; one batched delete at finish |
| `Lightbox` | Pinch zoom only — not a loupe, not synced compare |
| White-border print cells | Closer to mounted prints than light-table hairline gold rules |

### Thumb dial

`FocusDial` / exposure dials live in `AnalogGaugeView.swift` on the camera UI. Reusable as optional cull scrubber (Phase 3) if it doesn’t compromise swipe-up/down.

---

## 6. Deployment target & Swift / SwiftUI

| Setting | Value |
|---|---|
| iOS deployment | **17.0** |
| Swift (`SWIFT_VERSION`) | **5.0** (project setting; README claims 5.9+) |
| UI | SwiftUI throughout |
| Display names | Debug: “Shutter DEV”; Release: “Shutter cam” |
| Bundle IDs | `com.skylardann.filmcam` / `.dev` |
| Photos entitlements | Usage strings only (`NSPhotoLibraryAddUsageDescription`, `NSPhotoLibraryUsageDescription`) — currently requesting **`.addOnly`**, not `.readWrite` |
| CloudKit | Entitled (`iCloud.com.skylardann.filmcam`) for Field Book shares |

SwiftData is available on the deployment target if Phase 1c proceeds after re-scope.

---

## Implications for later phases (do not implement yet)

1. **Phase 1 is a migration**, not a greenfield Photos-only cutover. Dual-write exists today; gallery identity is sandbox UUID, not `PHAsset.localIdentifier`.
2. **Authorization must upgrade** from `.addOnly` to `.readWrite` (and handle `.limited`) before the app can own a `ShutterCraft` album or batch-delete rejects.
3. **Field Book / CloudKit** is a large parallel product surface. Cull rebuild should either (a) replace the thumbnail entry with the contact-sheet front door and leave Field Book behind a secondary path, or (b) explicitly deprecate it — owner call.
4. **Reuse candidates:** `ContactSheetPage` layout language, EXIF caption pattern, `ControlsGrain`, `DS.accent`, dials — not the shelf/book model or spring-heavy transitions.
5. **Phases 1–3** remain the shippable core once migration is scoped; 4–6 wait on dogfooding as planned.

---

## Owner blockers (need answers before Phase 1)

1. Confirm migration strategy for existing `Documents/PhotoBook` frames → Photos `ShutterCraft` album.
2. Confirm fate of Field Books + CloudKit sharing relative to the cull front door.
3. Confirm whether RAW DNGs already in Photos should be clustered into sessions alongside processed previews (today both land in the camera roll with no album).
