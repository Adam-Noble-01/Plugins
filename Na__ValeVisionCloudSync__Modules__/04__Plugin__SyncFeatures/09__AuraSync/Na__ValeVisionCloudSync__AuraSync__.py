#!/usr/bin/env python3
"""
=============================================================================
 VALEDESIGNSUITE - VALEVISION CLOUD SYNC - AURA SYNC
=============================================================================

FILE       : Na__ValeVisionCloudSync__AuraSync__.py
AUTHOR     : Adam Noble - Noble Architecture
PURPOSE    : Keep one SketchUp model and its project's ValeVision AURA scene in
             lockstep: SketchUp's GLBs go up and replace AURA's model (the old
             set zipped, AURA's placed NPR assets kept), and AURA's placed assets
             come back as proxies, while proxies moved, added or deleted in
             SketchUp go back to AURA.
CREATED    : 30-Oct-2026

DESCRIPTION:
- Asked by Adam (30-Oct-2026): "the new tab should update the model on the Vale
  server, exporting new GLBs, archiving the old one in a zip file, and replacing
  it with a newer version of the model (but keeping all of the other assets,
  such as the NPR assets, etc.), and then syncing those back with the SketchUp
  model ... It's a two-way sync: changes in one update the other". His calls:
  AURA's own model set (ValeVision 3D untouched), sign in from the plugin, AURA
  wins a clash.
- REUSES the Library Publisher (imported from 08__LibraryPublisher): the report,
  the library lookup from the Server Manager's sync map, the GLB checks, the
  file placing and the engine's scoped collect and push. Nothing of it is copied.
- THE MODEL: the GLBs go into the project's
  ValeVision__AuraRender/Content__AuraScenePackages (an exact copy: the push
  prunes it), then AURA's API imports them (scene API 1.2.0, source SketchUp):
  the scene's previous set is zipped into Content__AuraScene__ModelFiles/
  00__Archive and read back before the older zip goes, object Ids are kept, and
  the placement, stored assets and the drawing set are untouched.
- THE ASSETS: AURA's drawing set (AuraDrawingSet__Engine.Settings.Assets) is
  user data, which the Server Manager never pushes, so it is read and written
  through AURA's API with a Vale sign-in. A three-way merge against the last
  synced state (kept in the SketchUp model) decides each plop: changed on one
  side goes to the other; changed on both, AURA wins and the clash is reported.
- COORDINATES are all here: SketchUp inches, Z up, front -Y; the GLB builder's
  glTF metres (x, z, -y); AURA's world is that turned about +Y by the scene's
  RotationDeg, then moved by OffsetM (the engine's own GlbTransform). Ruby hands
  over raw SketchUp poses and applies raw SketchUp poses.
- THE SIGN-IN: the shared Vale sign-in (/aura/api/accounts/login). The password
  arrives on stdin, never on the command line, never written anywhere; only the
  session cookie is kept, in the plugin's local-only user config folder.

USAGE:
  python Na__ValeVisionCloudSync__AuraSync__.py --action signin|signout|sync|assets
      --site https://app.valegardenhouses.com --session-file <json> --report-file <json>
      [--project-root <SketchUp project> --library-id <id> --sync-map <...> --engine <...>
       --mapping projects --sketchup-file <json>]
  signin reads {"email": ..., "password": ...} from stdin.

-----------------------------------------------------------------------------

DEVELOPMENT LOG:
30-Oct-2026 - Version 1.0.0
- Initial build: sign-in, the model to AURA (package, push, import), the
  two-way asset merge, the scene brought back down.

=============================================================================
"""

from __future__ import annotations

import argparse
import json
import math
import os
import secrets
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.cookies import SimpleCookie
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "08__LibraryPublisher"))
import Na__ValeVisionCloudSync__LibraryPublisher__ as pub                    # noqa: E402  <-- The publisher's own helpers, never copied


# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

NA__AURA__VERSION               = "1.0.0"
NA__AURA__ACTIONS               = ("signin", "signout", "sync", "assets")
NA__AURA__API                   = "/aura/api"
NA__AURA__COOKIE                = "vale_session"                            # <-- ValeShared__Auth__'s cookie: one sign-in for every Vale app
NA__AURA__USER_AGENT            = f"ValeVisionCloudSync/{NA__AURA__VERSION} (SketchUp; AURA sync)"
NA__AURA__TIMEOUT_S             = 120                                       # <-- An import copies and hashes every GLB on the server

NA__AURA__GLB_SYNC              = "ValeVision__AuraFileSync"                # <-- SketchUp project: this tab's own GLB export (never ValeVision 3D's)
NA__AURA__BUCKET                = "ValeVision__AuraRender"
NA__AURA__PACKAGE_DIR           = f"{NA__AURA__BUCKET}/Content__AuraScenePackages"
NA__AURA__MODEL_DIR             = f"{NA__AURA__BUCKET}/Content__AuraScene__ModelFiles"
NA__AURA__ARCHIVE_DIR           = "00__Archive"                             # <-- Never synced (KindExcludes): PC-only stale copies rest here

NA__AURA__APP_DIR               = "Vale__ValeVision__AuraRender"
NA__AURA__IMPORT_MAP            = "04__Lib__CoreEngine__VersionLocked/Vale__CoreEngine__ImportMap__Index__.json"
NA__AURA__ENGINE_PREFIX         = "PainterlyNPR/"
NA__AURA__ASSET_LIBRARY         = "12__Data__AssetLibrary"

NA__AURA__INCH_M                = 0.0254
NA__AURA__TOL_M                 = 0.001                                     # <-- AURA keeps positions to the millimetre
NA__AURA__TOL_DEG               = 0.05                                      # <-- ... turns to a tenth of a degree
NA__AURA__TOL_SCALE             = 0.0005                                    # <-- ... scales to a thousandth

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Report (the publisher's, with this tool's own fields)
# -----------------------------------------------------------------------------

class Na__AuraReport(pub.Na__Report):
    """The publisher's step trail, so the dialog renders both the same way."""

    def __init__(self, args):
        super().__init__(args)
        self.extra.update(aura_version=NA__AURA__VERSION)

    def finish(self, message: str = "") -> dict:
        out = super().finish(message)
        out["publisher_version"] = f"{pub.NA__PUB__VERSION} (AURA sync {NA__AURA__VERSION})"
        return out

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | AURA's API (HTTPS, the Vale session cookie)
# -----------------------------------------------------------------------------

class Na__AuraApiError(Exception):
    def __init__(self, status: int, message: str, body: dict | None = None):
        super().__init__(message)
        self.status = status
        self.body   = body or {}


# FUNCTION | The Kept Session (cookie and who it is), or None
# ------------------------------------------------------------
def na_read_session(path: Path) -> dict | None:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
        return doc if isinstance(doc, dict) and doc.get("Cookie") else None
    except (OSError, ValueError):
        return None
# ---------------------------------------------------------------

# FUNCTION | Keep a Session (written beside, then renamed: never half a file)
# ------------------------------------------------------------
def na_write_session(path: Path, session: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(session, indent=4, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)
# ---------------------------------------------------------------

# FUNCTION | One Call to AURA's API
# ------------------------------------------------------------
def na_api(site: str, method: str, route: str, session: dict | None = None, body=None) -> dict:
    """JSON in, JSON out. A renewed cookie (the server renews it on /me) is written back into session.
    Raises Na__AuraApiError with the server's own words on any refusal."""
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(f"{site}{NA__AURA__API}/{route}", data=data, method=method)
    req.add_header("Accept", "application/json")
    req.add_header("User-Agent", NA__AURA__USER_AGENT)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    if session and session.get("Cookie"):
        req.add_header("Cookie", f"{NA__AURA__COOKIE}={session['Cookie']}")
    try:
        with urllib.request.urlopen(req, timeout=NA__AURA__TIMEOUT_S) as res:
            raw, status, headers = res.read(), res.status, res.headers
    except urllib.error.HTTPError as e:
        raw, status, headers = e.read(), e.code, e.headers
    except (urllib.error.URLError, OSError) as e:
        raise Na__AuraApiError(0, f"app.valegardenhouses.com could not be reached ({getattr(e, 'reason', e)})")
    if session is not None:
        cookie = na_cookie_from(headers)
        if cookie:
            session["Cookie"] = cookie
    try:
        doc = json.loads(raw.decode("utf-8")) if raw else {}
    except (UnicodeDecodeError, ValueError):
        doc = {}
    if status >= 400 or not isinstance(doc, dict) or doc.get("ok") is False:
        error = (doc.get("error") if isinstance(doc, dict) else None) or f"HTTP {status}"
        raise Na__AuraApiError(status, str(error), doc if isinstance(doc, dict) else None)
    return doc
# ---------------------------------------------------------------

# HELPER FUNCTION | The Session Cookie From a Response's Set-Cookie Headers
# ------------------------------------------------------------
def na_cookie_from(headers) -> str:
    for line in (headers.get_all("Set-Cookie") or []) if headers else []:
        jar = SimpleCookie()
        try:
            jar.load(line)
        except Exception:                                                    # noqa: BLE001  <-- A cookie Python cannot parse is not ours
            continue
        if NA__AURA__COOKIE in jar and jar[NA__AURA__COOKIE].value:
            return jar[NA__AURA__COOKIE].value
    return ""
# ---------------------------------------------------------------

# HELPER FUNCTION | A Refusal in Words the Dialog Can Act On
# ------------------------------------------------------------
def na_api_words(error: Na__AuraApiError) -> str:
    if error.status == 401:
        return "Your AURA sign-in has ended (signed out, or the password changed): sign in again in the Sync Aura tab."
    if error.body.get("notSwitchedOn"):
        return str(error)                                                    # <-- The server says where to switch it on
    if error.status == 403:
        return f"AURA refused this account: {error} (AURA is for Managers and App Admins)."
    return str(error)
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Signing In and Out
# -----------------------------------------------------------------------------

# FUNCTION | Sign In (the password from stdin, never kept)
# ------------------------------------------------------------
def na_signin(args) -> dict:
    rep = Na__AuraReport(args)
    try:
        given = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        given = {}
    email, password = str(given.get("email") or "").strip(), str(given.get("password") or "")
    given = None                                                             # <-- Nothing of the password outlives this call
    if not email or not password:
        rep.step("Sign In", False, "Enter your email address and password.")
        return rep.finish()
    session = {}
    try:
        doc = na_api(args.site, "POST", "accounts/login", session, {"email": email, "password": password})
    except Na__AuraApiError as e:
        rep.step("Sign In", False, str(e))
        return rep.finish(str(e))
    finally:
        password = ""
    if not session.get("Cookie"):
        rep.step("Sign In", False, "The server accepted the sign-in but sent no session cookie.")
        return rep.finish()
    user = doc.get("user") or {}
    kept = {"Schema": "Na__ValeVisionCloudSync__AuraSession", "SchemaVersion": 1, "Site": args.site, "Email": email,
            "User": user, "SignedInIso": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "Cookie": session["Cookie"],
            "_About": "ValeVision Cloud Sync's sign-in to ValeVision AURA on this PC. A session, not a password: "
                      "Sign Out (Sync Aura tab) ends it on the server and deletes this file. Never commit or share it."}
    na_write_session(Path(args.session_file), kept)
    name = user.get("name") or user.get("displayName") or email
    rep.extra.update(user=user, email=email)
    rep.step("Sign In", True, f"Signed in as {name}.")
    return rep.finish(f"Signed in to AURA as {name}.")
# ---------------------------------------------------------------

# FUNCTION | Sign Out (the server first, then the file, whatever the server says)
# ------------------------------------------------------------
def na_signout(args) -> dict:
    rep = Na__AuraReport(args)
    path = Path(args.session_file)
    session = na_read_session(path)
    note = ""
    if session:
        try:
            na_api(args.site, "POST", "accounts/logout", dict(session))
        except Na__AuraApiError as e:
            note = f" (the server said: {e})"
    try:
        path.unlink(missing_ok=True)
    except OSError as e:
        rep.step("Sign Out", False, f"The session file could not be deleted: {e}")
        return rep.finish()
    rep.step("Sign Out", True, "Signed out of AURA on this PC" + note + ".")
    return rep.finish("Signed out of AURA.")
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Coordinates (SketchUp <-> AURA's world)
# -----------------------------------------------------------------------------

# FUNCTION | A SketchUp Pose Into AURA's World
# ------------------------------------------------------------
# SketchUp (x, y, z) inches -> glTF (x, z, -y) metres (the GLB builder's
# Z_UP_TO_Y_UP_MATRIX) -> turned about +Y by the placement's RotationDeg
# (right-handed, the engine's GlbTransform) -> moved by OffsetM. A turn about
# SketchUp's +Z is the same angle about glTF's +Y (both counter-clockwise seen
# from above), so a plop's RotationDeg is SketchUp's plus the placement's.
def na_to_aura(origin_in: list, rot_z_deg: float, scale: float, placement: dict) -> dict:
    gx, gy, gz = origin_in[0] * NA__AURA__INCH_M, origin_in[2] * NA__AURA__INCH_M, -origin_in[1] * NA__AURA__INCH_M
    a = math.radians(float(placement.get("RotationDeg") or 0.0))
    c, s = math.cos(a), math.sin(a)
    off = list(placement.get("OffsetM") or [0.0, 0.0, 0.0])
    p = [c * gx + s * gz + off[0], gy + off[1], -s * gx + c * gz + off[2]]
    return {"Position": [round(v, 3) + 0.0 for v in p],
            "RotationDeg": na_norm_deg(rot_z_deg + float(placement.get("RotationDeg") or 0.0)),
            "Scale": round(float(scale), 3)}
# ---------------------------------------------------------------

# FUNCTION | An AURA Plop Back Into a SketchUp Pose (the exact inverse)
# ------------------------------------------------------------
def na_to_sketchup(plop: dict, placement: dict) -> dict:
    off = list(placement.get("OffsetM") or [0.0, 0.0, 0.0])
    pos = list(plop.get("Position") or [0.0, 0.0, 0.0])
    dx, dy, dz = pos[0] - off[0], pos[1] - off[1], pos[2] - off[2]
    a = math.radians(float(placement.get("RotationDeg") or 0.0))
    c, s = math.cos(a), math.sin(a)
    gx, gy, gz = c * dx - s * dz, dy, s * dx + c * dz
    return {"OriginIn": [gx / NA__AURA__INCH_M, -gz / NA__AURA__INCH_M, gy / NA__AURA__INCH_M],
            "RotZDeg": na_norm_deg(float(plop.get("RotationDeg") or 0.0) - float(placement.get("RotationDeg") or 0.0), 6),
            "Scale": float(plop.get("Scale") or 1.0)}
# ---------------------------------------------------------------

# HELPER FUNCTION | An Angle in [0, 360)
# ------------------------------------------------------------
def na_norm_deg(deg: float, places: int = 1) -> float:
    value = round(((float(deg) % 360.0) + 360.0) % 360.0, places)
    return 0.0 if value >= 360.0 else value + 0.0
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Three-Way Merge (base: what both sides held after the last sync)
# -----------------------------------------------------------------------------

# HELPER FUNCTION | Has a Plop Changed Against Another (pose and asset)
# ------------------------------------------------------------
def na_differs(a: dict, b: dict) -> bool:
    if a.get("AssetId") != b.get("AssetId"):
        return True
    pa, pb = a.get("Position") or [0, 0, 0], b.get("Position") or [0, 0, 0]
    if any(abs(float(x) - float(y)) > NA__AURA__TOL_M for x, y in zip(pa, pb)):
        return True
    turn = abs(float(a.get("RotationDeg") or 0) - float(b.get("RotationDeg") or 0)) % 360.0
    if min(turn, 360.0 - turn) > NA__AURA__TOL_DEG:
        return True
    return abs(float(a.get("Scale") or 1) - float(b.get("Scale") or 1)) > NA__AURA__TOL_SCALE
# ---------------------------------------------------------------

# HELPER FUNCTION | The Part of a Plop the Base Keeps
# ------------------------------------------------------------
def na_base_entry(plop: dict) -> dict:
    return {"Uid": plop["Uid"], "AssetId": plop.get("AssetId"), "Position": list(plop.get("Position") or [0, 0, 0]),
            "RotationDeg": plop.get("RotationDeg", 0.0), "Scale": plop.get("Scale", 1.0)}
# ---------------------------------------------------------------

# HELPER FUNCTION | The Next Plop Uid (the engine's NextUid over every Uid either side has used)
# ------------------------------------------------------------
def na_next_uid(used: set) -> str:
    top = 0
    for uid in used:
        try:
            top = max(top, int(str(uid)[1:]))
        except ValueError:
            continue
    return "A" + str(top + 1).zfill(4)
# ---------------------------------------------------------------

# FUNCTION | Merge SketchUp's Proxies and AURA's Plops
# ------------------------------------------------------------
def na_merge(base: list, aura: list, proxies: list, placement: dict, new_plop) -> dict:
    """base: the plops both sides held after the last sync (AURA's world). aura: Settings.Assets now. proxies:
    SketchUp's, each {Key, Uid ('' when new), AssetId, OriginIn, RotZDeg, Scale}. new_plop(asset_id, pose, uid) makes an
    AURA plop for a proxy placed in SketchUp, or returns (None, why).
    Returns {Assets (AURA's list after the merge), Removed (Uids taken out of AURA), Apply (SketchUp's ops),
    Clashes, Notes, AuraChanged}. AURA wins a clash."""
    B = {p["Uid"]: p for p in base if p.get("Uid")}
    A = {p["Uid"]: p for p in aura if isinstance(p, dict) and p.get("Uid")}
    S, fresh = {}, []
    for proxy in proxies:
        uid = proxy.get("Uid") or ""
        if uid and uid not in S:
            S[uid] = dict(proxy, **na_to_aura(proxy["OriginIn"], proxy["RotZDeg"], proxy["Scale"], placement))
        else:
            fresh.append(proxy)                                              # <-- No Uid, or a copy of another proxy (its Uid came with it)

    out = {uid: dict(p) for uid, p in A.items()}
    order = [p["Uid"] for p in aura if isinstance(p, dict) and p.get("Uid")]
    apply, clashes, notes, removed = [], [], [], []
    changed = False

    def push_pose(uid, s):                                                   # <-- SketchUp's pose into AURA's record
        rec = out[uid]
        rec.update(Position=s["Position"], RotationDeg=s["RotationDeg"], Scale=s["Scale"])

    def pull(uid, s=None):                                                   # <-- AURA's plop onto SketchUp
        pose = na_to_sketchup(out[uid], placement)
        if s is not None and s.get("AssetId") == out[uid].get("AssetId"):
            apply.append(dict(Op="update", Key=s["Key"], Uid=uid, AssetId=out[uid]["AssetId"], Name=out[uid].get("Name"), **pose))
        else:
            if s is not None:
                apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})  # <-- A swapped asset: a new proxy of the new asset
            apply.append(dict(Op="create", Uid=uid, AssetId=out[uid]["AssetId"], Name=out[uid].get("Name"), **pose))

    for uid in sorted(set(B) | set(A) | set(S)):
        b, a, s = B.get(uid), A.get(uid), S.get(uid)
        if b and a and s:
            su, au = na_differs(s, b), na_differs(a, b)
            if su and au:
                clashes.append(f"{a.get('Name') or a.get('AssetId')} ({uid}) changed in both: AURA's kept")
                pull(uid, s)
            elif au:
                pull(uid, s)
            elif su:
                if s.get("AssetId") != a.get("AssetId"):                     # <-- The proxy was swapped for another asset in SketchUp
                    fresh.append(dict(s, Uid=""))
                    del out[uid]
                    removed.append(uid)
                    apply.append({"Op": "unstamp", "Key": s["Key"], "Uid": uid})
                else:
                    push_pose(uid, s)
                changed = True
        elif b and a and not s:
            if na_differs(a, b):
                clashes.append(f"{a.get('Name') or a.get('AssetId')} ({uid}) deleted in SketchUp but changed in AURA: put back")
                pull(uid)
            else:
                del out[uid]
                removed.append(uid)
                changed = True
        elif b and s and not a:
            if na_differs(s, b):
                clashes.append(f"{s.get('AssetId')} ({uid}) deleted in AURA but moved in SketchUp: taken out")
            apply.append({"Op": "delete", "Key": s["Key"], "Uid": uid})
        elif a and s and not b:
            if na_differs(s, a):
                pull(uid, s)                                                 # <-- No common past: AURA's is the record
        elif a and not b and not s:
            pull(uid)
        elif s and not a and not b:
            fresh.append(dict(s, Uid=""))                                    # <-- A Uid neither side knows: placed afresh
            apply.append({"Op": "unstamp", "Key": s["Key"], "Uid": uid})

    used = set(B) | set(A) | set(S) | set(out)
    for proxy in fresh:
        pose = na_to_aura(proxy["OriginIn"], proxy["RotZDeg"], proxy["Scale"], placement)
        uid = na_next_uid(used)
        plop, why = new_plop(proxy.get("AssetId"), pose, uid)
        if plop is None:
            notes.append(f"{proxy.get('AssetId')}: {why}; left in SketchUp only")
            continue
        used.add(uid)
        out[uid] = plop
        order.append(uid)
        apply.append({"Op": "stamp", "Key": proxy["Key"], "Uid": uid, "AssetId": plop["AssetId"]})
        changed = True

    assets = [out[uid] for uid in order if uid in out]
    return {"Assets": assets, "Removed": removed, "Apply": apply, "Clashes": clashes, "Notes": notes, "AuraChanged": changed}
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | A Plop for a Proxy Placed in SketchUp (from AURA's pinned library)
# -----------------------------------------------------------------------------

# FUNCTION | AURA's Pinned Asset Library on This PC (the one the server stores from)
# ------------------------------------------------------------
def na_pinned_library(sync_map: Path) -> Path | None:
    try:
        cfg = json.loads(sync_map.read_text(encoding="utf-8"))
        app = Path(cfg["Local"]["MirrorRoot"]) / NA__AURA__APP_DIR
        record = json.loads((app / NA__AURA__IMPORT_MAP).read_text(encoding="utf-8"))
        imports = next(v for k, v in record.items() if k.endswith("__Imports"))
        modules = (app / imports[NA__AURA__ENGINE_PREFIX]).resolve()
        return modules.parent / NA__AURA__ASSET_LIBRARY
    except (OSError, ValueError, KeyError, StopIteration, TypeError):
        return None
# ---------------------------------------------------------------

# FUNCTION | A Maker of Plops, Reading Each Asset's DAT Once
# ------------------------------------------------------------
def na_plop_maker(library: Path | None):
    cache = {}

    def make(asset_id: str, pose: dict, uid: str):
        if library is None:
            return None, "AURA's pinned asset library was not found on this PC"
        if asset_id not in cache:
            found = sorted(library.glob(f"*/{asset_id}__*/{asset_id}__DAT__*.json")) if asset_id else []
            try:
                cache[asset_id] = (json.loads(found[0].read_text(encoding="utf-8")) or {}).get("PainterlyNPR__AssetData") if found else None
            except (OSError, ValueError):
                cache[asset_id] = None
        dat = cache[asset_id]
        if not dat:
            return None, "not in AURA's pinned asset library yet (sync the engine into AURA first)"
        paint = dat.get("PainterlyNPR__AssetData__Painterly") or {}
        rules = dat.get("PainterlyNPR__AssetData__Placement") or {}
        seed = secrets.randbits(32) if rules.get("NewShapeEachPlop") else int((dat.get("PainterlyNPR__AssetData__Factory") or {}).get("StageSeed") or 0)
        return {"Uid": uid, "AssetId": asset_id,
                "Name": (dat.get("PainterlyNPR__AssetData__Identity") or {}).get("DisplayName") or asset_id,
                "Position": pose["Position"], "RotationDeg": pose["RotationDeg"], "Scale": pose["Scale"], "Seed": seed,
                "Recipe": {"Generator": paint.get("Generator"), "Params": dict(paint.get("Params") or {}), "Kind": paint.get("Kind"),
                           "Material": paint.get("Material"), "Role": paint.get("Role"),
                           "Flowers": dict(paint["Flowers"]) if paint.get("Flowers") else None}}, ""
    return make
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Steps
# -----------------------------------------------------------------------------

# FUNCTION | Resolve the Library Project (it must exist: AURA opens library projects only)
# ------------------------------------------------------------
def na_resolve(args, rep) -> tuple:
    try:
        library = pub.na_library_root(Path(args.sync_map), args.mapping)
    except (OSError, ValueError, KeyError) as e:
        rep.step("Resolve Library Project", False, f"Cannot read the Server Manager sync map {args.sync_map}: {e}")
        return None, None
    hits = pub.na_find_library_folder(library, args.library_id or "")
    if len(hits) != 1:
        rep.step("Resolve Library Project", False, (f"{args.library_id} is not in the Project Library: run Sync Project To "
                 "ValeVision 3D once, and switch it on for AURA in the Gallery's Project Editor."
                 if not hits else f"{args.library_id} is in more than one year folder: set the Library Project in Settings."))
        return None, None
    project = hits[0]
    rel = project.relative_to(library).as_posix()
    rep.extra.update(library_rel=rel, library_path=str(project))
    rep.step("Resolve Library Project", True, f"{rel}.")
    return project, rel
# ---------------------------------------------------------------

# FUNCTION | The Kept Sign-In, or a Step Saying There Is None
# ------------------------------------------------------------
def na_session_or_fail(args, rep) -> dict | None:
    session = na_read_session(Path(args.session_file))
    if not session:
        rep.step("AURA Sign-In", False, "Not signed in to AURA on this PC: sign in at the top of the Sync Aura tab.")
        return None
    who = (session.get("User") or {}).get("name") or session.get("Email") or "?"
    rep.step("AURA Sign-In", True, f"Signed in as {who}.")
    return session
# ---------------------------------------------------------------

# FUNCTION | Check This Tab's GLB Export
# ------------------------------------------------------------
def na_check_glbs(args, rep) -> list:
    folder = Path(args.project_root) / pub.NA__PUB__CONTENT_DELIVERED / NA__AURA__GLB_SYNC
    glbs = pub.na_glbs_in(folder)
    problems = [] if glbs else [f"no .glb files in {pub.NA__PUB__CONTENT_DELIVERED}/{NA__AURA__GLB_SYNC}"]
    problems += [f"{p.name}: {pub.na_glb_problem(p)}" for p in glbs if pub.na_glb_problem(p)]
    names = [pub.na_glb_library_name(p.name) for p in glbs]
    if len(set(n.lower() for n in names)) != len(names):
        problems.append("two GLBs end up with the same name after the __NaModel__ rename")
    if problems:
        rep.step("Check Exported Files", False, "Nothing was sent to AURA. " + "; ".join(problems[:8]))
    else:
        rep.step("Check Exported Files", True, f"{len(glbs)} GLB(s), {sum(p.stat().st_size for p in glbs) / 1e6:.1f} MB.")
    return glbs
# ---------------------------------------------------------------

# FUNCTION | The Package: the Project's Content__AuraScenePackages Holds This Sync's Set Alone
# ------------------------------------------------------------
def na_publish_package(project: Path, glbs: list, rep) -> list:
    bucket = project / NA__AURA__PACKAGE_DIR
    pairs = [(src, pub.na_glb_library_name(src.name)) for src in glbs]
    names = {n for _, n in pairs}
    purged = pub.na_purge(bucket, names, lambda n: n.lower().endswith(".glb"), False)
    counts = {"added": 0, "replaced": 0, "same": 0}
    for src, name in pairs:
        counts[pub.na_place(src, bucket / name, False)] += 1
    rep.extra["published"] += counts["added"] + counts["replaced"]
    rep.step("Publish AURA Package", True,
             f"{len(names)} model(s) in {NA__AURA__PACKAGE_DIR}: {counts['added']} new, {counts['replaced']} replaced, "
             f"{counts['same']} unchanged" + (f"; {len(purged)} old model(s) removed" if purged else "") + ".")
    return sorted(names)
# ---------------------------------------------------------------

# FUNCTION | Push This Project, the Package Folder Pruned to the PC's Set
# ------------------------------------------------------------
def na_push_package(args, rel: str, rep) -> bool:
    out = pub.na_engine(args, "push", rel, (f"{rel}/{NA__AURA__PACKAGE_DIR}",))
    if not out.get("ok"):
        rep.step("Push To Server", False, f"Not pushed: {out.get('error')}. AURA's model was not changed.")
        return False
    result = out.get("result") or {}
    counts = pub.na_plan_counts(out, args.mapping)
    pushed = sum(len(p.get("added", [])) + len(p.get("replaced", [])) for p in result.get("plans", []))
    removed = sum(len(p.get("deleted", [])) for p in result.get("plans", []))
    rep.extra["pushed"] = pushed
    if counts.get("shared_collect"):
        rep.step("Push To Server", False, "The server's record changed while this sync ran: run Sync Aura again.")
        return False
    mb = ((out.get("plans") or {}).get(args.mapping) or {}).get("push_bytes", 0) / 1e6
    rep.step("Push To Server", True, (f"Pushed {pushed} file(s), {mb:.1f} MB" if pushed else "Nothing new to push")
             + (f"; {removed} superseded package file(s) removed from the server (kept in its backup)" if removed else "") + ".")
    return True
# ---------------------------------------------------------------

# FUNCTION | AURA Imports the Package (the old set zipped, Ids, placement and assets kept)
# ------------------------------------------------------------
def na_import(args, session: dict, model_name: str, rep) -> dict | None:
    try:
        doc = na_api(args.site, "POST", f"projects/{args.library_id}/scene/import", session,
                     {"source": "SketchUp", "modelName": model_name})
    except Na__AuraApiError as e:
        rep.step("Update AURA Scene", False, na_api_words(e) + " The GLBs are on the server; Sync Aura again to retry.")
        return None
    scene = doc.get("scene") or {}
    source = scene.get("AuraScene__Source") or {}
    if source.get("Method") != "SketchUpScenePackage":                       # <-- An API before 1.2.0 ignores the source and copies ValeVision 3D's
        rep.step("Update AURA Scene", False, "AURA's server is older than scene API 1.2.0, so it imported ValeVision 3D's whitecard "
                 "instead of this model: push server-api and restart vale@ValeVision__AuraRender, then Sync Aura again. "
                 "SketchUp was not changed.")
        return None
    history = source.get("History") or []
    archived = history[-2].get("Import__ArchivedAs") if len(history) > 1 else None
    files = scene.get("AuraScene__ModelFiles") or []
    missing = sum(1 for o in scene.get("AuraScene__Objects") or [] if o.get("Object__Missing"))
    rep.extra.update(scene_rev=doc.get("rev"), import_number=source.get("ImportNumber"))
    rep.step("Update AURA Scene", True,
             f"Import {source.get('ImportNumber')}: {len(files)} model file(s), {len(scene.get('AuraScene__Objects') or [])} object(s)"
             + (f" ({missing} no longer in the model, Ids kept)" if missing else "")
             + (f"; the previous set zipped as {archived}" if archived else "")
             + f"; {len(scene.get('AuraScene__AssetFiles') or [])} stored NPR asset(s) kept.")
    return scene
# ---------------------------------------------------------------

# FUNCTION | Read the Scene Only (the assets-only sync)
# ------------------------------------------------------------
def na_read_scene(args, session: dict, rep) -> dict | None:
    try:
        doc = na_api(args.site, "GET", f"projects/{args.library_id}/scene", session)
    except Na__AuraApiError as e:
        rep.step("Read AURA Scene", False, na_api_words(e))
        return None
    if not doc.get("scene"):
        rep.step("Read AURA Scene", False, "This project has no AURA scene yet: run Sync Model and Assets first.")
        return None
    rep.step("Read AURA Scene", True, f"Import {(doc['scene'].get('AuraScene__Source') or {}).get('ImportNumber')}.")
    return doc["scene"]
# ---------------------------------------------------------------

# FUNCTION | Sync the NPR Assets Both Ways
# ------------------------------------------------------------
def na_sync_assets(args, session: dict, scene: dict, sketchup: dict, rep) -> dict | None:
    placement = scene.get("AuraScene__ModelPlacement") or {}
    proxies = [p for p in sketchup.get("Proxies") or [] if isinstance(p, dict) and p.get("Key")]
    base = sketchup.get("Base") or [] if sketchup.get("BaseProjectId") == args.library_id else []
    if sketchup.get("BaseProjectId") not in ("", None, args.library_id):
        proxies = [dict(p, Uid="") for p in proxies]                         # <-- Synced with another project: its Uids mean nothing here
    tilted = [p.get("AssetId") for p in proxies if p.get("Tilted")]
    maker = na_plop_maker(na_pinned_library(Path(args.sync_map)))

    for attempt in (1, 2):                                                   # <-- A save that lost the race reads again and merges again, once
        try:
            got = na_api(args.site, "GET", f"projects/{args.library_id}/drawings", session)
        except Na__AuraApiError as e:
            rep.step("Sync NPR Assets", False, na_api_words(e))
            return None
        doc, rev = got.get("drawings"), int(got.get("rev") or 0)
        settings = ((doc or {}).get("AuraDrawingSet__Engine") or {}).get("Settings") if isinstance(doc, dict) else None
        if not isinstance(settings, dict):                                   # <-- Never made here: the page writes a whole engine state
            rep.step("Sync NPR Assets", True, "AURA has no saved drawing set for this project yet, so there are no plops to bring "
                     "in and nowhere to send SketchUp's: open the project in AURA once, then Sync Assets.", status="skip")
            return {"Placement": placement, "Apply": [], "DrawingRev": rev, "BaseProjectId": sketchup.get("BaseProjectId") or "",
                    "Base": list(sketchup.get("Base") or [])}
        aura = list(settings.get("Assets") or [])
        merged = na_merge(base, aura, proxies, placement, maker)
        if not merged["AuraChanged"]:
            break
        settings["Assets"] = merged["Assets"]
        if merged["Removed"]:                                                # <-- As the engine's take-out: a removed plop's materials go with it
            gone = tuple(f"{uid}." for uid in merged["Removed"])
            settings["Materials"] = [m for m in settings.get("Materials") or []
                                     if not (isinstance(m, dict) and str(m.get("Object") or "").startswith(gone))]
        doc["_rev"] = rev
        try:
            saved = na_api(args.site, "PUT", f"projects/{args.library_id}/drawings", session, doc)
            rev = int(saved.get("rev") or rev)
            rep.extra["assets_stored"] = saved.get("assetsStored") or []
            break
        except Na__AuraApiError as e:
            if e.status == 409 and attempt == 1:
                continue
            rep.step("Sync NPR Assets", False, na_api_words(e) + " Nothing was changed in SketchUp.")
            return None

    ops = merged["Apply"]
    count = lambda op: sum(1 for o in ops if o["Op"] == op)                  # noqa: E731
    sent = sum(1 for o in ops if o["Op"] == "stamp")
    parts = [f"{len(merged['Assets'])} plop(s) in AURA"]
    if merged["AuraChanged"]:
        parts.append(f"AURA updated ({sent} new from SketchUp, {len(merged['Removed'])} taken out)")
    if count("create") or count("update") or count("delete"):
        parts.append(f"SketchUp: {count('create')} to place, {count('update')} to move, {count('delete')} to take out")
    if not merged["AuraChanged"] and not (count("create") or count("update") or count("delete")):
        parts.append("both sides already match")
    rep.step("Sync NPR Assets", True, "; ".join(parts) + ".")
    if merged["Clashes"]:
        rep.step("Asset Clashes (AURA Kept)", True, "; ".join(merged["Clashes"]) + ".")
    if merged["Notes"] or tilted:
        rep.step("Asset Notes", True, "; ".join(merged["Notes"] + ([f"{len(tilted)} tilted proxy(s) sent upright (AURA turns "
                                                                     "assets about the vertical only)"] if tilted else [])) + ".",
                 status="skip")
    return {"Placement": placement, "Apply": ops, "DrawingRev": rev, "BaseProjectId": args.library_id,
            "Base": [na_base_entry(p) for p in merged["Assets"]]}
# ---------------------------------------------------------------

# FUNCTION | Bring AURA's New Scene Down, and Rest PC-Only Model Copies in 00__Archive
# ------------------------------------------------------------
# A model file the import dropped would otherwise come back from the PC's old
# copy on the next push (the scene schema's known gap). 00__Archive never syncs.
def na_collect_scene(args, project: Path, rel: str, scene: dict, rep) -> None:
    out = pub.na_engine(args, "collect", rel)
    if not out.get("ok"):
        rep.step("Bring AURA Scene Down", True, f"Not collected ({out.get('error')}); the next sync collects it.", status="skip")
        return
    got = (out.get("result") or {}).get("received", 0)
    listed = {f.get("ModelFile__FileName") for f in scene.get("AuraScene__ModelFiles") or []}
    models = project / NA__AURA__MODEL_DIR
    rested = []
    for f in pub.na_glbs_in(models):
        if f.name not in listed:
            (models / NA__AURA__ARCHIVE_DIR).mkdir(parents=True, exist_ok=True)
            os.replace(f, models / NA__AURA__ARCHIVE_DIR / f.name)
            rested.append(f.name)
    rep.step("Bring AURA Scene Down", True, f"Collected {got} file(s)"
             + (f"; {len(rested)} model copy(s) no longer in the scene moved to {NA__AURA__MODEL_DIR}/{NA__AURA__ARCHIVE_DIR} on this PC"
                if rested else "") + ".")
# ---------------------------------------------------------------

# FUNCTION | One Sync: the Model and the Assets, or the Assets Alone
# ------------------------------------------------------------
def na_sync(args) -> dict:
    rep = Na__AuraReport(args)
    try:
        sketchup = json.loads(Path(args.sketchup_file).read_text(encoding="utf-8")) if args.sketchup_file else {}
    except (OSError, ValueError) as e:
        rep.step("Read SketchUp Proxies", False, f"The plugin's hand-over file could not be read: {e}")
        return rep.finish()
    project, rel = na_resolve(args, rep)
    if project is None:
        return rep.finish()
    session = na_session_or_fail(args, rep)
    if session is None:
        return rep.finish()

    if args.action == "sync":
        glbs = na_check_glbs(args, rep)
        if rep.failed:
            return rep.finish()
        out = pub.na_engine(args, "collect", rel)
        if not out.get("ok"):
            rep.step("Fetch Server Copy", False, f"Nothing was sent: the server's copy could not be checked first. {out.get('error')}")
            return rep.finish()
        rep.step("Fetch Server Copy", True, f"Brought down {(out.get('result') or {}).get('received', 0)} file(s) newer on the server.")
        try:
            na_publish_package(project, glbs, rep)
        except OSError as e:
            rep.step("Publish AURA Package", False, f"{type(e).__name__}: {e}. Nothing was pushed.")
            return rep.finish()
        if not na_push_package(args, rel, rep):
            return rep.finish()
        scene = na_import(args, session, str(sketchup.get("ModelName") or ""), rep)
    else:
        scene = na_read_scene(args, session, rep)
    if scene is None:
        na_write_session(Path(args.session_file), session)
        return rep.finish()

    result = na_sync_assets(args, session, scene, sketchup, rep)
    na_write_session(Path(args.session_file), session)                     # <-- A renewed cookie is kept
    if result is None:
        return rep.finish()
    rep.extra["aura"] = result
    if args.action == "sync":
        na_collect_scene(args, project, rel, scene, rep)
    return rep.finish(f"{'Synced' if args.action == 'sync' else 'Synced the NPR assets of'} {args.library_id} with ValeVision AURA.")
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
    ap = argparse.ArgumentParser(description="ValeVision Cloud Sync: keep a SketchUp model and its AURA scene in lockstep")
    ap.add_argument("--action", choices=NA__AURA__ACTIONS, required=True)
    ap.add_argument("--site", default="https://app.valegardenhouses.com")
    ap.add_argument("--session-file", required=True, help="the plugin's local-only AURA session (91__UserConfig__LocalOnly)")
    ap.add_argument("--project-root", default="", help="the SketchUp project folder")
    ap.add_argument("--library-id", default="", help="the library folder name, e.g. 63403__Thrower")
    ap.add_argument("--sync-map", default="", help="the Server Manager's VirtualServerManager__SyncMap__.json")
    ap.add_argument("--engine", default="", help="the Server Manager's VirtualServerManager__SyncEngine__.py")
    ap.add_argument("--mapping", default="projects")
    ap.add_argument("--sketchup-file", default="", help="the plugin's hand-over: model name, proxies, the last synced base")
    ap.add_argument("--report-file", default="")
    ap.add_argument("--json", action="store_true", help="also print the report as the last stdout line")
    args = ap.parse_args()
    args.site = args.site.rstrip("/")
    args.dry_run = False                                                     # <-- The publisher's report and engine helpers read these
    print(f"ValeVision Cloud Sync AURA sync {NA__AURA__VERSION}: {args.action} {args.library_id}", flush=True)
    try:
        report = {"signin": na_signin, "signout": na_signout}.get(args.action, na_sync)(args)
    except Exception as e:                                                   # <-- Never leave the dialog without a report
        import traceback
        traceback.print_exc()
        report = {"success": False, "message": f"AURA sync error: {type(e).__name__}: {e}", "steps": [
            {"label": "AURA Sync", "success": False, "message": f"{type(e).__name__}: {e}"}]}
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
