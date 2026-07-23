# Revised gallery scope (owner decisions)

**Date:** 2026-07-23  
**Overrides** the Phase 0 “Photos-only source of truth” cutover.

## Plain-English product

You shoot with ShutterCraft. Photos land in **both** the app and the system Photos library.  
You **cull the shoot in the app** (keep / reject).  
When you’re done:

- **Rejects** are deleted from the app **and** from Photos.
- **Keepers** are batched into a **Photos album** so sharing happens in the native Photos app (and Field Book can still wrap that set for in-app / CloudKit share).

We are **not** rebuilding Photos.app. We are a post-shoot cutting room that hands a clean set back to Photos / friends.

## Decisions locked

| Topic | Decision |
|---|---|
| Existing sandbox photos | Ignore — no migration |
| Dual write (app + Photos) | Keep |
| Where cull happens | In-app |
| Rejects | Delete in **both** places |
| Keepers / share | Batch into a Photos album; Field Book / share stays and merges with sessions |
| RAW | Cull processed frames only (v1); RAW stays in Photos as a sibling, not a cull cell |
| Field Book | Keep — a finished session’s keepers can become / feed a book |

## Architecture (adapted Phase 1–3)

```
Capture
  ├─ sandbox JPEG + ShotMetadata (+ optional photosAssetLocalIdentifier)
  └─ Photos library (same moment; store localIdentifier on the shot)

Sessions (clustered by time gap / location)
  └─ Contact sheet front door
       └─ Cull (swipe keep/reject, undo)
            └─ Finish
                 ├─ delete rejects (sandbox + PHAsset)
                 ├─ create/update Photos album with keepers
                 └─ optional: open / create Field Book from keepers
```

## What changed vs original Phase 1 plan

- Photos is **not** the only store — sandbox remains the working roll for metadata + Field Book.
- Photos is the **durable / share surface**: album export + reject deletion + favorite mirror on keep.
- Still need `.readWrite` Photos auth (delete + album), not `.addOnly`.
- Still need `photosAssetLocalIdentifier` on each new shot so dual-delete works.

## Ship order (unchanged)

1 → 2 → 3 → dogfood a real shoot → 4 loupe/compare → 5 finish polish → 6 aesthetic polish.
