#!/usr/bin/env python3
"""
=============================================================================
 VALEDESIGNSUITE - VALEVISION CLOUD SYNC - VEGETATION SYNC
=============================================================================

FILE       : Na__ValeVisionCloudSync__VegetationSync__.py
AUTHOR     : Adam Noble - Noble Architecture
PURPOSE    : Keep one SketchUp model's vegetation proxies and its project's
             planting in ValeVision 3D in lockstep: plants placed, moved or taken
             out in ValeVision come back as proxies, and proxies placed, moved,
             resized or deleted in SketchUp go back to ValeVision.
CREATED    : 04-Nov-2026

DESCRIPTION:
- Adam's answer, 04-Nov-2026, to whether the plants reach SketchUp: "Both ways,
  like Sync Aura". The plan is ValeVision__PLAN__VegetationSystem__.md, section 5.
- WHAT IS READ AND WRITTEN: the project record's one key, Vegetation__SceneData,
  through ValeVision 3D's API with the kept Vale sign-in (the Sync Aura tab's: one
  sign-in for every Vale app). PATCH merges that key under the server's lock, and
  only App Admins may. Only the object's Plops and Assets are ever changed here:
  line rules, palettes, paths and tool settings are the app's alone.
- THE THREE-WAY MERGE, against what both sides held after the last sync (the base,
  kept in the SketchUp model). Changed on one side goes to the other. Changed on
  both, ValeVision wins and the report names it, as in Sync Aura.
- A PATH'S PLANTS ARE READ-ONLY PROXIES. A path saves rules and a seed, never its
  plants, so they are worked out here with a port of the app's sums (the REGION
  below). A proxy of one that has been moved goes back where its path says, and the
  report names it: to change a path, edit it in the app or bake it first. A copy of
  one is a plant of its own.
- SAFE WRITE: the record is read again just before the PATCH, and a change in between
  starts the merge again, once. It is a comparison and not the API guard the plan
  asked for (the API file holds other sessions' open work), so a save landing in the
  moment between that read and the PATCH could still be overwritten; its revision is
  kept on the server. The app's Save makes the same comparison from its side.
- COORDINATES are all here. Ruby hands over and applies raw SketchUp poses: origin in
  inches, the turn about +Z, a scale per axis. See the REGION below.
- A PLANT'S SCALE (app v2.86.0) is the whole plant, on top of its saved size, so a proxy
  shows and is compared at what the plant really measures. Scaled evenly in SketchUp, a
  plant's scale changes, the same bush smaller. Scaled on one axis only, its saved size
  changes: fitted to a space, its clumps keeping their size, as a stretched run's do.
- NOTHING IS MADE HERE WITHOUT THE APP: a project that has not been switched on is
  refused. Switching on and off is the app's, in Dev Tools.

USAGE:
  python Na__ValeVisionCloudSync__VegetationSync__.py --action sync
      --site https://app.valegardenhouses.com --session-file <json> --report-file <json>
      --library-id <id> --sync-map <...> --sketchup-file <json> [--project-root <...>]

-----------------------------------------------------------------------------

DEVELOPMENT LOG:
04-Nov-2026 - Version 1.1.0
- A plant's scale through the merge. The path sums follow the app's v2.86.0: Plant Scale, each
  palette item's scale, Height, clipped plants and the corners of their runs.

04-Nov-2026 - Version 1.0.0
- Initial build: frames, the three-way merge, path plants as read-only proxies, pins
  for assets placed in SketchUp, the comparison before the write.

=============================================================================
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import os
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

NA__VEG__VERSION                = "1.1.0"
NA__VEG__ACTIONS                = ("sync",)
NA__VEG__API                    = "/valevision/api"
NA__VEG__ROOT_KEY               = "Vegetation__SceneData"
NA__VEG__APP_DIR                = "Vale__ValeVision3D"
NA__VEG__LIBRARY_DIR            = "53__Vegetation__AssetLibrary"
NA__VEG__LIBRARY_INDEX          = "VegetationLibrary__Index__.json"

NA__VEG__K_PLOPS                = "Vegetation__SceneData__Plops"
NA__VEG__K_PATHS                = "Vegetation__SceneData__Paths"
NA__VEG__K_PALETTES             = "Vegetation__SceneData__Palettes"
NA__VEG__K_ASSETS               = "Vegetation__SceneData__Assets"
NA__VEG__K_ENABLED              = "Vegetation__SceneData__Enabled"
NA__VEG__P_UID                  = "Vegetation__Plop__Uid"
NA__VEG__P_ASSET                = "Vegetation__Plop__AssetId"
NA__VEG__P_SEED                 = "Vegetation__Plop__Seed"
NA__VEG__P_POSITION             = "Vegetation__Plop__PositionMm"
NA__VEG__P_YAW                  = "Vegetation__Plop__YawDeg"
NA__VEG__P_SIZE                 = "Vegetation__Plop__SizeMm"
NA__VEG__P_SCALE                = "Vegetation__Plop__Scale"

NA__VEG__MM_PER_INCH            = 25.4
NA__VEG__TOL_MM                 = 1                                         # <-- Saved in whole mm: a read back may round either way by one
NA__VEG__TOL_DEG                = 0.06                                      # <-- Yaw is saved to a tenth of a degree
NA__VEG__EVEN_SCALE_SHARE       = 0.005                                     # <-- Axes within this of each other are one even scale: a read back may round
NA__VEG__SEED_LIMIT             = 1000000000                                # <-- As the app's plops

NA__VEG__CURVE_STEP_MM          = 120                                       # <-- The path model's numbers: never changed on one side alone
NA__VEG__CURVE_MAX_STEPS        = 64
NA__VEG__MIN_SPACING_MM         = 200
NA__VEG__MAX_PLANTS             = 1500
NA__VEG__RUN_MIN_CELLS          = 2
NA__VEG__RUN_MAX_CELLS          = 3
NA__VEG__RUN_FILL_SHARE         = 0.94
NA__VEG__RUN_MIN_WIDTH          = 0.6
NA__VEG__END_SLACK              = 0.000001
NA__VEG__CORNER_TURN_RAD        = 0.26
NA__VEG__CORNER_SLACK_MM        = 1
NA__VEG__CORNER_MAX_TAN         = 2
NA__VEG__CLIPPED_SLIVER         = 0.5
NA__VEG__CLIPPED_MAX_MM         = 4000
NA__VEG__U32                    = 0xFFFFFFFF

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Report (the publisher's, with this tool's own version)
# -----------------------------------------------------------------------------

class Na__VegReport(pub.Na__Report):
    """The publisher's step trail, so the dialog renders every tab the same way."""

    def __init__(self, args):
        super().__init__(args)
        self.extra.update(vegetation_version=NA__VEG__VERSION)

    def finish(self, message: str = "") -> dict:
        out = super().finish(message)
        out["publisher_version"] = f"{pub.NA__PUB__VERSION} (vegetation sync {NA__VEG__VERSION})"
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

# HELPER FUNCTION | A Turn in the Range -180 to 180, to a Tenth of a Degree (the app's NeatYaw)
# ------------------------------------------------------------
def na_neat_yaw(deg: float) -> float:
    turn = math.fmod(float(deg), 360.0)                                      # <-- fmod keeps the sign, as JavaScript's %
    if turn > 180:
        turn -= 360
    if turn <= -180:
        turn += 360
    return na_js_round(turn * 10) / 10
# ---------------------------------------------------------------

# FUNCTION | A SketchUp Pose as the App Saves It
# ------------------------------------------------------------
# SketchUp (x, y, z) inches, Z up -> three.js (x, z, -y) as whole mm. A turn about
# SketchUp's +Z is the same angle about three's +Y: both carry local x towards
# (cos, sin) seen from above, and three's -z is SketchUp's +y. Width lies along the
# plant's local x, depth along SketchUp's local y (three's local z), height up.
def na_pose_to_app(proxy: dict, nominal_mm: list | None) -> dict:
    x, y, z = [float(v) for v in proxy["OriginIn"]]
    scale = [float(v) for v in (proxy.get("ScaleXYZ") or [1.0, 1.0, 1.0])]
    return {"PositionMm": [na_js_round(x * NA__VEG__MM_PER_INCH), na_js_round(z * NA__VEG__MM_PER_INCH), na_js_round(-y * NA__VEG__MM_PER_INCH)],
            "YawDeg": na_neat_yaw(float(proxy.get("RotZDeg") or 0.0)),
            "SizeMm": [na_js_round(float(n) * s) for n, s in zip(nominal_mm, scale)] if nominal_mm else None}
# ---------------------------------------------------------------

# FUNCTION | A Saved Plant Back Into a SketchUp Pose (the exact inverse)
# ------------------------------------------------------------
def na_app_to_pose(view: dict, nominal_mm: list) -> dict:
    x, y, z = [float(v) for v in view["PositionMm"]]
    size = view.get("SizeMm") or nominal_mm
    return {"OriginIn": [x / NA__VEG__MM_PER_INCH, -z / NA__VEG__MM_PER_INCH, y / NA__VEG__MM_PER_INCH],
            "RotZDeg": float(view.get("YawDeg") or 0.0),
            "ScaleXYZ": [float(s) / float(n) for s, n in zip(size, nominal_mm)]}
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The App's Path Sums (Na__Vegetation__PathModel__.js and its generator)
# -----------------------------------------------------------------------------
# A PORT, checked against the JavaScript by numbers (DEVLOG 0.6.0). A saved seed must
# give the same plants on both sides, so a change there is a change here, in the same
# release. Draws come in the same order; JavaScript's 32-bit sums are masked by hand.

def na_imul(a: int, b: int) -> int:
    return ((a & NA__VEG__U32) * (b & NA__VEG__U32)) & NA__VEG__U32


class Na__VegRand:
    """Mulberry32, byte for byte Na__VegRand__Create."""

    def __init__(self, seed: int):
        self.state = (int(seed) & NA__VEG__U32) or 1

    def next(self) -> float:
        self.state = (self.state + 0x6D2B79F5) & NA__VEG__U32
        t = self.state
        t = na_imul(t ^ (t >> 15), t | 1)
        t = (t ^ ((t + na_imul(t ^ (t >> 7), t | 61)) & NA__VEG__U32)) & NA__VEG__U32
        return ((t ^ (t >> 14)) & NA__VEG__U32) / 4294967296

    def range(self, a: float, b: float) -> float:
        return a + (b - a) * self.next()

    def int(self, a: int, b: int) -> int:
        return a + math.floor((b - a + 1) * self.next())

    def chance(self, p: float) -> bool:
        return self.next() < p


# HELPER FUNCTION | One Item by Its Weight (Na__VegBrush__DrawItem)
# ------------------------------------------------------------
def na_draw_item(items: list, r: float) -> dict | None:
    if not items:
        return None
    total = sum(max(0, it.get("weight") or 0) for it in items)
    if total <= 0:
        return items[min(len(items) - 1, math.floor(r * len(items)))]
    left = r * total
    for it in items:
        left -= max(0, it.get("weight") or 0)
        if left < 0:
            return it
    return items[-1]
# ---------------------------------------------------------------

# HELPER FUNCTION | One Point of a Centripetal Catmull-Rom Span
# ------------------------------------------------------------
def na_curve_point(p0, p1, p2, p3, t: float) -> list:
    def knot(a, b, last):
        return last + math.pow(math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]) or 1e-6, 0.5)
    t0 = 0
    t1 = knot(p0, p1, t0)
    t2 = knot(p1, p2, t1)
    t3 = knot(p2, p3, t2)
    at = t1 + (t2 - t1) * t
    out = [0.0, 0.0, 0.0]
    for k in range(3):
        a1 = ((t1 - at) * p0[k] + (at - t0) * p1[k]) / (t1 - t0)
        a2 = ((t2 - at) * p1[k] + (at - t1) * p2[k]) / (t2 - t1)
        a3 = ((t3 - at) * p2[k] + (at - t2) * p3[k]) / (t3 - t2)
        b1 = ((t2 - at) * a1 + (at - t0) * a2) / (t2 - t0)
        b2 = ((t3 - at) * a2 + (at - t1) * a3) / (t3 - t1)
        out[k] = ((t2 - at) * b1 + (at - t1) * b2) / (t2 - t1)
    return out
# ---------------------------------------------------------------

# FUNCTION | The Line a Path Follows, and How Far Along Each Point Is (Na__VegPath__Line)
# ------------------------------------------------------------
def na_path_line(points_mm, curved: bool) -> dict:
    given = [p for p in (points_mm or []) if isinstance(p, list) and len(p) >= 3]
    points = given
    if curved and len(given) > 2:
        points = []
        for i in range(len(given) - 1):
            p1, p2 = given[i], given[i + 1]
            p0 = given[i - 1] if i > 0 else [2 * p1[0] - p2[0], 2 * p1[1] - p2[1], 2 * p1[2] - p2[2]]
            p3 = given[i + 2] if i + 2 < len(given) else [2 * p2[0] - p1[0], 2 * p2[1] - p1[1], 2 * p2[2] - p1[2]]
            chord = math.hypot(p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2])
            steps = max(2, min(NA__VEG__CURVE_MAX_STEPS, math.ceil(chord / NA__VEG__CURVE_STEP_MM)))
            for s in range(steps):
                points.append(na_curve_point(p0, p1, p2, p3, s / steps))
        points.append(given[-1])
    lengths, total = [0.0], 0.0
    for i in range(1, len(points)):
        total += math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1], points[i][2] - points[i - 1][2])
        lengths.append(total)
    return {"points": points, "lengths": lengths, "total": total}
# ---------------------------------------------------------------

# FUNCTION | Where a Line Is at a Distance Along It, and Which Way It Runs (Na__VegPath__AtDistance)
# ------------------------------------------------------------
def na_path_at(line: dict, distance: float) -> dict:
    points, lengths, total = line["points"], line["lengths"], line["total"]
    d = max(0, min(total, distance))
    i = 1
    while i < len(lengths) - 1 and lengths[i] < d:
        i += 1
    a, b = points[i - 1], points[i]
    span = lengths[i] - lengths[i - 1]
    t = (d - lengths[i - 1]) / span if span > 0 else 0
    dx, dz = 0.0, 0.0
    k = i
    while k >= 1 and dx == 0 and dz == 0:
        ex, ez = points[k][0] - points[k - 1][0], points[k][2] - points[k - 1][2]
        level = math.hypot(ex, ez)
        if level > 1e-6:
            dx, dz = ex / level, ez / level
        k -= 1
    if dx == 0 and dz == 0:
        dx = 1.0
    return {"x": a[0] + (b[0] - a[0]) * t, "y": a[1] + (b[1] - a[1]) * t, "z": a[2] + (b[2] - a[2]) * t, "dx": dx, "dz": dz}
# ---------------------------------------------------------------

# HELPER FUNCTION | A Seed for One Plant, from the Path's Seed and Its Number
# ------------------------------------------------------------
def na_plant_seed(path_seed: int, number: int) -> int:
    return (na_imul((int(path_seed) & NA__VEG__U32) ^ 0x9E3779B9, 0x85EBCA6B) + na_imul(number + 1, 0xC2B2AE35)) & NA__VEG__U32
# ---------------------------------------------------------------

# HELPER FUNCTION | The Next Real Corner of a Line Past a Distance (Na__VegPath__NextCorner)
# ------------------------------------------------------------
def na_next_corner(line: dict, distance: float) -> dict:
    points, lengths = line["points"], line["lengths"]
    for i in range(1, len(points) - 1):
        if lengths[i] <= distance + NA__VEG__CORNER_SLACK_MM:
            continue
        ax, az = points[i][0] - points[i - 1][0], points[i][2] - points[i - 1][2]
        bx, bz = points[i + 1][0] - points[i][0], points[i + 1][2] - points[i][2]
        turn = abs(math.atan2(ax * bz - az * bx, ax * bx + az * bz))
        if turn >= NA__VEG__CORNER_TURN_RAD:
            return {"at": lengths[i], "tan": min(NA__VEG__CORNER_MAX_TAN, math.tan(turn / 2))}
    return {"at": line["total"], "tan": 0}
# ---------------------------------------------------------------

# HELPER FUNCTION | A Scale If It Is One, Else 1
# ------------------------------------------------------------
def na_scale_of(value) -> float:
    return value if isinstance(value, (int, float)) and value > 0 else 1
# ---------------------------------------------------------------

# FUNCTION | Every Plant of a Path, in the Shape of Saved Plops (Na__VegPath__PlantsFor)
# ------------------------------------------------------------
def na_plants_for(path: dict, items: list) -> list:
    usable = [it for it in (items or []) if it.get("recipe") and (it.get("weight") or 0) > 0]
    line = na_path_line(path.get("Vegetation__Path__PointsMm"), path.get("Vegetation__Path__Curved") is True)
    if not usable or line["total"] <= 0:
        return []
    rules = path.get("Vegetation__Path__Advanced") or {}
    path_seed = path.get("Vegetation__Path__Seed") or 1
    spacing = max(NA__VEG__MIN_SPACING_MM, path.get("Vegetation__Path__SpacingMm") or NA__VEG__MIN_SPACING_MM)
    fit = rules.get("Vegetation__PathAdvanced__FitLastPlant") is not False
    align_any = rules.get("Vegetation__PathAdvanced__AlignToPath") is not False
    rot_var = rules.get("Vegetation__PathAdvanced__RotationVariationDeg") or 0
    scale_var = (rules.get("Vegetation__PathAdvanced__ScaleVariationPercent") or 0) / 100
    height_var = (rules.get("Vegetation__PathAdvanced__HeightVariationPercent") or 0) / 100
    space_var = (rules.get("Vegetation__PathAdvanced__SpacingVariationPercent") or 0) / 100
    side_offset = rules.get("Vegetation__PathAdvanced__SideOffsetMm") or 0
    depth_fit = rules.get("Vegetation__PathAdvanced__DepthAcrossMm") or 0
    height_fit = rules.get("Vegetation__PathAdvanced__HeightFitMm") or 0
    path_zoom = na_scale_of(path.get("Vegetation__Path__PlantScale"))

    wanted = na_js_round(line["total"] / spacing) if fit else math.ceil(line["total"] / spacing)
    cells = max(1, min(NA__VEG__MAX_PLANTS, wanted))
    cell = line["total"] / cells if fit else spacing

    plants = []
    at, number, tan_behind = 0, 0, 0
    while at < cells - NA__VEG__END_SLACK and number < NA__VEG__MAX_PLANTS:
        rng = Na__VegRand(na_plant_seed(path_seed, number))
        item = na_draw_item(usable, rng.next())
        recipe = item["recipe"]
        place = recipe.get("Asset__Placement") or {}
        size = recipe["Asset__Size"]
        is_run = place.get("Placement__StretchAlongPath") is True
        kept = place.get("Placement__Clipped") is True
        zoom = path_zoom * na_scale_of(item.get("scale"))

        run_wanted = rng.int(NA__VEG__RUN_MIN_CELLS, NA__VEG__RUN_MAX_CELLS)
        span = min(run_wanted, cells - at) if is_run else 1

        kept_run = kept and is_run
        corner = na_next_corner(line, at * cell) if kept_run else None
        if kept_run:
            start = at * cell
            finish = min(start + span * cell, start + NA__VEG__CLIPPED_MAX_MM * zoom, corner["at"])
            if corner["at"] - finish < cell * NA__VEG__CLIPPED_SLIVER:
                finish = corner["at"]
            span = max((finish - start) / cell, NA__VEG__END_SLACK)

        slip = rng.range(-space_var, space_var) * cell
        mid = (at + span / 2) * cell + (0 if (is_run or kept) else slip)
        spot = na_path_at(line, mid)

        drawn_scale = 1 + rng.range(-scale_var, scale_var)
        drawn_higher = 1 + rng.range(-height_var, height_var)
        scale = 1 if kept else drawn_scale
        higher = 1 if kept else drawn_higher
        depth_mm = depth_fit / zoom if depth_fit > 0 else size["Size__DepthMm"] * scale
        height_mm = (height_fit / zoom if height_fit > 0 else size["Size__HeightMm"]) * scale * higher

        end_behind, end_ahead, ends = 0, 0, None
        if kept_run:
            lap = ((recipe.get("Asset__Form") or {}).get("Form__LapMm") or 0) * zoom
            half_depth = (depth_mm * zoom) / 2
            start = at * cell
            finish = start + span * cell
            is_start = start <= NA__VEG__CORNER_SLACK_MM
            is_finish = finish >= line["total"] - NA__VEG__CORNER_SLACK_MM
            at_corner = (not is_finish) and corner["tan"] > 0 and finish >= corner["at"] - NA__VEG__CORNER_SLACK_MM
            end_behind = 0 if is_start else (tan_behind * half_depth if tan_behind > 0 else lap)
            end_ahead = 0 if is_finish else (corner["tan"] * half_depth if at_corner else lap)
            ends = ["End" if is_start else ("Corner" if tan_behind > 0 else "Lap"),
                    "End" if is_finish else ("Corner" if at_corner else "Lap")]
            tan_behind = corner["tan"] if at_corner else 0
        along = (end_ahead - end_behind) / 2

        if kept_run:
            width_mm = (span * cell + end_behind + end_ahead) / zoom
        elif is_run:
            width_mm = max(size["Size__WidthMm"] * NA__VEG__RUN_MIN_WIDTH, (span * cell * NA__VEG__RUN_FILL_SHARE) / zoom)
        else:
            width_mm = size["Size__WidthMm"] * scale

        heading = math.degrees(math.atan2(-spot["dz"], spot["dx"]))
        aligned = is_run or depth_fit > 0 or (align_any and place.get("Placement__AlignToPath") is True)
        turned = rng.range(-rot_var, rot_var)
        flipped = 180 if rng.chance(0.5) else 0
        free = rng.range(-180, 180)
        yaw_deg = (heading + (0 if kept else turned + flipped)) if aligned else free

        drawn_side = rng.range(-side_offset, side_offset)
        side = 0 if kept else drawn_side
        x = spot["x"] - spot["dz"] * side + spot["dx"] * along
        z = spot["z"] + spot["dx"] * side + spot["dz"] * along

        plant = {NA__VEG__P_UID: f"{path.get('Vegetation__Path__Uid')}-{str(number + 1).zfill(3)}",
                 NA__VEG__P_ASSET: item["assetId"],
                 NA__VEG__P_SEED: math.floor(rng.next() * NA__VEG__SEED_LIMIT),
                 NA__VEG__P_POSITION: [na_js_round(x), na_js_round(spot["y"]), na_js_round(z)],
                 NA__VEG__P_YAW: na_neat_yaw(yaw_deg),
                 NA__VEG__P_SIZE: [na_js_round(width_mm), na_js_round(depth_mm), na_js_round(height_mm)],
                 "Vegetation__Plop__PathUid": path.get("Vegetation__Path__Uid")}
        if zoom != 1:
            plant[NA__VEG__P_SCALE] = na_js_round(zoom * 1000) / 1000
        if ends:
            plant["Vegetation__Plop__Ends"] = ends
        plants.append(plant)
        at += span
        number += 1
    return plants
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Assets (the project's own copy first, then the library on this PC)
# -----------------------------------------------------------------------------

# FUNCTION | The Vegetation Library on This PC, from the Server Manager's Sync Map
# ------------------------------------------------------------
def na_library_folder(sync_map: str) -> Path | None:
    try:
        cfg = json.loads(Path(sync_map).read_text(encoding="utf-8"))
        return Path(cfg["Local"]["MirrorRoot"]) / NA__VEG__APP_DIR / NA__VEG__LIBRARY_DIR
    except (OSError, ValueError, KeyError, TypeError):
        return None
# ---------------------------------------------------------------

# FUNCTION | A Reader of Assets, Reading Each File Once
# ------------------------------------------------------------
# Returns recipe_of(asset_id) -> the recipe, or None. A project draws from its own copy,
# so that is what decides a plant's nominal size here too.
def na_recipe_reader(scene: dict, library: Path | None):
    pinned = scene.get(NA__VEG__K_ASSETS) or {}
    cache = {}

    def library_recipe(asset_id: str):
        if asset_id in cache:
            return cache[asset_id]
        cache[asset_id] = None
        if library is not None:
            try:
                index = json.loads((library / NA__VEG__LIBRARY_INDEX).read_text(encoding="utf-8"))
                row = next((r for r in index.get("VegetationLibrary__Index__Assets") or [] if r.get("Asset__Id") == asset_id), None)
                if row:
                    cache[asset_id] = json.loads((library / row["Asset__File"]).read_text(encoding="utf-8"))
            except (OSError, ValueError, KeyError, TypeError):
                pass
        return cache[asset_id]

    def recipe_of(asset_id: str):
        return pinned.get(asset_id) or library_recipe(asset_id)
    return recipe_of
# ---------------------------------------------------------------

# HELPER FUNCTION | An Asset's Own Size From Its Recipe, as [width, depth, height], or None
# ------------------------------------------------------------
def na_recipe_size(recipe: dict | None) -> list | None:
    size = (recipe or {}).get("Asset__Size") or {}
    values = [size.get("Size__WidthMm"), size.get("Size__DepthMm"), size.get("Size__HeightMm")]
    return values if all(isinstance(v, (int, float)) and v > 0 for v in values) else None
# ---------------------------------------------------------------

# FUNCTION | Every Plant of Every Path, by Uid
# ------------------------------------------------------------
def na_path_plants(scene: dict, recipe_of) -> dict:
    palettes = {p.get("Vegetation__Palette__Uid"): p for p in scene.get(NA__VEG__K_PALETTES) or [] if isinstance(p, dict)}
    plants = {}
    for path in scene.get(NA__VEG__K_PATHS) or []:
        palette = palettes.get(path.get("Vegetation__Path__PaletteUid")) or {}
        items = [{"assetId": it.get("Vegetation__PaletteItem__AssetId"), "weight": it.get("Vegetation__PaletteItem__Weight"),
                  "scale": it.get("Vegetation__PaletteItem__PlantScale"), "recipe": recipe_of(it.get("Vegetation__PaletteItem__AssetId"))}
                 for it in palette.get("Vegetation__Palette__Items") or []]
        for plant in na_plants_for(path, items):
            plants[plant[NA__VEG__P_UID]] = plant
    return plants
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Three-Way Merge (base: what both sides held after the last sync)
# -----------------------------------------------------------------------------

# HELPER FUNCTION | The Part of a Plant That Is Compared and Kept in the Base
# ------------------------------------------------------------
def na_view(plop: dict, nominal_of) -> dict:
    asset = plop.get(NA__VEG__P_ASSET)
    size = plop.get(NA__VEG__P_SIZE) or nominal_of(asset)
    zoom = na_scale_of(plop.get(NA__VEG__P_SCALE))
    if size and zoom != 1:
        size = [na_js_round(mm * zoom) for mm in size]                       # <-- What it really measures (Na__VegData__PlopSizeMm)
    view = {"Uid": plop.get(NA__VEG__P_UID), "AssetId": asset, "PositionMm": list(plop.get(NA__VEG__P_POSITION) or [0, 0, 0]),
            "YawDeg": plop.get(NA__VEG__P_YAW) or 0, "SizeMm": size}
    if plop.get("Vegetation__Plop__PathUid"):
        view["PathUid"] = plop["Vegetation__Plop__PathUid"]
    return view
# ---------------------------------------------------------------

# HELPER FUNCTION | Is One Scale Close Enough to All Three Axes?
# ------------------------------------------------------------
def na_even_scale(ratios: list) -> float | None:
    if not ratios or any(r <= 0 for r in ratios):
        return None
    mean = sum(ratios) / len(ratios)
    return mean if all(abs(r - mean) <= mean * NA__VEG__EVEN_SCALE_SHARE for r in ratios) else None
# ---------------------------------------------------------------

# FUNCTION | Write What SketchUp Measures Into a Plant's Record
# ------------------------------------------------------------
# Evenly scaled, its plant scale moves, the same bush smaller. On one axis, its saved size
# moves, under its scale. Nothing that rounds away is written at all. Its own size stands
# for a plant that has none saved.
def na_write_size(rec: dict, measured: list, own_size: list | None) -> None:
    saved = rec.get(NA__VEG__P_SIZE) or own_size
    if not saved:
        rec[NA__VEG__P_SIZE] = measured
        return
    zoom = na_scale_of(rec.get(NA__VEG__P_SCALE))
    now = [mm * zoom for mm in saved]
    if all(abs(float(m) - n) <= NA__VEG__TOL_MM for m, n in zip(measured, now)):
        return
    even = na_even_scale([float(m) / n for m, n in zip(measured, now)])
    if even is None:
        rec[NA__VEG__P_SIZE] = [na_js_round(float(m) / zoom) for m in measured]
        return
    scale = na_js_round(zoom * even * 1000) / 1000
    if scale == 1:
        rec.pop(NA__VEG__P_SCALE, None)
    else:
        rec[NA__VEG__P_SCALE] = scale
# ---------------------------------------------------------------

# HELPER FUNCTION | Has a Plant Changed Against Another
# ------------------------------------------------------------
def na_differs(a: dict, b: dict) -> bool:
    if a.get("AssetId") != b.get("AssetId"):
        return True
    if any(abs(float(x) - float(y)) > NA__VEG__TOL_MM for x, y in zip(a["PositionMm"], b["PositionMm"])):
        return True
    turn = abs(float(a.get("YawDeg") or 0) - float(b.get("YawDeg") or 0)) % 360.0
    if min(turn, 360.0 - turn) > NA__VEG__TOL_DEG:
        return True
    sa, sb = a.get("SizeMm"), b.get("SizeMm")
    return bool(sa and sb and any(abs(float(x) - float(y)) > NA__VEG__TOL_MM for x, y in zip(sa, sb)))
# ---------------------------------------------------------------

# HELPER FUNCTION | The Next Free Plop Uid (the app's NextUid, over every Uid either side has used)
# ------------------------------------------------------------
def na_next_uid(used: set) -> str:
    top = 0
    for uid in used:
        text = str(uid)
        if text.startswith("A"):
            try:
                top = max(top, int(text[1:]))
            except ValueError:
                continue
    return "A" + str(top + 1).zfill(4)
# ---------------------------------------------------------------

# FUNCTION | Merge SketchUp's Proxies and the Project's Planting
# ------------------------------------------------------------
def na_merge(base: list, scene: dict, proxies: list, model_nominals: dict, recipe_of) -> dict:
    """base: the plants both sides held after the last sync. scene: the Vegetation__SceneData read just now. proxies:
    SketchUp's, each {Key, Uid ('' when new), PathUid, AssetId, OriginIn, RotZDeg, ScaleXYZ}. model_nominals: the size each
    of the model's proxy definitions was built at (a proxy's scale means nothing without it). recipe_of: na_recipe_reader's.
    Returns {Plops (the object's list after the merge), Pins (assets to copy into the object), Apply (SketchUp's ops),
    Base, Definitions, Clashes, Notes, Moved, Returned, Counts, AppChanged}. ValeVision wins a clash."""
    def nominal_of(asset_id):
        return model_nominals.get(asset_id) or na_recipe_size(recipe_of(asset_id))

    apply, clashes, notes, moved, returned, pins = [], [], [], [], [], {}
    definitions, skipped = {}, set()
    counts = {"new": 0, "moved": 0, "removed": 0}
    changed = False

    def name_of(asset_id):
        recipe = recipe_of(asset_id) or {}
        return recipe.get("Asset__Name") or asset_id

    def need_definition(asset_id):                                           # <-- What Ruby needs to build the proxy, if the model has none yet
        if asset_id not in definitions:
            recipe = recipe_of(asset_id) or {}
            definitions[asset_id] = {"Name": name_of(asset_id), "NominalMm": nominal_of(asset_id), "Proxy": recipe.get("Asset__Proxy") or {}}

    def pose_op(op: str, view: dict, proxy: dict | None = None) -> bool:     # <-- proxy: the one being moved, whose own definition its scale is of
        nominal = (proxy or {}).get("NominalMm") or nominal_of(view["AssetId"])
        if not nominal:
            notes.append(f"{view['AssetId']} ({view['Uid']}): not in the project or the library on this PC; not brought into SketchUp")
            skipped.add(view["Uid"])
            return False
        need_definition(view["AssetId"])
        entry = dict(Op=op, Uid=view["Uid"], PathUid=view.get("PathUid") or "", AssetId=view["AssetId"], Name=name_of(view["AssetId"]),
                     **na_app_to_pose(view, nominal))
        if proxy:
            entry["Key"] = proxy["Key"]
        apply.append(entry)
        return True

    # EVERY PROXY INTO ONE OF THREE LISTS | A copy brings its Uid with it, so the first keeps the name
    free, from_path, fresh = {}, {}, []
    for proxy in proxies:
        uid, path_uid = proxy.get("Uid") or "", proxy.get("PathUid") or ""
        view = dict(proxy, Uid=uid, **na_pose_to_app(proxy, proxy.get("NominalMm") or nominal_of(proxy.get("AssetId"))))
        if path_uid and uid and uid not in from_path:
            from_path[uid] = view
        elif uid and not path_uid and uid not in free:
            free[uid] = view
        else:
            if uid:
                apply.append({"Op": "unstamp", "Key": proxy["Key"], "Uid": uid})
            fresh.append(view)

    plops = [dict(p) for p in scene.get(NA__VEG__K_PLOPS) or [] if isinstance(p, dict)]
    used = {p.get(NA__VEG__P_UID) for p in plops} | {e.get("Uid") for e in base if isinstance(e, dict)} | set(free)
    used.discard(None)
    for plop in plops:                                                       # <-- A plop with no name cannot be followed: it gets one
        if not plop.get(NA__VEG__P_UID):
            plop[NA__VEG__P_UID] = na_next_uid(used)
            used.add(plop[NA__VEG__P_UID])
            changed = True

    B = {e["Uid"]: e for e in base if isinstance(e, dict) and e.get("Uid") and not e.get("PathUid")}
    B_path = {e["Uid"]: e for e in base if isinstance(e, dict) and e.get("Uid") and e.get("PathUid")}
    records = {p[NA__VEG__P_UID]: p for p in plops}
    order = [p[NA__VEG__P_UID] for p in plops]
    A = {uid: na_view(p, nominal_of) for uid, p in records.items()}

    def pull(uid, s=None):                                                   # <-- ValeVision's plant onto SketchUp
        if s is not None and s.get("AssetId") == A[uid]["AssetId"]:
            pose_op("update", A[uid], s)
        else:
            if s is not None:
                apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})  # <-- Swapped for another asset: a new proxy of the new asset
            pose_op("create", A[uid])

    def push(uid, s):                                                        # <-- SketchUp's pose into the record
        rec = records[uid]
        rec[NA__VEG__P_POSITION] = s["PositionMm"]
        rec[NA__VEG__P_YAW] = s["YawDeg"]
        if s.get("SizeMm"):
            na_write_size(rec, s["SizeMm"], nominal_of(rec.get(NA__VEG__P_ASSET)))
        A[uid] = na_view(rec, nominal_of)
        counts["moved"] += 1

    for uid in sorted(set(B) | set(A) | set(free)):
        b, a, s = B.get(uid), A.get(uid), free.get(uid)
        if b and a and s:
            su, vv = na_differs(s, b), na_differs(a, b)
            if su and vv:
                clashes.append(f"{name_of(a['AssetId'])} ({uid}) changed in both: ValeVision's kept")
                pull(uid, s)
            elif vv:
                pull(uid, s)
            elif su:
                if s.get("AssetId") != a.get("AssetId"):                     # <-- The proxy was swapped for another asset in SketchUp
                    fresh.append(dict(s, Uid=""))
                    apply.append({"Op": "unstamp", "Key": s["Key"], "Uid": uid})
                    del records[uid]
                    del A[uid]
                    counts["removed"] += 1
                else:
                    push(uid, s)
                changed = True
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
                clashes.append(f"{name_of(s['AssetId'])} ({uid}) deleted in ValeVision but moved in SketchUp: taken out")
            apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})
        elif a and s and not b:
            if na_differs(s, a):
                pull(uid, s)                                                 # <-- No common past: ValeVision's is the record
        elif a and not b and not s:
            pull(uid)
        elif s and not a and not b:
            fresh.append(dict(s, Uid=""))                                    # <-- A Uid neither side knows: placed afresh
            apply.append({"Op": "unstamp", "Key": s["Key"], "Uid": uid})

    # NEW IN SKETCHUP | A plop of its own, with a seed of its own, and its asset copied in
    for proxy in fresh:
        asset_id = proxy.get("AssetId")
        recipe = recipe_of(asset_id)
        if not recipe or not proxy.get("SizeMm"):
            notes.append(f"{asset_id}: not in the project or the library on this PC; left in SketchUp only")
            continue
        uid = na_next_uid(used)
        used.add(uid)
        records[uid] = {NA__VEG__P_UID: uid, NA__VEG__P_ASSET: asset_id, NA__VEG__P_SEED: secrets.randbelow(NA__VEG__SEED_LIMIT),
                        NA__VEG__P_POSITION: proxy["PositionMm"], NA__VEG__P_YAW: proxy["YawDeg"], NA__VEG__P_SIZE: proxy["SizeMm"]}
        even = na_even_scale([float(v) for v in (proxy.get("ScaleXYZ") or [1.0, 1.0, 1.0])])
        own_size = proxy.get("NominalMm") or nominal_of(asset_id)
        if even is not None and own_size and na_js_round(even * 1000) != 1000:   # <-- Placed and scaled evenly: its own size, and a scale
            records[uid][NA__VEG__P_SIZE] = [na_js_round(float(mm)) for mm in own_size]
            records[uid][NA__VEG__P_SCALE] = na_js_round(even * 1000) / 1000
        order.append(uid)
        A[uid] = na_view(records[uid], nominal_of)
        if asset_id not in (scene.get(NA__VEG__K_ASSETS) or {}):
            pins[asset_id] = copy.deepcopy(recipe)
        apply.append({"Op": "stamp", "Key": proxy["Key"], "Uid": uid, "PathUid": "", "AssetId": asset_id, "Name": name_of(asset_id)})
        counts["new"] += 1
        changed = True

    # A PATH'S PLANTS | Worked out from its rules, never from the record: read-only here
    wanted = {uid: na_view(plant, nominal_of) for uid, plant in na_path_plants(scene, recipe_of).items()}
    for uid, want in wanted.items():
        s = from_path.get(uid)
        if s is None:
            if uid in B_path:
                returned.append(uid)
            pose_op("create", want)
        elif s.get("AssetId") != want["AssetId"]:
            apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})
            pose_op("create", want)
        elif na_differs(s, want):
            if uid in B_path and not na_differs(B_path[uid], want):
                moved.append(uid)
            pose_op("update", want, s)
    for uid, s in from_path.items():
        if uid not in wanted:
            apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})

    new_base = [A[uid] for uid in order if uid in A and uid not in skipped]
    new_base += [want for uid, want in wanted.items() if uid not in skipped]
    return {"Plops": [records[uid] for uid in order if uid in records], "Pins": pins, "Apply": apply, "Base": new_base,
            "Definitions": definitions, "Clashes": clashes, "Notes": notes, "Moved": moved, "Returned": returned,
            "Counts": counts, "AppChanged": changed, "PathPlants": len(wanted)}
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
        return f"ValeVision 3D refused this account: {error} (changing a project's vegetation is for App Admins)."
    if error.status == 404:
        return f"The server has no project {library_id}: run Sync Project To ValeVision 3D once."
    return str(error)
# ---------------------------------------------------------------

# FUNCTION | The Project's Vegetation Object as It Is on the Server, or None With a Step Saying Why
# ------------------------------------------------------------
def na_read_scene(args, session: dict, rep) -> dict | None:
    try:
        record = aura.na_api(args.site, "GET", f"projects/{args.library_id}", session, api=NA__VEG__API)
    except aura.Na__AuraApiError as e:
        rep.step("Read The Project", False, na_api_words(e, args.library_id))
        return None
    scene = record.get(NA__VEG__ROOT_KEY)
    if not isinstance(scene, dict):
        rep.step("Read The Project", False, f"Vegetation is not switched on for {args.library_id}: in ValeVision 3D, Dev Tools, "
                 "Vegetation, Switch On, then sync here. Nothing was changed.")
        return None
    if scene.get(NA__VEG__K_ENABLED) is not True:
        rep.step("Read The Project", False, f"Vegetation is switched off for {args.library_id} in ValeVision 3D's Dev Tools. "
                 "Its plants are kept; switch it on to sync. Nothing was changed.")
        return None
    return scene
# ---------------------------------------------------------------

# HELPER FUNCTION | An Object as One String, Whatever Order Its Keys Came In
# ------------------------------------------------------------
def na_canon(value) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False)
# ---------------------------------------------------------------

# FUNCTION | Sync the Planting Both Ways
# ------------------------------------------------------------
def na_sync_planting(args, session: dict, sketchup: dict, rep) -> dict | None:
    same_project = sketchup.get("BaseProjectId") in ("", None, args.library_id)
    base = (sketchup.get("Base") or []) if sketchup.get("BaseProjectId") == args.library_id else []
    proxies = [p for p in sketchup.get("Proxies") or [] if isinstance(p, dict) and p.get("Key")]
    if not same_project:
        proxies = [dict(p, Uid="", PathUid="") for p in proxies]             # <-- Synced with another project: its Uids mean nothing here
    tilted = sum(1 for p in proxies if p.get("Tilted"))
    model_nominals = {k: v.get("NominalMm") for k, v in (sketchup.get("Definitions") or {}).items() if isinstance(v, dict)}
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
                rep.step("Sync Planting", False, "The project's vegetation keeps changing on the server (the app saving, or another "
                         "sync): nothing was sent, and SketchUp was not changed. Sync again in a moment.")
                return None
            continue
        out = dict(scene)
        out[NA__VEG__K_PLOPS] = merged["Plops"]
        if merged["Pins"]:
            out[NA__VEG__K_ASSETS] = {**(scene.get(NA__VEG__K_ASSETS) or {}), **merged["Pins"]}
        try:
            aura.na_api(args.site, "PATCH", f"projects/{args.library_id}", session, {NA__VEG__ROOT_KEY: out}, api=NA__VEG__API)
        except aura.Na__AuraApiError as e:
            rep.step("Sync Planting", False, na_api_words(e, args.library_id) + " Nothing was changed in SketchUp.")
            return None
        break

    ops, counts = merged["Apply"], merged["Counts"]
    count = lambda op: sum(1 for o in ops if o["Op"] == op)                  # noqa: E731
    parts = [f"{len(merged['Plops'])} placed plant(s) and {merged['PathPlants']} from paths in ValeVision"]
    if merged["AppChanged"]:
        parts.append(f"ValeVision updated ({counts['new']} new from SketchUp, {counts['moved']} moved, {counts['removed']} taken out)")
    if count("create") or count("update") or count("delete"):
        parts.append(f"SketchUp: {count('create')} to place, {count('update')} to move, {count('delete')} to take out")
    if not merged["AppChanged"] and not (count("create") or count("update") or count("delete")):
        parts.append("both sides already match")
    rep.step("Sync Planting", True, "; ".join(parts) + ".")
    if merged["Clashes"]:
        rep.step("Clashes (ValeVision Kept)", True, "; ".join(merged["Clashes"]) + ".")
    if merged["Moved"] or merged["Returned"]:
        told = []
        if merged["Moved"]:
            told.append(f"moved in SketchUp, put back where the path says: {', '.join(merged['Moved'][:12])}")
        if merged["Returned"]:
            told.append(f"deleted in SketchUp, put back: {', '.join(merged['Returned'][:12])}")
        rep.step("Path Plants Are Read-Only", True, "; ".join(told) + ". To change a path, edit it in ValeVision 3D or bake it to plants.", status="skip")
    if merged["Notes"] or tilted:
        rep.step("Planting Notes", True, "; ".join(merged["Notes"] + ([f"{tilted} tilted proxy(s) sent upright (a plant turns "
                                                                       "about the vertical only)"] if tilted else [])) + ".", status="skip")
    return {"Apply": ops, "Definitions": merged["Definitions"], "Base": merged["Base"], "BaseProjectId": args.library_id}
# ---------------------------------------------------------------

# FUNCTION | One Sync
# ------------------------------------------------------------
def na_sync(args) -> dict:
    rep = Na__VegReport(args)
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

    result = na_sync_planting(args, session, sketchup, rep)
    aura.na_write_session(Path(args.session_file), session)                  # <-- A renewed cookie is kept
    if result is None:
        return rep.finish()
    rep.extra["vegetation"] = result
    return rep.finish(f"Synced the planting of {args.library_id} with ValeVision 3D.")
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
    ap = argparse.ArgumentParser(description="ValeVision Cloud Sync: keep a SketchUp model's vegetation proxies and its project's planting in lockstep")
    ap.add_argument("--action", choices=NA__VEG__ACTIONS, required=True)
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
    print(f"ValeVision Cloud Sync vegetation sync {NA__VEG__VERSION}: {args.action} {args.library_id}", flush=True)
    try:
        report = na_sync(args)
    except Exception as e:                                                   # <-- Never leave the dialog without a report
        import traceback
        traceback.print_exc()
        report = {"success": False, "message": f"Vegetation sync error: {type(e).__name__}: {e}", "steps": [
            {"label": "Vegetation Sync", "success": False, "message": f"{type(e).__name__}: {e}"}]}
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
