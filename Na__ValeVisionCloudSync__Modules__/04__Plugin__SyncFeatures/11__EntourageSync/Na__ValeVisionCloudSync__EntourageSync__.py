#!/usr/bin/env python3
"""
=============================================================================
 VALEDESIGNSUITE - VALEVISION CLOUD SYNC - ENTOURAGE SYNC
=============================================================================

FILE       : Na__ValeVisionCloudSync__EntourageSync__.py
AUTHOR     : Adam Noble - Noble Architecture
PURPOSE    : Keep one SketchUp model's entourage proxies and the figures placed in
             its project in ValeVision 3D in lockstep: people placed, moved, scaled,
             swapped or taken out in ValeVision come back as proxies, and proxies
             placed, moved, scaled, swapped or deleted in SketchUp go back.
CREATED    : 05-Nov-2026

DESCRIPTION:
- Adam, 05-Nov-2026, asked "Should placed people sync both ways with SketchUp, as plants do
  through Cloud Sync?": "Yes, both ways now". Sync Vegetation's shape, without what only a
  plant has: a path, a turn, a size of its own.
- WHAT IS READ AND WRITTEN: the project record's one key, Entourage__SceneData, through
  ValeVision 3D's API with the kept Vale sign-in (the Sync Aura tab's: one sign-in for every
  Vale app). PATCH merges that key under the server's lock, and only App Admins may. Only
  the object's Figures and Assets are ever changed here: line rules, tools and every other
  key are the app's alone.
- THE THREE-WAY MERGE, against what both sides held after the last sync (the base, kept in
  the SketchUp model). Changed on one side goes to the other. Changed on both, ValeVision
  wins and the report names it. Both making the same change is no clash at all.
- A FIGURE HAS NO TURN. It always faces the camera, so nothing about rotation is handed
  over, compared, saved or sent: a proxy keeps whatever turn SketchUp has given it.
- A FIGURE'S SCALE is what the proxy's blue axis says, against the height its definition was
  built at and the asset's own height. Stretched unevenly in SketchUp, the report says so
  and the height is what counts. A scale is saved to a thousandth, and exactly 1 is no key.
- AN UNDO IN SKETCHUP takes back the proxies and the base together, and not the record. So a
  new proxy standing exactly where a figure the base has never heard of stands, of the same
  asset, is that figure, with its stamp undone: it takes the Uid back rather than being
  drawn twice.
- SAFE WRITE: the record is read again just before the PATCH, and a change in between starts
  the merge again, once. It is a comparison and not an API guard, as Sync Vegetation's is, so
  a save landing in the moment between that read and the PATCH could still be overwritten;
  its revision is kept on the server. The app's Save makes the same comparison from its side.
- COORDINATES are all here, in one REGION. Ruby hands over and applies raw SketchUp poses:
  origin in inches, the lengths of the axes.
- ON UNLESS SWITCHED OFF (Adam, 05-Nov-2026): a project with no key counts as on, and only an
  explicit Enabled false is refused. A first sync that has something to write makes the key
  with Enabled true, its figures and the assets they need, and nothing more: the page lays
  every default over that when it reads it. Switching off is the app's, in Dev Tools.

USAGE:
  python Na__ValeVisionCloudSync__EntourageSync__.py --action sync
      --site https://app.valegardenhouses.com --session-file <json> --report-file <json>
      --library-id <id> --sync-map <...> --sketchup-file <json> [--project-root <...>]

-----------------------------------------------------------------------------

DEVELOPMENT LOG:
05-Nov-2026 - Version 1.0.0
- Initial build: frames, the three-way merge, a new proxy's asset pinned as the app pins
  it, an undone stamp taken back, the comparison before the write.

=============================================================================
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import os
import re
import secrets
import sys
from pathlib import Path

sys.dont_write_bytecode = True                                               # <-- Importing Sync Aura's file would leave a __pycache__ beside it, in the repo
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "08__LibraryPublisher"))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "09__AuraSync"))
import Na__ValeVisionCloudSync__LibraryPublisher__ as pub                    # noqa: E402  <-- The publisher's report, never copied
import Na__ValeVisionCloudSync__AuraSync__ as aura                           # noqa: E402  <-- The kept Vale sign-in and its API call, never copied


# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

NA__ENT__VERSION                = "1.0.0"
NA__ENT__ACTIONS                = ("sync",)
NA__ENT__API                    = "/valevision/api"
NA__ENT__ROOT_KEY               = "Entourage__SceneData"
NA__ENT__APP_DIR                = "Vale__ValeVision3D"
NA__ENT__LIBRARY_DIR            = "54__Entourage__AssetLibrary"
NA__ENT__LIBRARY_INDEX          = "EntourageLibrary__Index__.json"

NA__ENT__K_FIGURES              = "Entourage__SceneData__Figures"
NA__ENT__K_ASSETS               = "Entourage__SceneData__Assets"
NA__ENT__K_ENABLED              = "Entourage__SceneData__Enabled"
NA__ENT__F_UID                  = "Entourage__Figure__Uid"
NA__ENT__F_ASSET                = "Entourage__Figure__AssetId"
NA__ENT__F_SEED                 = "Entourage__Figure__Seed"
NA__ENT__F_POSITION             = "Entourage__Figure__PositionMm"
NA__ENT__F_SCALE                = "Entourage__Figure__Scale"

NA__ENT__MM_PER_INCH            = 25.4
NA__ENT__TOL_MM                 = 1                                         # <-- Saved in whole mm: a read back may round either way by one
NA__ENT__SCALE_STEPS            = 1000                                      # <-- A scale is saved to a thousandth
NA__ENT__TOL_SCALE              = 0.0006                                    # <-- Half of that step, and a little: a read back may round
NA__ENT__EVEN_SCALE_SHARE       = 0.005                                     # <-- Red and blue within this of each other are one even scale, as Sync Vegetation's
NA__ENT__SEED_LIMIT             = 1000000000                                # <-- As the app's Na__EntTool__SEED_RANGE

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Report (the publisher's, with this tool's own version)
# -----------------------------------------------------------------------------

class Na__EntReport(pub.Na__Report):
    """The publisher's step trail, so the dialog renders every tab the same way."""

    def __init__(self, args):
        super().__init__(args)
        self.extra.update(entourage_version=NA__ENT__VERSION)

    def finish(self, message: str = "") -> dict:
        out = super().finish(message)
        out["publisher_version"] = f"{pub.NA__PUB__VERSION} (entourage sync {NA__ENT__VERSION})"
        return out

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Coordinates (SketchUp <-> ValeVision's saved values)
# -----------------------------------------------------------------------------

# FUNCTION | A Number Rounded as JavaScript Rounds It
# ------------------------------------------------------------
# Python's round() goes to the even number at a half. Whole mm must match the app's.
def na_js_round(value: float) -> int:
    return int(math.floor(float(value) + 0.5))
# ---------------------------------------------------------------

# HELPER FUNCTION | A Scale as It Is Saved: to a Thousandth
# ------------------------------------------------------------
def na_neat_scale(value: float) -> float:
    return na_js_round(float(value) * NA__ENT__SCALE_STEPS) / NA__ENT__SCALE_STEPS
# ---------------------------------------------------------------

# FUNCTION | A SketchUp Origin as the App Saves It
# ------------------------------------------------------------
# SketchUp (x, y, z) inches, Z up -> three.js (x, z, -y) as whole mm. No offset, ever.
def na_origin_to_app(origin_in: list) -> list:
    x, y, z = [float(v) for v in origin_in]
    return [na_js_round(x * NA__ENT__MM_PER_INCH), na_js_round(z * NA__ENT__MM_PER_INCH), na_js_round(-y * NA__ENT__MM_PER_INCH)]
# ---------------------------------------------------------------

# FUNCTION | A Saved Position Back Into a SketchUp Origin (the exact inverse)
# ------------------------------------------------------------
def na_app_to_origin(position_mm: list) -> list:
    x, y, z = [float(v) for v in position_mm]
    return [x / NA__ENT__MM_PER_INCH, -z / NA__ENT__MM_PER_INCH, y / NA__ENT__MM_PER_INCH]
# ---------------------------------------------------------------

# FUNCTION | The Figure's Scale a Proxy's Blue Axis Means
# ------------------------------------------------------------
# axis_z: the length of the instance's z axis. built_mm: the height its definition was built
# at. own_mm: the asset's own height in the project's copy, which is what a scale is of.
def na_axis_to_scale(axis_z: float, built_mm: float | None, own_mm: float | None) -> float:
    return float(axis_z) * float(built_mm) / float(own_mm) if built_mm and own_mm else float(axis_z)
# ---------------------------------------------------------------

# FUNCTION | The Blue Axis a Figure's Scale Means (the exact inverse)
# ------------------------------------------------------------
def na_scale_to_axis(scale: float, built_mm: float | None, own_mm: float | None) -> float:
    return float(scale) * float(own_mm) / float(built_mm) if built_mm and own_mm else float(scale)
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Assets (the project's own copy first, then the library on this PC)
# -----------------------------------------------------------------------------

# FUNCTION | The Entourage Library on This PC, from the Server Manager's Sync Map
# ------------------------------------------------------------
def na_library_folder(sync_map: str) -> Path | None:
    try:
        cfg = json.loads(Path(sync_map).read_text(encoding="utf-8"))
        return Path(cfg["Local"]["MirrorRoot"]) / NA__ENT__APP_DIR / NA__ENT__LIBRARY_DIR
    except (OSError, ValueError, KeyError, TypeError):
        return None
# ---------------------------------------------------------------

# FUNCTION | A Reader of Assets, Reading Each File Once
# ------------------------------------------------------------
# Returns recipe_of(asset_id) -> the whole asset, or None. A project draws from its own copy
# (Na__EntLib__ResolveAsset), so that is what decides a figure's own size here too.
def na_recipe_reader(scene: dict, library: Path | None):
    pinned = scene.get(NA__ENT__K_ASSETS) or {}
    cache = {}

    def library_recipe(asset_id: str):
        if asset_id in cache:
            return cache[asset_id]
        cache[asset_id] = None
        if library is not None:
            try:
                index = json.loads((library / NA__ENT__LIBRARY_INDEX).read_text(encoding="utf-8"))
                row = next((r for r in index.get("EntourageLibrary__Index__Assets") or [] if r.get("Asset__Id") == asset_id), None)
                if row:
                    cache[asset_id] = json.loads((library / row["Asset__File"]).read_text(encoding="utf-8"))
            except (OSError, ValueError, KeyError, TypeError):
                pass
        return cache[asset_id]

    def recipe_of(asset_id: str):
        return pinned.get(asset_id) or library_recipe(asset_id)
    return recipe_of
# ---------------------------------------------------------------

# HELPER FUNCTION | An Asset's Own Size From Its Recipe, as [width, height], or None
# ------------------------------------------------------------
def na_recipe_size(recipe: dict | None) -> list | None:
    size = (recipe or {}).get("Asset__Size") or {}
    values = [size.get("Size__WidthMm"), size.get("Size__HeightMm")]
    return values if all(isinstance(v, (int, float)) and v > 0 for v in values) else None
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Three-Way Merge (base: what both sides held after the last sync)
# -----------------------------------------------------------------------------

# HELPER FUNCTION | A Scale If It Is One, Else 1 (Na__EntData__FigureToBuild)
# ------------------------------------------------------------
def na_scale_of(value) -> float:
    return value if isinstance(value, (int, float)) and value > 0 else 1
# ---------------------------------------------------------------

# HELPER FUNCTION | The Part of a Figure That Is Compared and Kept in the Base
# ------------------------------------------------------------
def na_view(figure: dict) -> dict:
    return {"Uid": figure.get(NA__ENT__F_UID), "AssetId": figure.get(NA__ENT__F_ASSET),
            "PositionMm": list(figure.get(NA__ENT__F_POSITION) or [0, 0, 0]), "Scale": na_scale_of(figure.get(NA__ENT__F_SCALE))}
# ---------------------------------------------------------------

# HELPER FUNCTION | A Proxy, as a Figure's View, From Its Raw Pose
# ------------------------------------------------------------
def na_proxy_view(proxy: dict, own_size: list | None) -> dict:
    axes = [float(v) for v in (proxy.get("ScaleXYZ") or [1.0, 1.0, 1.0])]
    built = proxy.get("NominalMm") or own_size
    scale = na_axis_to_scale(axes[2], built[1] if built else None, own_size[1] if own_size else None)
    stretched = abs(axes[0] - axes[2]) > axes[2] * NA__ENT__EVEN_SCALE_SHARE    # <-- Green is no part of it: a flat figure has no depth to stretch
    return dict(proxy, PositionMm=na_origin_to_app(proxy["OriginIn"]), Scale=na_neat_scale(scale), Stretched=stretched)
# ---------------------------------------------------------------

# HELPER FUNCTION | Write a Figure's Scale. Exactly 1 Is No Key (Na__EntTool__WriteScale)
# ------------------------------------------------------------
def na_write_scale(record: dict, scale: float) -> None:
    if scale == 1:
        record.pop(NA__ENT__F_SCALE, None)
    else:
        record[NA__ENT__F_SCALE] = scale
# ---------------------------------------------------------------

# HELPER FUNCTION | Do Two Figures Stand in Different Places?
# ------------------------------------------------------------
def na_position_differs(a: dict, b: dict) -> bool:
    return any(abs(float(x) - float(y)) > NA__ENT__TOL_MM for x, y in zip(a["PositionMm"], b["PositionMm"]))
# ---------------------------------------------------------------

# HELPER FUNCTION | Has a Figure Changed Against Another
# ------------------------------------------------------------
def na_differs(a: dict, b: dict) -> bool:
    if a.get("AssetId") != b.get("AssetId"):
        return True
    return na_position_differs(a, b) or abs(float(a.get("Scale") or 1) - float(b.get("Scale") or 1)) > NA__ENT__TOL_SCALE
# ---------------------------------------------------------------

# HELPER FUNCTION | The Next Free Figure Uid (Na__EntData__NextUid, over every Uid either side has used)
# ------------------------------------------------------------
# parseInt reads the leading digits of what follows the E, so this does too.
def na_next_uid(used: set) -> str:
    top = 0
    for uid in used:
        text = str(uid)
        if text.startswith("E"):
            digits = re.match(r"\d+", text[1:])
            if digits:
                top = max(top, int(digits.group(0)))
    return "E" + str(top + 1).zfill(4)
# ---------------------------------------------------------------

# FUNCTION | Merge SketchUp's Proxies and the Project's Figures
# ------------------------------------------------------------
def na_merge(base: list, scene: dict, proxies: list, model_nominals: dict, recipe_of) -> dict:
    """base: the figures both sides held after the last sync. scene: the Entourage__SceneData read just now. proxies:
    SketchUp's, each {Key, Uid ('' when new), AssetId, OriginIn, ScaleXYZ, NominalMm}. model_nominals: the [width, height]
    each of the model's proxy definitions was built at (a proxy's scale means nothing without it). recipe_of: na_recipe_reader's.
    Returns {Figures (the object's list after the merge), Pins (assets to copy into the object), Apply (SketchUp's ops),
    Base, Definitions, Clashes, Notes, Stretched, Counts, AppChanged}. ValeVision wins a clash."""
    def own_size(asset_id):
        return na_recipe_size(recipe_of(asset_id))

    def nominal_of(asset_id):
        return model_nominals.get(asset_id) or own_size(asset_id)

    def name_of(asset_id):
        recipe = recipe_of(asset_id) or {}
        return recipe.get("Asset__Name") or asset_id

    apply, clashes, notes, pins = [], [], [], {}
    definitions, skipped = {}, set()
    counts = {"new": 0, "moved": 0, "removed": 0}
    changed = False

    def need_definition(asset_id):                                           # <-- What Ruby needs to build the proxy, when the model has none yet
        if asset_id not in definitions and asset_id not in model_nominals:
            recipe = recipe_of(asset_id) or {}
            definitions[asset_id] = {"Name": name_of(asset_id), "NominalMm": nominal_of(asset_id), "Figure": recipe.get("Asset__Figure") or {}}

    def pose_op(op: str, view: dict, proxy: dict | None = None) -> bool:     # <-- proxy: the one being moved, whose own definition its scale is of
        built = (proxy or {}).get("NominalMm") or nominal_of(view["AssetId"])
        if not built:
            notes.append(f"{view['AssetId']} ({view['Uid']}): not in the project or the library on this PC; not brought into SketchUp")
            skipped.add(view["Uid"])
            return False
        if op == "create":
            need_definition(view["AssetId"])
        own = own_size(view["AssetId"])
        entry = dict(Op=op, Uid=view["Uid"], AssetId=view["AssetId"], Name=name_of(view["AssetId"]), OriginIn=na_app_to_origin(view["PositionMm"]),
                     ScaleEven=na_scale_to_axis(view["Scale"], built[1], own[1] if own else None))
        if proxy:
            entry["Key"] = proxy["Key"]
        apply.append(entry)
        return True

    # EVERY PROXY INTO ONE OF TWO LISTS | A copy brings its Uid with it: whichever still stands where the base has it keeps the name
    B = {e["Uid"]: e for e in base if isinstance(e, dict) and e.get("Uid")}
    free, fresh, views = {}, [], []
    for proxy in proxies:
        view = na_proxy_view(proxy, own_size(proxy.get("AssetId")))
        views.append(view)
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

    figures = [dict(f) for f in scene.get(NA__ENT__K_FIGURES) or [] if isinstance(f, dict)]
    used = {f.get(NA__ENT__F_UID) for f in figures} | set(B) | set(free)
    used.discard(None)
    seen = set()
    for figure in figures:                                                   # <-- A figure with no name, or another's, cannot be followed: it gets its own
        if not figure.get(NA__ENT__F_UID) or figure[NA__ENT__F_UID] in seen:
            figure[NA__ENT__F_UID] = na_next_uid(used)
            used.add(figure[NA__ENT__F_UID])
            changed = True
        seen.add(figure[NA__ENT__F_UID])

    records = {f[NA__ENT__F_UID]: f for f in figures}
    order = [f[NA__ENT__F_UID] for f in figures]
    A = {uid: na_view(f) for uid, f in records.items()}

    # A STAMP UNDONE | A new proxy where a figure the base does not know stands, of that asset, is that figure:
    # an Undo in SketchUp took its stamp back and not the record, or a sync was cut short before SketchUp. Not drawn twice.
    known = set(B) | set(free)
    for view in list(fresh):
        twin = next((uid for uid, a in A.items() if uid not in known and a["AssetId"] == view.get("AssetId") and not na_position_differs(a, view)), None)
        if twin:
            fresh.remove(view)
            known.add(twin)
            free[twin] = dict(view, Uid=twin)
            apply.append({"Op": "stamp", "Key": view["Key"], "Uid": twin, "AssetId": view.get("AssetId"), "Name": name_of(view.get("AssetId"))})

    def pull(uid, s=None):                                                   # <-- ValeVision's figure onto SketchUp
        if s is not None and s.get("AssetId") == A[uid]["AssetId"]:
            pose_op("update", A[uid], s)
        else:
            if s is not None:
                apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})  # <-- Swapped for another asset: a new proxy of the new asset
            pose_op("create", A[uid])

    def push(uid, s):                                                        # <-- SketchUp's change into the record: nothing that only rounds is written
        nonlocal changed
        rec, a = records[uid], A[uid]
        if s.get("AssetId") != a["AssetId"]:                                 # <-- Replaced in SketchUp: as the app's own swap, the spot, the Uid and the seed stay
            recipe = recipe_of(s.get("AssetId"))
            if not recipe:
                notes.append(f"{s.get('AssetId')} ({uid}): not in the project or the library on this PC; the figure is left as it was")
                return
            rec[NA__ENT__F_ASSET] = s["AssetId"]
            if s["AssetId"] not in (scene.get(NA__ENT__K_ASSETS) or {}):
                pins[s["AssetId"]] = copy.deepcopy(recipe)
        if na_position_differs(s, a):
            rec[NA__ENT__F_POSITION] = s["PositionMm"]
        if abs(float(s["Scale"]) - float(a["Scale"])) > NA__ENT__TOL_SCALE:
            na_write_scale(rec, s["Scale"])
        A[uid] = na_view(rec)
        counts["moved"] += 1
        changed = True

    for uid in sorted(set(B) | set(A) | set(free)):
        b, a, s = B.get(uid), A.get(uid), free.get(uid)
        if b and a and s:
            su, vv = na_differs(s, b), na_differs(a, b)
            if su and vv:
                if na_differs(s, a):                                         # <-- Both making the same change is no clash
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

    # NEW IN SKETCHUP | A figure of its own, with a seed of its own, and its asset copied in as the app copies it
    named = {}
    for proxy in fresh:
        asset_id = proxy.get("AssetId")
        recipe = recipe_of(asset_id)
        if not recipe:
            notes.append(f"{asset_id}: not in the project or the library on this PC; left in SketchUp only")
            continue
        uid = na_next_uid(used)
        used.add(uid)
        records[uid] = {NA__ENT__F_UID: uid, NA__ENT__F_ASSET: asset_id, NA__ENT__F_SEED: secrets.randbelow(NA__ENT__SEED_LIMIT),
                        NA__ENT__F_POSITION: proxy["PositionMm"]}
        na_write_scale(records[uid], proxy["Scale"])
        order.append(uid)
        A[uid] = na_view(records[uid])
        named[proxy["Key"]] = uid
        if asset_id not in (scene.get(NA__ENT__K_ASSETS) or {}):
            pins[asset_id] = copy.deepcopy(recipe)
        apply.append({"Op": "stamp", "Key": proxy["Key"], "Uid": uid, "AssetId": asset_id, "Name": name_of(asset_id)})
        counts["new"] += 1
        changed = True

    # STRETCHED | The height counts. Named by what the figure is called now
    stretched = [f"{name_of(v.get('AssetId'))} ({named.get(v['Key']) or v.get('Uid') or 'new'}), scale {v['Scale']:g}" for v in views if v["Stretched"]]

    return {"Figures": [records[uid] for uid in order if uid in records], "Pins": pins, "Apply": apply,
            "Base": [A[uid] for uid in order if uid in A and uid not in skipped], "Definitions": definitions,
            "Clashes": clashes, "Notes": notes, "Stretched": stretched, "Counts": counts, "AppChanged": changed}
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
        return f"ValeVision 3D refused this account: {error} (changing a project's entourage is for App Admins)."
    if error.status == 404:
        return f"The server has no project {library_id}: run Sync Project To ValeVision 3D once."
    return str(error)
# ---------------------------------------------------------------

# FUNCTION | The Project's Entourage Object as It Is on the Server, or None With a Step Saying Why
# ------------------------------------------------------------
def na_read_scene(args, session: dict, rep) -> dict | None:
    try:
        record = aura.na_api(args.site, "GET", f"projects/{args.library_id}", session, api=NA__ENT__API)
    except aura.Na__AuraApiError as e:
        rep.step("Read The Project", False, na_api_words(e, args.library_id))
        return None
    scene = record.get(NA__ENT__ROOT_KEY)
    if not isinstance(scene, dict):
        return {}                                                            # <-- No key counts as on: a first sync makes it
    if scene.get(NA__ENT__K_ENABLED) is False:
        rep.step("Read The Project", False, f"Entourage is switched off for {args.library_id} in ValeVision 3D's Dev Tools. "
                 "Its figures are kept; switch it on to sync. Nothing was changed.")
        return None
    return scene
# ---------------------------------------------------------------

# HELPER FUNCTION | An Object as One String, Whatever Order Its Keys Came In
# ------------------------------------------------------------
def na_canon(value) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)
# ---------------------------------------------------------------

# FUNCTION | Sync the People Both Ways
# ------------------------------------------------------------
def na_sync_people(args, session: dict, sketchup: dict, rep) -> dict | None:
    same_project = sketchup.get("BaseProjectId") in ("", None, args.library_id)
    base = (sketchup.get("Base") or []) if sketchup.get("BaseProjectId") == args.library_id else []
    proxies = [p for p in sketchup.get("Proxies") or [] if isinstance(p, dict) and p.get("Key")]
    if not same_project:
        proxies = [dict(p, Uid="") for p in proxies]                         # <-- Synced with another project: its Uids mean nothing here
    tilted = sum(1 for p in proxies if p.get("Tilted"))
    nested = int(sketchup.get("Nested") or 0)
    model_nominals = {k: v.get("NominalMm") for k, v in (sketchup.get("Definitions") or {}).items() if isinstance(v, dict) and v.get("NominalMm")}
    library = na_library_folder(args.sync_map)

    merged, scene = None, None
    for attempt in (1, 2):                                                   # <-- A change that landed mid-merge means merging again, once
        scene = na_read_scene(args, session, rep)
        if scene is None:
            return None
        merged = na_merge(base, scene, proxies, model_nominals, na_recipe_reader(scene, library))
        if not merged["AppChanged"]:
            break
        again = na_read_scene(args, session, rep)
        if again is None:
            return None
        if na_canon(again) != na_canon(scene):
            if attempt == 2:
                rep.step("Sync People", False, "The project's entourage keeps changing on the server (the app saving, or another "
                         "sync): nothing was sent, and SketchUp was not changed. Sync again in a moment.")
                return None
            continue
        out = dict(scene)
        out.setdefault(NA__ENT__K_ENABLED, True)                             # <-- What a first sync makes; the page lays every default over it
        out[NA__ENT__K_FIGURES] = merged["Figures"]
        if merged["Pins"]:
            out[NA__ENT__K_ASSETS] = {**(scene.get(NA__ENT__K_ASSETS) or {}), **merged["Pins"]}
        try:
            aura.na_api(args.site, "PATCH", f"projects/{args.library_id}", session, {NA__ENT__ROOT_KEY: out}, api=NA__ENT__API)
        except aura.Na__AuraApiError as e:
            rep.step("Sync People", False, na_api_words(e, args.library_id) + " Nothing was changed in SketchUp.")
            return None
        break

    ops, counts = merged["Apply"], merged["Counts"]
    count = lambda op: sum(1 for o in ops if o["Op"] == op)                  # noqa: E731
    parts = [f"{len(merged['Figures'])} figure(s) in ValeVision"]
    if merged["AppChanged"]:
        parts.append(f"ValeVision updated ({counts['new']} new from SketchUp, {counts['moved']} moved or scaled, {counts['removed']} taken out)")
    if count("create") or count("update") or count("delete"):
        parts.append(f"SketchUp: {count('create')} to place, {count('update')} to move, {count('delete')} to take out")
    if not merged["AppChanged"] and not (count("create") or count("update") or count("delete")):
        parts.append("both sides already match")
    rep.step("Sync People", True, "; ".join(parts) + ".")
    if merged["AppChanged"] and not scene:
        rep.step("First Sync Of This Project", True, f"{args.library_id} had no entourage yet, so this sync started it: switched on, with its figures "
                 "and the assets they need. ValeVision 3D lays every default over that when it reads it.")
    if merged["Clashes"]:
        rep.step("Clashes (ValeVision Kept)", True, "; ".join(merged["Clashes"]) + ".")
    if merged["Stretched"]:
        rep.step("Stretched Proxies", True, "Stretched unevenly in SketchUp, so the height is used: " + "; ".join(merged["Stretched"][:12])
                 + ". A figure scales evenly: scale it from a corner.", status="skip")
    told = list(merged["Notes"])
    if tilted:
        told.append(f"{tilted} tilted proxy(s): a figure always stands upright in ValeVision 3D, so only its foot and its height are used")
    if nested:
        told.append(f"{nested} proxy(s) inside a group or component are not seen: a proxy syncs only at the model root")
    if told:
        rep.step("People Notes", True, "; ".join(told) + ".", status="skip")
    return {"Apply": ops, "Definitions": merged["Definitions"], "Base": merged["Base"], "BaseProjectId": args.library_id}
# ---------------------------------------------------------------

# FUNCTION | One Sync
# ------------------------------------------------------------
def na_sync(args) -> dict:
    rep = Na__EntReport(args)
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

    result = na_sync_people(args, session, sketchup, rep)
    aura.na_write_session(Path(args.session_file), session)                  # <-- A renewed cookie is kept
    if result is None:
        return rep.finish()
    rep.extra["entourage"] = result
    return rep.finish(f"Synced the people of {args.library_id} with ValeVision 3D.")
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
    ap = argparse.ArgumentParser(description="ValeVision Cloud Sync: keep a SketchUp model's entourage proxies and its project's figures in lockstep")
    ap.add_argument("--action", choices=NA__ENT__ACTIONS, required=True)
    ap.add_argument("--site", default="https://app.valegardenhouses.com")
    ap.add_argument("--session-file", required=True, help="the plugin's local-only Vale session (91__UserConfig__LocalOnly)")
    ap.add_argument("--project-root", default="", help="the SketchUp project folder")
    ap.add_argument("--library-id", required=True, help="the library folder name, e.g. 63403__Thrower")
    ap.add_argument("--sync-map", default="", help="the Server Manager's VirtualServerManager__SyncMap__.json (finds the asset library)")
    ap.add_argument("--sketchup-file", default="", help="the plugin's hand-over: proxies, the definitions' sizes, the last synced base")
    ap.add_argument("--report-file", default="")
    ap.add_argument("--json", action="store_true", help="also print the report as the last stdout line")
    args = ap.parse_args()
    args.site = args.site.rstrip("/")
    args.dry_run = False                                                     # <-- The publisher's report reads it
    print(f"ValeVision Cloud Sync entourage sync {NA__ENT__VERSION}: {args.action} {args.library_id}", flush=True)
    try:
        report = na_sync(args)
    except Exception as e:                                                   # <-- Never leave the dialog without a report
        import traceback
        traceback.print_exc()
        report = {"success": False, "message": f"Entourage sync error: {type(e).__name__}: {e}", "steps": [
            {"label": "Entourage Sync", "success": False, "message": f"{type(e).__name__}: {e}"}]}
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
