#!/usr/bin/env python3
"""
=============================================================================
 VALEDESIGNSUITE - VALEVISION CLOUD SYNC - FURNISHINGS SYNC
=============================================================================

FILE       : Na__ValeVisionCloudSync__FurnishingsSync__.py
AUTHOR     : Adam Noble - Noble Architecture
PURPOSE    : Keep one SketchUp model's furnishings proxies and the pieces placed in its
             project in ValeVision 3D in lockstep: pieces placed, moved, turned, swapped or
             taken out in ValeVision come back as the real library components, and proxies
             placed, moved, turned, swapped or deleted in SketchUp go back.
CREATED    : 25-Nov-2026

DESCRIPTION:
- Adam's answer 9 (25-Nov-2026): SketchUp both ways now. Plan of record: the app's
  ValeVision__PLAN__FurnishingsSystem__.md, section 5.6. Sync Entourage's shape (its file
  11__EntourageSync), with a turn and without a scale or a seed.
- WHAT IS READ AND WRITTEN: the project's Furnishings__SceneData, through ValeVision 3D's placed-assets
  routes with the kept Vale sign-in (the Sync Aura tab's): GET scene-assets/working?system=Furnishings,
  then POST scene-assets/save with what was read as the base. The server finds this sync's changes
  item by item, so it records who placed what (Owners, Changes, Remove My Changes) and never
  overwrites a piece someone else changed meanwhile. Only the items and the pins they need are sent.
- THE THREE-WAY MERGE, against what both sides held after the last sync (the base, kept in the
  SketchUp model). Changed on one side goes to the other. Changed on both, ValeVision wins and the
  report names it. Both making the same change is no clash at all.
- A PIECE HAS ITS REAL SIZE. A proxy scaled or mirrored in SketchUp is refused: left where it is, out
  of ValeVision, and the report names it. A proxy tilted off the vertical keeps only its turn about Z.
- A PIN is the library's row for the asset's latest version (plan 5.2), as the app pins it. A project
  keeps drawing the version it pinned; the sync never moves a pin.
- COORDINATES are all here, in one REGION. Ruby hands over and applies raw SketchUp poses: the origin
  in inches and the turn of the red axis about Z in degrees.
- ON UNLESS SWITCHED OFF (Adam's answer 8): a project with no key counts as on, and only an explicit
  Enabled false is refused. The server seeds the key at the first save.

USAGE:
  python Na__ValeVisionCloudSync__FurnishingsSync__.py --action sync
      --site https://app.valegardenhouses.com --session-file <json> --report-file <json>
      --library-id <id> --sync-map <...> --sketchup-file <json> [--project-root <...>]

-----------------------------------------------------------------------------

DEVELOPMENT LOG:
25-Nov-2026 - Version 0.0.1 (Cloud Sync 0.7.2)
- Initial build: frames, the three-way merge with a turn, pins from the library on this PC,
  refusals for scaled and mirrored proxies, the save through the placed-assets routes.

=============================================================================
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True                                               # <-- Importing Sync Aura's file would leave a __pycache__ beside it, in the repo
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "08__LibraryPublisher"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "09__AuraSync"))
import Na__ValeVisionCloudSync__LibraryPublisher__ as pub                    # noqa: E402  <-- The publisher's report, never copied
import Na__ValeVisionCloudSync__AuraSync__ as aura                           # noqa: E402  <-- The kept Vale sign-in, its API call and its turns, never copied


# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

NA__FURN__VERSION               = "0.0.1"
NA__FURN__ACTIONS               = ("sync",)
NA__FURN__API                   = "/valevision/api"
NA__FURN__SYSTEM                = "Furnishings"
NA__FURN__ROOT_KEY              = "Furnishings__SceneData"
NA__FURN__APP_DIR               = "Vale__ValeVision3D"
NA__FURN__LIBRARY_DIR           = "55__Furnishings__AssetLibrary"
NA__FURN__LIBRARY_INDEX         = "FurnishingsLibrary__Index__.json"
NA__FURN__LIBRARY_REGISTER      = "FurnishingsLibrary__Register__.json"

NA__FURN__K_ITEMS               = "Furnishings__SceneData__Items"
NA__FURN__K_ASSETS              = "Furnishings__SceneData__Assets"
NA__FURN__K_ENABLED             = "Furnishings__SceneData__Enabled"
NA__FURN__I_UID                 = "Furnishings__Item__Uid"
NA__FURN__I_ASSET               = "Furnishings__Item__AssetId"
NA__FURN__I_POSITION            = "Furnishings__Item__PositionMm"
NA__FURN__I_ROTATION            = "Furnishings__Item__RotationDeg"

NA__FURN__MM_PER_INCH           = 25.4
NA__FURN__TOL_MM                = 1                                         # <-- Saved in whole mm: a read back may round either way by one
NA__FURN__TOL_DEG               = 0.05                                      # <-- Saved to a tenth of a degree
NA__FURN__TOL_SCALE             = 0.001                                     # <-- An axis this far from 1 is a scaled proxy
NA__FURN__UID                   = re.compile(r"^F\d{4,}$")

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Report (the publisher's, with this tool's own version)
# -----------------------------------------------------------------------------

class Na__FurnReport(pub.Na__Report):
    """The publisher's step trail, so the dialog renders every tab the same way."""

    def __init__(self, args):
        super().__init__(args)
        self.extra.update(furnishings_version=NA__FURN__VERSION)

    def finish(self, message: str = "") -> dict:
        out = super().finish(message)
        out["publisher_version"] = f"{pub.NA__PUB__VERSION} (furnishings sync {NA__FURN__VERSION})"
        return out

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Coordinates (SketchUp <-> ValeVision's saved values)
# -----------------------------------------------------------------------------

# FUNCTION | A Number Rounded as JavaScript Rounds It
# ------------------------------------------------------------
def na_js_round(value: float) -> int:
    return int(math.floor(float(value) + 0.5))
# ---------------------------------------------------------------

# FUNCTION | A SketchUp Origin as the App Saves It
# ------------------------------------------------------------
# SketchUp (x, y, z) inches, Z up -> three.js (x, z, -y) as whole mm. No offset, ever.
def na_origin_to_app(origin_in: list) -> list:
    x, y, z = [float(v) for v in origin_in]
    return [na_js_round(x * NA__FURN__MM_PER_INCH), na_js_round(z * NA__FURN__MM_PER_INCH), na_js_round(-y * NA__FURN__MM_PER_INCH)]
# ---------------------------------------------------------------

# FUNCTION | A Saved Position Back Into a SketchUp Origin (the exact inverse)
# ------------------------------------------------------------
def na_app_to_origin(position_mm: list) -> list:
    x, y, z = [float(v) for v in position_mm]
    return [x / NA__FURN__MM_PER_INCH, -z / NA__FURN__MM_PER_INCH, y / NA__FURN__MM_PER_INCH]
# ---------------------------------------------------------------

# FUNCTION | A Turn as It Is Saved
# ------------------------------------------------------------
# A turn about SketchUp +Z is the same turn about three +Y: counter-clockwise seen from above,
# so the number needs no change, only its form: 0 to 360, a tenth of a degree (Sync Aura's).
def na_neat_turn(deg) -> float:
    return aura.na_norm_deg(float(deg or 0), 1)
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Library on This PC
# -----------------------------------------------------------------------------

# FUNCTION | The Furnishings Library on This PC, From the Server Manager's Sync Map
# ------------------------------------------------------------
def na_library_folder(sync_map: str) -> Path | None:
    try:
        cfg = json.loads(Path(sync_map).read_text(encoding="utf-8"))
        return Path(cfg["Local"]["MirrorRoot"]) / NA__FURN__APP_DIR / NA__FURN__LIBRARY_DIR
    except (OSError, ValueError, KeyError, TypeError):
        return None
# ---------------------------------------------------------------

# FUNCTION | A Reader of the Library: Each Asset's Index Row, Its Pin and Its Source .skp
# ------------------------------------------------------------
def na_library_reader(library: Path | None):
    rows, source_root = {}, ""
    if library is not None:
        try:
            index = json.loads((library / NA__FURN__LIBRARY_INDEX).read_text(encoding="utf-8"))
            rows = {r["Asset__Id"]: r for r in index.get("FurnishingsLibrary__Index__Assets") or [] if r.get("Asset__Id")}
            register = json.loads((library / NA__FURN__LIBRARY_REGISTER).read_text(encoding="utf-8"))
            source_root = register["FurnishingsLibrary__Register__Source"]["Source__Root"]
        except (OSError, ValueError, KeyError, TypeError):
            rows = {}

    def row_of(asset_id: str) -> dict | None:
        return rows.get(asset_id)

    def pin_of(asset_id: str) -> dict | None:                                # <-- Plan 5.2: the latest version's row, as the app pins it
        row = rows.get(asset_id)
        if not row:
            return None
        version = row["Asset__LatestVersion"]
        files = row["Asset__Versions"][version]
        return {"Furnishings__Pin__Version": version, "Furnishings__Pin__Name": row["Asset__Name"],
                "Furnishings__Pin__MeshFile": files["Version__MeshFile"], "Furnishings__Pin__LineworkFile": files["Version__LineworkFile"],
                "Furnishings__Pin__ThumbnailFile": files["Version__ThumbnailFile"],
                "Furnishings__Pin__SizeMm": [row["Asset__WidthMm"], row["Asset__DepthMm"], row["Asset__HeightMm"]],
                "Furnishings__Pin__FootprintCentreMm": list(row["Asset__FootprintCentreMm"])}

    def skp_of(asset_id: str) -> str:                                        # <-- The core library component Ruby loads for a new proxy
        row = rows.get(asset_id)
        if not row or not source_root or library is None:
            return ""
        try:
            data = json.loads((library / row["Asset__DataFile"]).read_text(encoding="utf-8"))
            return str(Path(source_root) / data["Asset__Source"]["Source__SketchUpFile"]).replace("\\", "/")
        except (OSError, ValueError, KeyError, TypeError):
            return ""

    return row_of, pin_of, skp_of
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Three-Way Merge (base: what both sides held after the last sync)
# -----------------------------------------------------------------------------

# HELPER FUNCTION | The Part of a Piece That Is Compared and Kept in the Base
# ------------------------------------------------------------
def na_view(item: dict) -> dict:
    return {"Uid": item.get(NA__FURN__I_UID), "AssetId": item.get(NA__FURN__I_ASSET),
            "PositionMm": list(item.get(NA__FURN__I_POSITION) or [0, 0, 0]), "RotationDeg": na_neat_turn(item.get(NA__FURN__I_ROTATION))}
# ---------------------------------------------------------------

# HELPER FUNCTION | A Proxy, as a Piece's View, From Its Raw Pose
# ------------------------------------------------------------
def na_proxy_view(proxy: dict) -> dict:
    return dict(proxy, PositionMm=na_origin_to_app(proxy["OriginIn"]), RotationDeg=na_neat_turn(proxy.get("RotZDeg")))
# ---------------------------------------------------------------

# HELPER FUNCTION | Write a Piece's Turn. 0 Is No Key
# ------------------------------------------------------------
def na_write_turn(record: dict, deg: float) -> None:
    if abs(deg) < 1e-9:
        record.pop(NA__FURN__I_ROTATION, None)
    else:
        record[NA__FURN__I_ROTATION] = deg
# ---------------------------------------------------------------

# HELPER FUNCTION | Do Two Pieces Stand in Different Places?
# ------------------------------------------------------------
def na_position_differs(a: dict, b: dict) -> bool:
    return any(abs(float(x) - float(y)) > NA__FURN__TOL_MM for x, y in zip(a["PositionMm"], b["PositionMm"]))
# ---------------------------------------------------------------

# HELPER FUNCTION | Has a Piece Changed Against Another: Its Asset, Spot or Turn
# ------------------------------------------------------------
def na_differs(a: dict, b: dict) -> bool:
    if a.get("AssetId") != b.get("AssetId"):
        return True
    return na_position_differs(a, b) or aura.na_turned(a, b)
# ---------------------------------------------------------------

# HELPER FUNCTION | The Next Free Piece Uid, Over Every Uid Either Side Has Used
# ------------------------------------------------------------
def na_next_uid(used: set) -> str:
    top = 0
    for uid in used:
        text = str(uid)
        if text.startswith("F"):
            digits = re.match(r"\d+", text[1:])
            if digits:
                top = max(top, int(digits.group(0)))
    return "F" + str(top + 1).zfill(4)
# ---------------------------------------------------------------

# FUNCTION | Merge SketchUp's Proxies and the Project's Pieces
# ------------------------------------------------------------
def na_merge(base: list, scene: dict, proxies: list, row_of, pin_of, skp_of) -> dict:
    """base: the pieces both sides held after the last sync. scene: Furnishings__SceneData as read just now (staff's
    working object). proxies: SketchUp's, each {Key, Uid ('' when new), AssetId, OriginIn, RotZDeg, Scaled, Mirrored,
    Tilted}. Returns {Items, Pins, Apply (SketchUp's ops), Base, Definitions, Clashes, Notes, Refused, Counts, AppChanged}.
    ValeVision wins a clash."""
    def name_of(asset_id):
        pin = (scene.get(NA__FURN__K_ASSETS) or {}).get(asset_id) or pin_of(asset_id) or {}
        return pin.get("Furnishings__Pin__Name") or asset_id

    apply, clashes, notes, refused, pins = [], [], [], [], {}
    definitions, skipped = {}, set()
    counts = {"new": 0, "moved": 0, "removed": 0}
    changed = False

    def need_definition(asset_id) -> bool:                                   # <-- Where Ruby finds the real component for a new proxy
        if asset_id in definitions:
            return True
        skp = skp_of(asset_id)
        if not skp:
            return False
        definitions[asset_id] = {"Name": name_of(asset_id), "SkpPath": skp}
        return True

    def pose_op(op: str, view: dict, proxy: dict | None = None) -> bool:
        if op == "create" and not need_definition(view["AssetId"]):
            notes.append(f"{view['AssetId']} ({view['Uid']}): not in the furnishings library on this PC; not brought into SketchUp")
            skipped.add(view["Uid"])
            return False
        entry = dict(Op=op, Uid=view["Uid"], AssetId=view["AssetId"], Name=name_of(view["AssetId"]),
                     OriginIn=na_app_to_origin(view["PositionMm"]), RotZDeg=view["RotationDeg"])
        if proxy:
            entry["Key"] = proxy["Key"]
        apply.append(entry)
        return True

    # REFUSED | A scaled or mirrored proxy is not a piece of real size: it stays as it is, out of ValeVision
    usable = []
    for proxy in proxies:
        if proxy.get("Scaled") or proxy.get("Mirrored"):
            why = "mirrored" if proxy.get("Mirrored") else "scaled"
            refused.append(f"{name_of(proxy.get('AssetId'))} ({proxy.get('Uid') or 'new'}), {why}: a piece keeps its real size")
            if proxy.get("Uid"):
                skipped.add(proxy["Uid"])
            continue
        usable.append(proxy)

    # EVERY PROXY INTO ONE OF TWO LISTS | A copy brings its Uid with it: whichever still stands where the base has it keeps the name
    B = {e["Uid"]: e for e in base if isinstance(e, dict) and e.get("Uid")}
    free, fresh = {}, []
    for proxy in usable:
        view = na_proxy_view(proxy)
        uid = proxy.get("Uid") or ""
        if not uid:
            fresh.append(view)
            continue
        held = free.get(uid)
        if held is None:
            free[uid] = view
            continue
        keep, extra = (view, held) if (uid in B and na_differs(held, B[uid]) and not na_differs(view, B[uid])) else (held, view)
        free[uid] = keep
        apply.append({"Op": "unstamp", "Key": extra["Key"], "Uid": uid})
        fresh.append(dict(extra, Uid=""))

    items = [dict(i) for i in scene.get(NA__FURN__K_ITEMS) or [] if isinstance(i, dict) and i.get(NA__FURN__I_UID)]
    records = {i[NA__FURN__I_UID]: i for i in items}
    order = [i[NA__FURN__I_UID] for i in items]
    A = {uid: na_view(i) for uid, i in records.items()}
    used = set(records) | set(B) | set(free) | skipped

    # A STAMP UNDONE | A new proxy where a piece the base does not know stands, of that asset and turn, is that piece
    known = set(B) | set(free)
    for view in list(fresh):
        twin = next((uid for uid, a in A.items() if uid not in known and a["AssetId"] == view.get("AssetId")
                     and not na_position_differs(a, view) and not aura.na_turned(a, view)), None)
        if twin:
            fresh.remove(view)
            known.add(twin)
            free[twin] = dict(view, Uid=twin)
            apply.append({"Op": "stamp", "Key": view["Key"], "Uid": twin, "AssetId": view.get("AssetId"), "Name": name_of(view.get("AssetId"))})

    def pull(uid, s=None):                                                   # <-- ValeVision's piece onto SketchUp
        if s is not None and s.get("AssetId") == A[uid]["AssetId"]:
            pose_op("update", A[uid], s)
        else:
            if s is not None:
                apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})  # <-- Swapped for another asset: a new proxy of the new asset
            pose_op("create", A[uid])

    def push(uid, s):                                                        # <-- SketchUp's change into the record: nothing that only rounds is written
        nonlocal changed
        rec, a = records[uid], A[uid]
        if s.get("AssetId") != a["AssetId"]:                                 # <-- Replaced in SketchUp: the spot and the Uid stay, as the app's own swap
            pin = pin_of(s.get("AssetId"))
            if not pin:
                notes.append(f"{s.get('AssetId')} ({uid}): not in the furnishings library on this PC; the piece is left as it was")
                return
            rec[NA__FURN__I_ASSET] = s["AssetId"]
            if s["AssetId"] not in (scene.get(NA__FURN__K_ASSETS) or {}):
                pins[s["AssetId"]] = pin
        if na_position_differs(s, a):
            rec[NA__FURN__I_POSITION] = s["PositionMm"]
        if aura.na_turned(s, a):
            na_write_turn(rec, s["RotationDeg"])
        A[uid] = na_view(rec)
        counts["moved"] += 1
        changed = True

    for uid in sorted(set(B) | set(A) | set(free)):
        if uid in skipped:
            continue                                                         # <-- A refused proxy's piece is left alone on both sides
        b, a, s = B.get(uid), A.get(uid), free.get(uid)
        if b and a and s:
            su, vv = na_differs(s, b), na_differs(a, b)
            if su and vv:
                if na_differs(s, a):
                    clashes.append(f"{name_of(a['AssetId'])} ({uid}) changed on both sides: ValeVision's kept")
                    pull(uid, s)
            elif vv:
                pull(uid, s)
            elif su:
                push(uid, s)
        elif b and a and not s:
            if na_differs(a, b):
                clashes.append(f"{name_of(a['AssetId'])} ({uid}) deleted in SketchUp but changed in ValeVision: put back")
                pull(uid)
            else:
                del records[uid]
                del A[uid]
                counts["removed"] += 1
                changed = True
        elif b and s and not a:
            if na_differs(s, b):
                clashes.append(f"{name_of(s['AssetId'])} ({uid}) deleted in ValeVision but changed in SketchUp: taken out")
            apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})
        elif a and s and not b:
            if na_differs(s, a):
                pull(uid, s)                                                 # <-- No common past: ValeVision's is the record
        elif a and not b and not s:
            pull(uid)
        elif s and not a and not b:
            fresh.append(dict(s, Uid=""))                                    # <-- A Uid neither side knows: placed afresh
            apply.append({"Op": "unstamp", "Key": s["Key"], "Uid": uid})

    # NEW IN SKETCHUP | A piece of its own, its asset pinned as the app pins it
    named = {}
    for proxy in fresh:
        asset_id = proxy.get("AssetId")
        pin = (scene.get(NA__FURN__K_ASSETS) or {}).get(asset_id) or pin_of(asset_id)
        if not pin:
            notes.append(f"{asset_id}: not in the furnishings library on this PC; left in SketchUp only (port it with vv3d_furnishings_import_skp)")
            continue
        uid = na_next_uid(used)
        used.add(uid)
        records[uid] = {NA__FURN__I_UID: uid, NA__FURN__I_ASSET: asset_id, NA__FURN__I_POSITION: proxy["PositionMm"]}
        na_write_turn(records[uid], proxy["RotationDeg"])
        order.append(uid)
        A[uid] = na_view(records[uid])
        named[proxy["Key"]] = uid
        if asset_id not in (scene.get(NA__FURN__K_ASSETS) or {}):
            pins[asset_id] = pin
        apply.append({"Op": "stamp", "Key": proxy["Key"], "Uid": uid, "AssetId": asset_id, "Name": name_of(asset_id), "StampDefinition": True})
        counts["new"] += 1
        changed = True

    return {"Items": [records[uid] for uid in order if uid in records], "Pins": pins, "Apply": apply,
            "Base": [A[uid] for uid in order if uid in A and uid not in skipped], "Definitions": definitions,
            "Clashes": clashes, "Notes": notes, "Refused": refused, "Counts": counts, "AppChanged": changed}
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | ValeVision 3D's API
# -----------------------------------------------------------------------------

# HELPER FUNCTION | A Refusal in Words the Dialog Can Act On
# ------------------------------------------------------------
def na_api_words(error: aura.Na__AuraApiError, library_id: str) -> str:
    if error.status == 401:
        return "Your Vale sign-in has ended (signed out, or the password changed): sign in again in the Sync Aura tab."
    if error.status == 403:
        return f"ValeVision 3D refused this account: {error} (placing furnishings is for Employees and up)."
    if error.status == 404:
        return f"The server has no project {library_id}, or no furnishings routes yet: run Sync Project To ValeVision 3D once."
    return str(error)
# ---------------------------------------------------------------

# FUNCTION | The Project's Furnishings as Staff Work on Them, or None With a Step Saying Why
# ------------------------------------------------------------
def na_read_scene(args, session: dict, rep) -> dict | None:
    try:
        answer = aura.na_api(args.site, "GET", f"projects/{args.library_id}/scene-assets/working?system={NA__FURN__SYSTEM}", session, api=NA__FURN__API)
    except aura.Na__AuraApiError as e:
        rep.step("Read The Project", False, na_api_words(e, args.library_id))
        return None
    scene = answer.get("object")
    if not isinstance(scene, dict):
        return {}                                                            # <-- No key counts as on: the first save makes it
    if scene.get(NA__FURN__K_ENABLED) is False:
        rep.step("Read The Project", False, f"Furnishings are switched off for {args.library_id} in ValeVision 3D's Dev Tools. "
                 "Its pieces are kept; switch it on to sync. Nothing was changed.")
        return None
    return scene
# ---------------------------------------------------------------

# FUNCTION | Sync the Furnishings Both Ways
# ------------------------------------------------------------
def na_sync_furnishings(args, session: dict, sketchup: dict, rep) -> dict | None:
    same_project = sketchup.get("BaseProjectId") in ("", None, args.library_id)
    base = (sketchup.get("Base") or []) if sketchup.get("BaseProjectId") == args.library_id else []
    proxies = [p for p in sketchup.get("Proxies") or [] if isinstance(p, dict) and p.get("Key")]
    if not same_project:
        proxies = [dict(p, Uid="") for p in proxies]                         # <-- Synced with another project: its Uids mean nothing here
    tilted = sum(1 for p in proxies if p.get("Tilted"))
    nested = int(sketchup.get("Nested") or 0)
    row_of, pin_of, skp_of = na_library_reader(na_library_folder(args.sync_map))

    scene = na_read_scene(args, session, rep)
    if scene is None:
        return None
    merged = na_merge(base, scene, proxies, row_of, pin_of, skp_of)
    renamed = {}
    if merged["AppChanged"]:
        out = dict(scene)
        out[NA__FURN__K_ITEMS] = merged["Items"]
        if merged["Pins"]:
            out[NA__FURN__K_ASSETS] = {**(scene.get(NA__FURN__K_ASSETS) or {}), **merged["Pins"]}
        try:
            answer = aura.na_api(args.site, "POST", f"projects/{args.library_id}/scene-assets/save", session,
                                 {"system": NA__FURN__SYSTEM, "base": scene, "object": out}, api=NA__FURN__API)
        except aura.Na__AuraApiError as e:
            rep.step("Sync Furnishings", False, na_api_words(e, args.library_id) + " Nothing was changed in SketchUp.")
            return None
        renamed = answer.get("renamed") or {}

    # A UID SOMEBODY ELSE TOOK MEANWHILE | The server moved ours up: the stamps and the base follow
    if renamed:
        for op in merged["Apply"]:
            if op.get("Uid") in renamed:
                op["Uid"] = renamed[op["Uid"]]
        for entry in merged["Base"]:
            if entry.get("Uid") in renamed:
                entry["Uid"] = renamed[entry["Uid"]]

    ops, counts = merged["Apply"], merged["Counts"]
    count = lambda op: sum(1 for o in ops if o["Op"] == op)                  # noqa: E731
    parts = [f"{len(merged['Items'])} piece(s) in ValeVision"]
    if merged["AppChanged"]:
        parts.append(f"ValeVision updated ({counts['new']} new from SketchUp, {counts['moved']} moved or turned, {counts['removed']} taken out)")
    if count("create") or count("update") or count("delete"):
        parts.append(f"SketchUp: {count('create')} to place, {count('update')} to move, {count('delete')} to take out")
    if not merged["AppChanged"] and not (count("create") or count("update") or count("delete")):
        parts.append("both sides already match")
    rep.step("Sync Furnishings", True, "; ".join(parts) + ".")
    if merged["Clashes"]:
        rep.step("Clashes (ValeVision Kept)", True, "; ".join(merged["Clashes"]) + ".")
    if merged["Refused"]:
        rep.step("Refused Proxies", True, "Left in SketchUp only: " + "; ".join(merged["Refused"][:12]) + ". Set its scale back to 1 to sync it.", status="skip")
    told = list(merged["Notes"])
    if renamed:
        told.append(f"{len(renamed)} new piece(s) renumbered, as another save took the number first")
    if tilted:
        told.append(f"{tilted} tilted proxy(s): a piece always stands upright in ValeVision 3D, so only its turn about the vertical is used")
    if nested:
        told.append(f"{nested} proxy(s) inside a group or component are not seen: a proxy syncs only at the model root")
    if told:
        rep.step("Furnishings Notes", True, "; ".join(told) + ".", status="skip")
    return {"Apply": ops, "Definitions": merged["Definitions"], "Base": merged["Base"], "BaseProjectId": args.library_id}
# ---------------------------------------------------------------

# FUNCTION | One Sync
# ------------------------------------------------------------
def na_sync(args) -> dict:
    rep = Na__FurnReport(args)
    try:
        sketchup = json.loads(Path(args.sketchup_file).read_text(encoding="utf-8")) if args.sketchup_file else {}
    except (OSError, ValueError) as e:
        rep.step("Read SketchUp Proxies", False, f"The plugin's hand-over file could not be read: {e}")
        return rep.finish()
    session = aura.na_read_session(Path(args.session_file))
    if not session:
        rep.step("Vale Sign-In", False, "Not signed in on this PC: sign in at the top of the Sync Aura tab.")
        return rep.finish()
    who = (session.get("User") or {}).get("name") or session.get("Email") or "?"
    rep.step("Vale Sign-In", True, f"Signed in as {who}.")

    result = na_sync_furnishings(args, session, sketchup, rep)
    aura.na_write_session(Path(args.session_file), session)                  # <-- A renewed cookie is kept
    if result is None:
        return rep.finish()
    rep.extra["furnishings"] = result
    return rep.finish(f"Synced the furnishings of {args.library_id} with ValeVision 3D.")
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Entry Point
# -----------------------------------------------------------------------------

def na_main() -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except AttributeError:
            pass
    ap = argparse.ArgumentParser(description="ValeVision Cloud Sync: keep a SketchUp model's furnishings proxies and its project's pieces in lockstep")
    ap.add_argument("--action", choices=NA__FURN__ACTIONS, required=True)
    ap.add_argument("--site", default="https://app.valegardenhouses.com")
    ap.add_argument("--session-file", required=True, help="the plugin's local-only Vale session (91__UserConfig__LocalOnly)")
    ap.add_argument("--project-root", default="", help="the SketchUp project folder")
    ap.add_argument("--library-id", required=True, help="the library folder name, e.g. 63403__Thrower")
    ap.add_argument("--sync-map", default="", help="the Server Manager's VirtualServerManager__SyncMap__.json (finds the furnishings library)")
    ap.add_argument("--sketchup-file", default="", help="the plugin's hand-over: proxies and the last synced base")
    ap.add_argument("--report-file", default="")
    ap.add_argument("--json", action="store_true", help="also print the report as the last stdout line")
    args = ap.parse_args()
    args.site = args.site.rstrip("/")
    args.dry_run = False                                                     # <-- The publisher's report reads it
    print(f"ValeVision Cloud Sync furnishings sync {NA__FURN__VERSION}: {args.action} {args.library_id}", flush=True)
    try:
        report = na_sync(args)
    except Exception as e:                                                   # <-- Never leave the dialog without a report
        import traceback
        traceback.print_exc()
        report = {"success": False, "message": f"Furnishings sync error: {type(e).__name__}: {e}", "steps": [
            {"label": "Furnishings Sync", "success": False, "message": f"{type(e).__name__}: {e}"}]}
    if args.report_file:
        target = Path(args.report_file)
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".tmp")
        tmp.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, target)
    if args.json:
        print(json.dumps(report, ensure_ascii=False))
    return 0 if report.get("success") else 1


if __name__ == "__main__":
    sys.exit(na_main())

# endregion -------------------------------------------------------------------
