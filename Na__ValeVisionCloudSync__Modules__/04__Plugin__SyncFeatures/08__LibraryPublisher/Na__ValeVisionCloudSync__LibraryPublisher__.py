#!/usr/bin/env python3
"""
=============================================================================
 VALEDESIGNSUITE - VALEVISION CLOUD SYNC LIBRARY PUBLISHER
=============================================================================

FILE       : Na__ValeVisionCloudSync__LibraryPublisher__.py
AUTHOR     : Adam Noble - Noble Architecture
PURPOSE    : Publish one SketchUp project's exports into the Vale Projects Master
             Library on this PC, check them, then push that ONE project folder to
             app.valegardenhouses.com with the Vale Virtual Server Manager engine.
CREATED    : 06-Oct-2026

DESCRIPTION:
- Called by the plugin's SyncOrchestrator (one launch per sync button). Replaces the
  retired R2 / legacy Gallery-folder script: no Cloudflare, no CDN URLs, no index.
- Steps, all-or-nothing on the library side:
    1. Resolve      the library folder  <library>/ValeProjects__<yyyy>/<id>/
    2. Check        the SketchUp exports (IMG## PNGs, GLB headers, camera data)
    3. Fetch        the server's newer copy of THIS project first (engine collect --scope),
                    so edits made in the web apps are merged into, never overwritten
    4. Publish      images -> ValeVisionGallery buckets, 524p thumbnails -> Gallery +
                    ValeVision3D buckets, GLBs -> ValeVision3D bucket, record keys.
                    A changed GLB set first zips the previous set into the bucket's
                    00__Archive (one zip only), then the bucket holds the new set alone
    5. Verify       every name the record lists is in its bucket
    6. Push         THIS project folder only (engine push --scope); a GLB sync also prunes
                    the server's GLB bucket to match (--prune), so no stale model survives
- The library folder is found from the engine's own sync map, so the plugin publishes
  exactly where the push reads from.
- The record (ProjectData__<id>__.json) is shared by every app: only the keys this sync
  owns are changed; everything else, _rev included, is kept byte-for-byte.

USAGE:
  python Na__ValeVisionCloudSync__LibraryPublisher__.py --project-root <SketchUp project>
      --library-id <id> --year <yyyy> --action all|images|glb|cameras
      --sync-map <VirtualServerManager__SyncMap__.json> --engine <VirtualServerManager__SyncEngine__.py>
      [--mapping projects] [--create-new] [--local-only] [--dry-run] --report-file <json>

-----------------------------------------------------------------------------

DEVELOPMENT LOG:
07-Oct-2026 - Version 1.0.1
- GLB syncs keep one clean set. When the models change, the previous set in
  ValeVision3D/Content__3dModel__GlbFiles is zipped into its 00__Archive folder as
  <id>__ArchivedGlbFiles__DD-MMM-YYYY__.zip (read back before anything is deleted), the
  older archive zip is removed, and the bucket then holds the new GLBs only.
- The push prunes the server's GLB bucket to the PC's (engine 0.6.2 --prune): superseded
  GLBs and the older archive are deleted there too (backed up on the server; undo restores).
- Verify Library also fails on a GLB in the bucket that the record does not list.

06-Oct-2026 - Version 1.0.0
- Initial build: replaces AutomationUtil__SyncSingleProject__ToCloudAndWeb__Main__.py (R2).
  Image de-dupe by slot, 524p thumbnails, the scene-thumbnail re-point and the image
  lists are ported from it unchanged; GLB names keep the __NaModel__ -> __ValeVision__
  rename; model names are bare file names.

=============================================================================
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
from datetime import datetime
from pathlib import Path


# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

NA__PUB__VERSION                = "1.0.1"
NA__PUB__YEAR_PREFIX            = "ValeProjects__"                          # <-- Year folders in the library and in C:\01__ValeProjects
NA__PUB__CONTENT_DELIVERED      = "10__ContentDelivered__Local"            # <-- SketchUp project: delivered content
NA__PUB__GLB_SYNC               = "ValeVision__GlbFileSync"                # <-- SketchUp project: fresh GLBs (top level only)
NA__PUB__LOCAL_DATA_DIR         = "00__ProjectData"                         # <-- SketchUp project: local data (a JSON ARRAY)
NA__PUB__LOCAL_DATA_SUFFIX      = "__ProjectData__.json"

NA__PUB__BUCKET_FULL            = "ValeVisionGallery/Content__GalleryImages__FullQuality__VariantImages"
NA__PUB__BUCKET_524P            = "ValeVisionGallery/Content__GalleryImages__524p__VariantImages"
NA__PUB__BUCKET_THUMB           = "ValeVisionGallery/Content__GalleryImages__Thumbnail__VariantImages"
NA__PUB__BUCKET_SCENES          = "ValeVision3D/Content__AnimationScenes__Thumbnails"
NA__PUB__BUCKET_GLB             = "ValeVision3D/Content__3dModel__GlbFiles"
NA__PUB__NEW_PROJECT_DIRS       = (NA__PUB__BUCKET_FULL, NA__PUB__BUCKET_524P, NA__PUB__BUCKET_THUMB,
                                   NA__PUB__BUCKET_SCENES, NA__PUB__BUCKET_GLB,
                                   "ValeVision3D/Content__3dModel__AppGenerated",
                                   "ValeVision3D/UserData__UserAppConfigs",
                                   "ValeVision3D/UserData__UserGeneratedContent__Drawings",
                                   "ValeVision3D/UserData__UserGeneratedContent__Images",
                                   "LanternDesigner")

NA__PUB__IMAGE_MARKER           = "__WhitecardImage__"                      # <-- Every pipeline render carries it
NA__PUB__IMAGE_PATTERN          = re.compile(r"^IMG\d{2,3}.*__WhitecardImage__.*\.png$", re.IGNORECASE)
NA__PUB__SLOT_PATTERN           = re.compile(r"^(IMG\d{2,3}(?:_ART\d{2})?)", re.IGNORECASE)
NA__PUB__ART_PATTERN            = re.compile(r"^IMG\d{2,3}_ART\d{2}", re.IGNORECASE)
NA__PUB__IMG01_PATTERN          = re.compile(r"^IMG01(?:_ART\d{2})?__", re.IGNORECASE)
NA__PUB__THUMB_TOKEN            = "__Thumbnail__524p__"
NA__PUB__THUMB_LONG_EDGE        = 524
NA__PUB__THUMB_WEBP_QUALITY     = 82
NA__PUB__THUMB_JPG_QUALITY      = 88

NA__PUB__GLB_RENAME             = ("__NaModel__", "__ValeVision__")         # <-- SketchUp namespace -> app namespace
NA__PUB__GLB_ARCHIVE_DIR        = "00__Archive"                             # <-- Inside the GLB bucket: ONE zip of the previous set
NA__PUB__GLB_ARCHIVE_TOKEN      = "__ArchivedGlbFiles__"                    # <-- <id>__ArchivedGlbFiles__DD-MMM-YYYY__.zip
NA__PUB__MONTHS                 = ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")  # <-- English whatever the PC's locale

NA__PUB__KEY_CAMERA             = "ValeVison3D__SketchUpCameraData"         # <-- One 'i': the web app's key
NA__PUB__KEY_MODELS             = "valeVision_ModelUrls"
NA__PUB__SCENES_BLOCK           = "PresentationMode__SavedCameraScenes"
NA__PUB__SCENES_ARRAY           = "PresentationMode__SavedCameraScenes__Scenes"
NA__PUB__SCENE_THUMB            = "PresentationMode__Scene__ThumbnailUrl"
NA__PUB__SCENE_NAME             = "PresentationMode__Scene__Name"
NA__PUB__SCENE_ID               = "PresentationMode__Scene__Id"
NA__PUB__SCENE_ORDER            = "PresentationMode__Scene__Order"

NA__PUB__NOT_YET_REVIEWED       = "NOT YET REVIEWED"
NA__PUB__DEFAULT_NOTES          = "Write a description here. Credit artists or add critique if work is subpar and caused issues."
NA__PUB__META_PLACEHOLDERS      = {"DD-MMM-YYYY", "TBD", "N/A", "NONE", "NIL", "DEFAULT CONCEPT ARTIST", "DEFAULT DESIGNER"}
NA__PUB__TYPE_PATTERN           = re.compile(r"^(?:[A-Z]{2}-)?\d+__.+?__(Whitecard|Blockout|MaxModel)$")
NA__PUB__CAMERA_DEFAULTS        = {
    "Camera__DefaultPosition__Description": "All camera position/target values are integer millimeters; convert to 3D units in code.",
    "Camera__DefaultPos"     : {"Camera__DefaultPos__PosX": -5000, "Camera__DefaultPos__PosY": 2800, "Camera__DefaultPos__PosZ": 3250},
    "Camera__DefaultTarget"  : {"Camera__DefaultTarget__TargetX": -1250, "Camera__DefaultTarget__TargetY": 2570,
                                "Camera__DefaultTarget__TargetZ": -350},
    "Camera__DefaultRotation": {"Camera__DefaultRotation__RotX": -0.073, "Camera__DefaultRotation__RotY": -0.8346,
                                "Camera__DefaultRotation__RotZ": -0.0541},
    "Camera__DefaultMisc"    : {"Camera__DefaultMisc__Fov": 29.8628}
}

NA__PUB__ACTIONS                = ("all", "images", "glb", "cameras")
NA__PUB__ENGINE_TIMEOUT_S       = 60 * 60                                   # <-- A first push of large GLBs can take a while

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Report
# -----------------------------------------------------------------------------

class Na__Report:
    """Collects the step trail the dialog shows. Same shape as the retired script's report."""

    def __init__(self, args):
        self.args       = args
        self.steps      = []
        self.started    = time.time()
        self.extra      = {"library_id": args.library_id, "action": args.action, "published": 0, "pushed": 0,
                           "first_sync": False, "library_rel": "", "dry_run": bool(args.dry_run)}

    def step(self, label: str, ok: bool, message: str, status: str = ""):
        entry = {"label": label, "success": bool(ok), "message": message}
        if status:
            entry["status"] = status                                         # <-- 'skip' renders as SKIP in the dialog
        self.steps.append(entry)
        mark = "OK  " if ok else ("SKIP" if status == "skip" else "ERR ")
        print(f"  {mark} {label}: {message}", flush=True)

    @property
    def failed(self) -> bool:
        return any(not s["success"] and s.get("status") != "skip" for s in self.steps)

    def finish(self, message: str = "") -> dict:
        ok = not self.failed
        return {"success": ok,
                "message": message or ("Sync complete." if ok else "Sync stopped: see the step details."),
                "project": Path(self.args.project_root).name, "started_at": datetime.now().strftime("%d-%b-%Y at %H:%M"),
                "elapsed_ms": int((time.time() - self.started) * 1000),
                "uploaded": self.extra["pushed"], "mirrored": self.extra["published"],
                "publisher_version": NA__PUB__VERSION, **self.extra, "steps": self.steps}

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Library Location (from the Server Manager's sync map)
# -----------------------------------------------------------------------------

# FUNCTION | The Library Folder the Engine Pushes From
# ------------------------------------------------------------
def na_library_root(sync_map: Path, mapping_id: str) -> Path:
    cfg = json.loads(sync_map.read_text(encoding="utf-8"))
    for m in cfg.get("Mappings", []):
        if m.get("Id") == mapping_id:
            local = Path(m["Local"])
            return local if local.is_absolute() else Path(cfg["Local"]["MirrorRoot"]) / local
    raise ValueError(f"mapping '{mapping_id}' is not in {sync_map}")
# ---------------------------------------------------------------

# FUNCTION | Find the Project's Library Folder (unique across year folders)
# ------------------------------------------------------------
def na_find_library_folder(library: Path, library_id: str) -> list:
    return sorted(p for p in library.glob(f"{NA__PUB__YEAR_PREFIX}*/{library_id}") if p.is_dir())
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Reading the SketchUp Exports
# -----------------------------------------------------------------------------

# FUNCTION | Latest Edition Folder (newest VisDpt__*Whitecard*Edition* by time)
# ------------------------------------------------------------
def na_latest_edition(project_root: Path):
    content = project_root / NA__PUB__CONTENT_DELIVERED
    if not content.is_dir():
        return None
    eds = [d for d in content.iterdir() if d.is_dir() and "Whitecard" in d.name and "Edition" in d.name]
    return max(eds, key=lambda d: d.stat().st_mtime) if eds else None
# ---------------------------------------------------------------

# FUNCTION | The Latest Render per IMG## Slot (newest file wins; ART variants are their own slot)
# ------------------------------------------------------------
def na_latest_images(edition: Path) -> list:
    by_slot = {}
    for f in edition.iterdir():
        if not (f.is_file() and NA__PUB__IMAGE_PATTERN.match(f.name)):
            continue
        m = NA__PUB__SLOT_PATTERN.match(f.name)
        slot = m.group(1).upper() if m else f.name.upper()
        if slot not in by_slot or f.stat().st_mtime > by_slot[slot].stat().st_mtime:
            by_slot[slot] = f
    return sorted(by_slot.values(), key=lambda p: p.name.lower())
# ---------------------------------------------------------------

# FUNCTION | The Fresh GLBs (top level of ValeVision__GlbFileSync; archives and logs skipped)
# ------------------------------------------------------------
def na_fresh_glbs(project_root: Path) -> list:
    folder = project_root / NA__PUB__CONTENT_DELIVERED / NA__PUB__GLB_SYNC
    if not folder.is_dir():
        return []
    return sorted((f for f in folder.iterdir() if f.is_file() and f.suffix.lower() == ".glb"), key=lambda p: p.name)
# ---------------------------------------------------------------

# HELPER FUNCTION | The App's Name for a GLB
# ------------------------------------------------------------
def na_glb_library_name(name: str) -> str:
    return name.replace(*NA__PUB__GLB_RENAME)
# ---------------------------------------------------------------

# FUNCTION | The Local ProjectData Array (00__ProjectData/*__ProjectData__.json)
# ------------------------------------------------------------
def na_local_project_data(project_root: Path):
    folder = project_root / NA__PUB__LOCAL_DATA_DIR
    files = sorted(folder.glob(f"*{NA__PUB__LOCAL_DATA_SUFFIX}")) if folder.is_dir() else []
    if not files:
        return None, None
    return files[0], json.loads(files[0].read_text(encoding="utf-8"))
# ---------------------------------------------------------------

# HELPER FUNCTION | One Keyed Object From the Local Array (or a flat dict)
# ------------------------------------------------------------
def na_local_block(doc, key: str):
    if isinstance(doc, list):
        for item in doc:
            if isinstance(item, dict) and key in item:
                return item[key]
    if isinstance(doc, dict):
        return doc.get(key)
    return None
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Checks (exports before anything moves; the library after publishing)
# -----------------------------------------------------------------------------

# HELPER FUNCTION | Is This a Complete PNG
# ------------------------------------------------------------
def na_png_problem(path: Path) -> str:
    try:
        size = path.stat().st_size
        with open(path, "rb") as fh:
            head = fh.read(24)
            fh.seek(max(0, size - 12))
            tail = fh.read(12)
    except OSError as e:
        return f"unreadable ({e})"
    if size < 1024 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return "not a PNG"
    if b"IEND" not in tail:
        return "incomplete (no end marker: the export may still be writing)"
    width, height = struct.unpack(">II", head[16:24])
    return "" if width and height else "zero size"
# ---------------------------------------------------------------

# HELPER FUNCTION | Is This a Complete glTF Binary (header, declared length, JSON chunk)
# ------------------------------------------------------------
def na_glb_problem(path: Path) -> str:
    try:
        size = path.stat().st_size
        with open(path, "rb") as fh:
            head = fh.read(20)
    except OSError as e:
        return f"unreadable ({e})"
    if len(head) < 20 or head[:4] != b"glTF":
        return "not a GLB"
    version, length = struct.unpack("<II", head[4:12])
    if version != 2:
        return f"glTF version {version} (2 expected)"
    if length != size:
        return f"truncated ({size} of {length} bytes)"
    if head[16:20] != b"JSON":
        return "no JSON chunk"
    return ""
# ---------------------------------------------------------------

# FUNCTION | Check What This Action Needs Was Exported
# ------------------------------------------------------------
def na_check_exports(args, rep: Na__Report) -> dict:
    root = Path(args.project_root)
    found = {"images": [], "edition": None, "glbs": [], "camera": None}
    wants = {"images": args.action in ("all", "images"), "glb": args.action in ("all", "glb"),
             "camera": args.action in ("all", "cameras")}
    problems, notes = [], []
    if wants["images"]:
        edition = na_latest_edition(root)
        if not edition:
            problems.append(f"no VisDpt__Whitecard__*Edition* folder in {NA__PUB__CONTENT_DELIVERED}")
        else:
            imgs = na_latest_images(edition)
            bad = [f"{p.name}: {na_png_problem(p)}" for p in imgs if na_png_problem(p)]
            if not imgs:
                problems.append(f"no IMG## ...__WhitecardImage__....png renders in {edition.name}")
            problems += bad
            found.update(images=imgs, edition=edition)
            notes.append(f"{len(imgs)} image(s) from {edition.name}")
    if wants["glb"]:
        glbs = na_fresh_glbs(root)
        if not glbs:
            problems.append(f"no .glb files in {NA__PUB__CONTENT_DELIVERED}/{NA__PUB__GLB_SYNC}")
        problems += [f"{p.name}: {na_glb_problem(p)}" for p in glbs if na_glb_problem(p)]
        names = [na_glb_library_name(p.name) for p in glbs]
        if len(set(n.lower() for n in names)) != len(names):
            problems.append("two GLBs end up with the same name after the __NaModel__ rename")
        found["glbs"] = glbs
        notes.append(f"{len(glbs)} GLB(s), {sum(p.stat().st_size for p in glbs) / 1e6:.1f} MB")
    if wants["camera"]:
        try:
            _path, doc = na_local_project_data(root)
            camera = na_local_block(doc, NA__PUB__KEY_CAMERA)
            if not isinstance(camera, dict):
                problems.append(f"no {NA__PUB__KEY_CAMERA} in {NA__PUB__LOCAL_DATA_DIR} (capture the cameras first)")
            else:
                found["camera"] = camera
                notes.append(f"{len(camera.get('scenes') or [])} camera scene(s)")
        except (OSError, ValueError) as e:
            problems.append(f"the local ProjectData in {NA__PUB__LOCAL_DATA_DIR} is unreadable: {e}")
    if problems:
        rep.step("Check Exported Files", False, "Nothing was published. " + "; ".join(problems[:8])
                 + (f" (+{len(problems) - 8} more)" if len(problems) > 8 else ""))
    else:
        rep.step("Check Exported Files", True, ", ".join(notes) + ".")
    return found
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Writing Files Into the Library
# -----------------------------------------------------------------------------

# HELPER FUNCTION | SHA-256 of a File
# ------------------------------------------------------------
def na_sha(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
# ---------------------------------------------------------------

# HELPER FUNCTION | Are Two Files Byte-for-Byte the Same
# ------------------------------------------------------------
def na_same_file(src: Path, dst: Path) -> bool:
    return dst.is_file() and dst.stat().st_size == src.stat().st_size and na_sha(dst) == na_sha(src)
# ---------------------------------------------------------------

# FUNCTION | Place One File (identical files are left alone, so nothing needless is pushed)
# ------------------------------------------------------------
def na_place(src: Path, dst: Path, dry: bool) -> str:
    """Returns 'same', 'added' or 'replaced'. A placed file takes the time of the copy, so the
    push sees it as newer than the server's copy (content lane: newer wins)."""
    if na_same_file(src, dst):
        return "same"
    state = "replaced" if dst.exists() else "added"
    if not dry:
        dst.parent.mkdir(parents=True, exist_ok=True)
        tmp = dst.with_name(dst.name + ".publishing.tmp")
        shutil.copyfile(src, tmp)
        os.replace(tmp, dst)
    return state
# ---------------------------------------------------------------

# FUNCTION | Remove This Pipeline's Old Files From a Bucket (others' files are never touched)
# ------------------------------------------------------------
def na_purge(bucket: Path, keep: set, is_ours, dry: bool) -> list:
    gone = []
    if not bucket.is_dir():
        return gone
    for f in sorted(bucket.iterdir()):
        if f.is_file() and is_ours(f.name) and f.name not in keep:
            gone.append(f.name)
            if not dry:
                f.unlink()
    return gone
# ---------------------------------------------------------------

# HELPER FUNCTION | Thumbnail File Names for a Source Image
# ------------------------------------------------------------
def na_thumb_names(image_name: str) -> tuple:
    stem = Path(image_name).stem
    return f"{stem}{NA__PUB__THUMB_TOKEN}.webp", f"{stem}{NA__PUB__THUMB_TOKEN}.jpg"
# ---------------------------------------------------------------

# FUNCTION | Make the 524p WebP + JPG (long edge 524 px, LANCZOS; WebP q82 m6; JPG q88)
# ------------------------------------------------------------
def na_make_thumbnails(src: Path, webp: Path, jpg: Path) -> None:
    from PIL import Image                                                    # <-- Checked at start-up (na_check_pillow)
    with Image.open(src) as img:
        img.load()
        w, h = img.size
        if max(w, h) > NA__PUB__THUMB_LONG_EDGE:
            k = NA__PUB__THUMB_LONG_EDGE / float(max(w, h))
            img = img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.Resampling.LANCZOS)
        for target in (webp, jpg):
            target.parent.mkdir(parents=True, exist_ok=True)
        tmp_webp, tmp_jpg = webp.with_name(webp.name + ".tmp"), jpg.with_name(jpg.name + ".tmp")
        img.save(tmp_webp, format="WEBP", quality=NA__PUB__THUMB_WEBP_QUALITY, method=6)
        (img.convert("RGB") if img.mode != "RGB" else img).save(
            tmp_jpg, format="JPEG", quality=NA__PUB__THUMB_JPG_QUALITY, optimize=True, progressive=True)
        os.replace(tmp_webp, webp)
        os.replace(tmp_jpg, jpg)
# ---------------------------------------------------------------

# FUNCTION | Publish Images and Their Thumbnails
# ------------------------------------------------------------
def na_publish_images(project: Path, images: list, rep: Na__Report, dry: bool) -> list:
    full, b524, bthumb, bscene = (project / b for b in (NA__PUB__BUCKET_FULL, NA__PUB__BUCKET_524P,
                                                         NA__PUB__BUCKET_THUMB, NA__PUB__BUCKET_SCENES))
    names = [p.name for p in images]
    counts = {"added": 0, "replaced": 0, "same": 0}
    made = scene_copies = 0
    for src in images:
        state = na_place(src, full / src.name, dry)
        counts[state] += 1
        webp_name, jpg_name = na_thumb_names(src.name)
        webp, jpg = bthumb / webp_name, b524 / jpg_name
        if state != "same" or not webp.is_file() or not jpg.is_file():
            made += 1
            if not dry:
                na_make_thumbnails(full / src.name, webp, jpg)
        if webp.is_file() and na_place(webp, bscene / webp_name, dry) != "same":
            scene_copies += 1                                                # <-- ValeVision 3D's Views bar reads its own bucket
    ours = lambda n: NA__PUB__IMAGE_MARKER in n                              # <-- Pipeline renders and their thumbnails only
    keep_thumbs = {na_thumb_names(n)[0] for n in names}
    purged = (na_purge(full, set(names), ours, dry) + na_purge(bthumb, keep_thumbs, ours, dry)
              + na_purge(b524, {na_thumb_names(n)[1] for n in names}, ours, dry)
              + na_purge(bscene, keep_thumbs, ours, dry))
    rep.extra["published"] += counts["added"] + counts["replaced"] + made * 2 + scene_copies
    rep.step("Publish Images", True,
             f"{len(names)} image(s): {counts['added']} new, {counts['replaced']} replaced, {counts['same']} unchanged"
             + (f"; {len(purged)} old file(s) removed from the library" if purged else "") + ".")
    rep.step("Generate Thumbnails", True,
             f"{made} image(s) re-thumbnailed at 524p (WebP + JPG; the WebP also in Content__AnimationScenes__Thumbnails)."
             if made else "All thumbnails already current.")
    return names
# ---------------------------------------------------------------

# HELPER FUNCTION | Today as DD-MMM-YYYY
# ------------------------------------------------------------
def na_today_stamp() -> str:
    now = datetime.now()
    return f"{now.day:02d}-{NA__PUB__MONTHS[now.month - 1]}-{now.year}"
# ---------------------------------------------------------------

# HELPER FUNCTION | The GLBs at the Top of a Folder (archives and sub-folders are not models)
# ------------------------------------------------------------
def na_glbs_in(folder: Path) -> list:
    if not folder.is_dir():
        return []
    return sorted((f for f in folder.iterdir() if f.is_file() and f.suffix.lower() == ".glb"), key=lambda p: p.name.lower())
# ---------------------------------------------------------------

# FUNCTION | Zip Files Into One Archive and Read It Back (nothing is deleted unless it reads back whole)
# ------------------------------------------------------------
def na_write_glb_archive(target: Path, files: list) -> None:
    tmp = target.with_name(target.name + ".writing.tmp")                     # <-- *.tmp never syncs
    try:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as zf:
            for f in files:
                zf.write(f, arcname=f.name)
        with zipfile.ZipFile(tmp) as zf:
            bad = zf.testzip()                                               # <-- Reads every entry, checks every CRC
            names = sorted(zf.namelist())
        if bad or names != sorted(f.name for f in files):
            raise OSError(f"the archive did not read back whole ({bad or 'its file list differs'})")
        os.replace(tmp, target)
    finally:
        if tmp.exists():
            tmp.unlink()
# ---------------------------------------------------------------

# FUNCTION | Archive the Previous GLB Set (00__Archive keeps ONE zip: the set before this sync)
# ------------------------------------------------------------
def na_archive_previous_glbs(bucket: Path, previous: list, library_id: str, rep: Na__Report, dry: bool) -> None:
    """1. make 00__Archive, 2. zip the previous set into it, 3. remove the older archive zip.
    The caller then empties the bucket of old GLBs and writes the new set."""
    archive_dir = bucket / NA__PUB__GLB_ARCHIVE_DIR
    zip_name = f"{library_id}{NA__PUB__GLB_ARCHIVE_TOKEN}{na_today_stamp()}__.zip"
    zips = sorted(f for f in archive_dir.iterdir() if f.is_file() and f.suffix.lower() == ".zip") if archive_dir.is_dir() else []
    older = [f for f in zips if f.name != zip_name]
    mb = sum(p.stat().st_size for p in previous) / 1e6
    if not dry:
        archive_dir.mkdir(parents=True, exist_ok=True)
        na_write_glb_archive(archive_dir / zip_name, previous)
        for f in older:
            f.unlink()
    rep.extra["archived"] = len(previous)
    same_day = len(older) < len(zips)
    rep.step("Archive Previous GLBs", True,
             f"{'Would zip' if dry else 'Zipped'} the previous {len(previous)} model(s), {mb:.1f} MB, into "
             f"{NA__PUB__GLB_ARCHIVE_DIR}/{zip_name}"
             + (" (replacing today's earlier archive)" if same_day else "")
             + (f"; the older archive {', '.join(f.name for f in older)} {'would be' if dry else 'was'} removed" if older else "")
             + ".")
# ---------------------------------------------------------------

# FUNCTION | Publish the GLB Models (the bucket ends up holding exactly this sync's set)
# ------------------------------------------------------------
def na_publish_glbs(project: Path, glbs: list, rep: Na__Report, dry: bool, library_id: str) -> list:
    bucket = project / NA__PUB__BUCKET_GLB
    pairs = [(src, na_glb_library_name(src.name)) for src in glbs]
    names = [n for _, n in pairs]
    previous = na_glbs_in(bucket)
    unchanged = {p.name for p in previous} == set(names) and all(na_same_file(src, bucket / n) for src, n in pairs)
    if not previous:
        rep.step("Archive Previous GLBs", True, "No previous models in the library: nothing to archive.", status="skip")
    elif unchanged:
        rep.step("Archive Previous GLBs", True, "The models are the same as the last sync: the archive is kept as it is.",
                 status="skip")                                              # <-- Re-zipping the same set would lose the real previous one
    else:
        na_archive_previous_glbs(bucket, previous, library_id, rep, dry)
    purged = na_purge(bucket, set(names), lambda n: n.lower().endswith(".glb"), dry)
    counts = {"added": 0, "replaced": 0, "same": 0}
    for src, name in pairs:
        counts[na_place(src, bucket / name, dry)] += 1
    rep.extra["published"] += counts["added"] + counts["replaced"]
    rep.step("Publish GLB Models", True,
             f"{len(names)} model(s): {counts['added']} new, {counts['replaced']} replaced, {counts['same']} unchanged"
             + (f"; {len(purged)} old model(s) removed from the library" if purged else "") + ".")
    return sorted(names)
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | The Project Record (only the keys this sync owns)
# -----------------------------------------------------------------------------

# HELPER FUNCTION | IMG## Slot of a File Name
# ------------------------------------------------------------
def na_slot(name: str):
    m = NA__PUB__SLOT_PATTERN.match(name or "")
    return m.group(1).upper() if m else None
# ---------------------------------------------------------------

# HELPER FUNCTION | A Scene's Slot From the Camera Data (su_scene_N, or Order N)
# ------------------------------------------------------------
def na_scene_slot_from_cameras(record: dict, scene: dict):
    cams = (record.get(NA__PUB__KEY_CAMERA) or {}).get("scenes") if isinstance(record.get(NA__PUB__KEY_CAMERA), dict) else None
    if not isinstance(cams, list) or not cams:
        return None
    m = re.match(r"^su_scene_(\d+)$", str(scene.get(NA__PUB__SCENE_ID) or ""), re.IGNORECASE)
    order = scene.get(NA__PUB__SCENE_ORDER)
    index = int(m.group(1)) - 1 if m else (order - 1 if isinstance(order, int) and order > 0 else None)
    if index is None or not 0 <= index < len(cams) or not isinstance(cams[index], dict):
        return None
    return na_slot(str(cams[index].get("scene_name") or ""))
# ---------------------------------------------------------------

# FUNCTION | Re-point the ValeVision 3D Views-Bar Thumbnails at the Current Images
# ------------------------------------------------------------
def na_repoint_scene_thumbnails(record: dict, images: list) -> tuple:
    """Only values that start with an IMG## slot are changed; hand-authored paths are kept."""
    block = record.get(NA__PUB__SCENES_BLOCK)
    scenes = block.get(NA__PUB__SCENES_ARRAY) if isinstance(block, dict) else None
    if not isinstance(scenes, list):
        return 0, []
    by_slot = {}
    for name in images:
        by_slot.setdefault(na_slot(name), name)
    moved, orphaned = 0, []
    for scene in scenes:
        if not isinstance(scene, dict):
            continue
        stored = str(scene.get(NA__PUB__SCENE_THUMB) or "").strip()
        if stored and not NA__PUB__SLOT_PATTERN.match(stored):
            continue
        slot = na_slot(stored) if stored else na_scene_slot_from_cameras(record, scene)
        if not slot:
            continue
        image = by_slot.get(slot)
        if not image:
            orphaned.append(str(scene.get(NA__PUB__SCENE_NAME) or scene.get(NA__PUB__SCENE_ID) or "?"))
            continue
        wanted = na_thumb_names(image)[0]
        if stored != wanted:
            scene[NA__PUB__SCENE_THUMB] = wanted
            moved += 1
    return moved, orphaned
# ---------------------------------------------------------------

# FUNCTION | Rebuild the Image Lists (pipeline renders + any hand-added images still present)
# ------------------------------------------------------------
def na_set_image_lists(record: dict, project: Path, images: list) -> list:
    full = project / NA__PUB__BUCKET_FULL
    kept = [n for n in (record.get("images") or []) if isinstance(n, str) and NA__PUB__IMAGE_MARKER not in n
            and (full / n).is_file()]                                        # <-- e.g. photomatch images added by hand
    listed = sorted(set(images) | set(kept), key=str.lower)
    record["images"] = listed
    record["allImages"] = list(listed)
    record["displayImages"] = [n for n in listed if not NA__PUB__ART_PATTERN.match(n)]
    first = next((n for n in images if NA__PUB__IMG01_PATTERN.match(n)), None)
    if first:
        record["thumbnailImage"] = na_thumb_names(first)[0]
    return kept
# ---------------------------------------------------------------

# FUNCTION | A New Record (first sync of a project the library does not have yet)
# ------------------------------------------------------------
def na_new_record(args) -> dict:
    folder = Path(args.project_root).name
    m = NA__PUB__TYPE_PATTERN.match(folder)
    project_type = m.group(1) if m else "Whitecard"
    code, _, name = args.library_id.partition("__")
    code = code.split("-")[-1]
    meta = {}
    try:
        _, doc = na_local_project_data(Path(args.project_root))
        meta = na_local_block(doc, "Project__MetaData") or {}
    except (OSError, ValueError):
        pass
    clean = lambda v: v.strip() if isinstance(v, str) and v.strip() and v.strip().upper() not in NA__PUB__META_PLACEHOLDERS else None
    record = {
        "projectName"   : name or args.library_id,                           # <-- As the retired scaffold: all after the code
        "projectCode"   : code,
        "productionData": {"input": NA__PUB__NOT_YET_REVIEWED,
                           "conceptArtist": clean(meta.get("Project__ConceptArtist")) or NA__PUB__NOT_YET_REVIEWED,
                           "designer": clean(meta.get("Project__Designer")) or NA__PUB__NOT_YET_REVIEWED,
                           "additionalNotes": NA__PUB__DEFAULT_NOTES},
        "scheduleData"  : {"dateReceived": NA__PUB__NOT_YET_REVIEWED,
                           "dateFulfilled": datetime.now().strftime("%d-%b-%Y"),
                           "timeTaken": NA__PUB__NOT_YET_REVIEWED},
        "images"        : [],
        "ProjectType"   : project_type,
    }
    if project_type == "MaxModel":
        record["RenderEngine__Config"] = {"RenderEngine__Active": "MaxEngine"}  # <-- ValeVision 3D boots MaxEngine
    record[NA__PUB__KEY_MODELS] = []
    record["valeVision_Camera__DefaultPosition"] = json.loads(json.dumps(NA__PUB__CAMERA_DEFAULTS))
    return record
# ---------------------------------------------------------------

# FUNCTION | Write the Record in the Library's Style (4-space JSON, own newline state, atomic)
# ------------------------------------------------------------
def na_write_record(path: Path, record: dict, newline: bool) -> None:
    """The project-data lane is newer-wins. The file just fetched carries the SERVER's time, so if
    that clock runs ahead of this PC the merged record could look older than the copy it was merged
    into and never be pushed. The new file is therefore always given a later time than that copy."""
    prior = path.stat().st_mtime if path.is_file() else 0
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(record, indent=4, ensure_ascii=False) + ("\n" if newline else ""),
                   encoding="utf-8", newline="\n")
    os.replace(tmp, path)
    if path.stat().st_mtime <= prior:
        os.utime(path, (prior + 1, prior + 1))
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Server Manager Engine (one project folder only)
# -----------------------------------------------------------------------------

# FUNCTION | Run the Engine for This Project (collect or push, --scope, --yes)
# ------------------------------------------------------------
def na_engine(args, cmd: str, scope: str, prune: tuple = ()) -> dict:
    """Shells out to the Vale Virtual Server Manager's sync engine, which owns the server
    connection (one ssh session per job, the machine-wide lock, backups, undo).
    prune: content folders the push makes exact copies of the PC's (engine 0.6.2 or later)."""
    folder = Path(args.report_file).resolve().parent if args.report_file else Path(tempfile.gettempdir())
    report = folder / f"Na__ValeVisionCloudSync__Engine__{cmd}__{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}.json"
    env = dict(os.environ, VSM_CONFIG=str(Path(args.sync_map).resolve()), PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    argv = [sys.executable, str(args.engine), cmd, args.mapping, "--scope", scope, "--yes", "--report-file", str(report)]
    for p in prune:
        argv += ["--prune", p]
    print(f"  ...  engine: {cmd} {args.mapping} --scope {scope}" + "".join(f" --prune {p}" for p in prune), flush=True)
    try:
        p = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
                           timeout=NA__PUB__ENGINE_TIMEOUT_S, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"the engine did not finish within {NA__PUB__ENGINE_TIMEOUT_S // 60} min"}
    except OSError as e:
        return {"ok": False, "error": f"could not start the engine: {e}"}
    print("\n".join("       | " + line for line in (p.stdout + p.stderr).strip().splitlines()[-40:]), flush=True)
    try:
        out = json.loads(report.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        tail = " | ".join((p.stderr or p.stdout).strip().splitlines()[-3:])
        if "unrecognized arguments: --prune" in tail:
            return {"ok": False, "error": "the Vale Virtual Server Manager engine is older than 0.6.2 (no --prune): "
                                          "update it, then run the sync again"}
        return {"ok": False, "error": f"engine exit {p.returncode}, no report: {tail or 'no output'}"}
    finally:
        try:
            report.unlink()
        except OSError:
            pass
    out["exit"] = p.returncode
    return out
# ---------------------------------------------------------------

# HELPER FUNCTION | Counts of One Engine Plan
# ------------------------------------------------------------
def na_plan_counts(out: dict, mapping: str) -> dict:
    return ((out.get("plans") or {}).get(mapping) or {}).get("counts") or {}
# ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Sync
# -----------------------------------------------------------------------------

# FUNCTION | Check Pillow Before Anything Moves (thumbnails need it)
# ------------------------------------------------------------
def na_check_pillow() -> str:
    try:
        import PIL                                                           # noqa: F401
        from PIL import Image                                                # noqa: F401
        return ""
    except ImportError:
        return f"Pillow is not installed for {sys.executable}: run  \"{sys.executable}\" -m pip install pillow"
# ---------------------------------------------------------------

# FUNCTION | One Sync, Start to Finish
# ------------------------------------------------------------
def na_sync(args) -> dict:
    rep = Na__Report(args)
    dry = bool(args.dry_run)

    # 1. RESOLVE | The library folder this model publishes into
    try:
        library = na_library_root(Path(args.sync_map), args.mapping)
    except (OSError, ValueError, KeyError) as e:
        rep.step("Resolve Library Project", False, f"Cannot read the Server Manager sync map {args.sync_map}: {e}")
        return rep.finish()
    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$", args.library_id or "") or ".." in args.library_id:
        rep.step("Resolve Library Project", False, f"'{args.library_id}' is not a valid library project id.")
        return rep.finish()
    hits = na_find_library_folder(library, args.library_id)
    if len(hits) > 1:
        rep.step("Resolve Library Project", False, f"{args.library_id} exists in more than one year folder ("
                 + ", ".join(h.parent.name for h in hits) + "). Set the Library Project in Settings.")
        return rep.finish()
    is_new = not hits
    project = hits[0] if hits else library / f"{NA__PUB__YEAR_PREFIX}{args.year}" / args.library_id
    rel = project.relative_to(library).as_posix()
    rep.extra.update(library_rel=rel, library_path=str(project), first_sync=is_new)
    if is_new and not args.create_new:
        rep.step("Resolve Library Project", False, f"{rel} is not in the Project Library. Confirm the new project "
                 "in the dialog, or set the Library Project in Settings if it belongs to an existing one.")
        return rep.finish()
    rep.step("Resolve Library Project", True, f"{rel} ({'new project, created by this sync' if is_new else 'existing'}).")

    # 2. CHECK | Exports first: a bad export stops the sync before anything moves
    if args.action in ("all", "images"):
        problem = na_check_pillow()
        if problem:
            rep.step("Check Exported Files", False, "Nothing was published. " + problem)
            return rep.finish()
    found = na_check_exports(args, rep)
    if rep.failed:
        return rep.finish()

    # 3. FETCH | The server's newer copy of this project, before the record is touched
    record_path = project / f"ProjectData__{args.library_id}__.json"
    if args.local_only or dry:
        rep.step("Fetch Server Copy", True, "Skipped (" + ("dry run" if dry else "server sync is off in the AppConfig")
                 + ").", status="skip")
    elif is_new:
        rep.step("Fetch Server Copy", True, "New project: nothing on the server yet.", status="skip")
    else:
        out = na_engine(args, "collect", rel)
        if not out.get("ok"):
            rep.step("Fetch Server Copy", False, "Nothing was published: the server's copy could not be checked first, "
                     f"so the record cannot be updated safely. {out.get('error')}")
            return rep.finish()
        got = (out.get("result") or {}).get("received", 0)
        skipped = (out.get("result") or {}).get("skipped_local") or []
        rep.step("Fetch Server Copy", True, (f"Brought down {got} file(s) newer on the server (web edits are kept)."
                                             if got else "The library copy already matches the server.")
                 + (f" {len(skipped)} skipped." if skipped else ""))

    # 4. PUBLISH | Files into the buckets, then the record keys
    if is_new and not dry:
        for d in NA__PUB__NEW_PROJECT_DIRS:
            (project / d).mkdir(parents=True, exist_ok=True)
    try:
        images = na_publish_images(project, found["images"], rep, dry) if found["images"] else None
        models = na_publish_glbs(project, found["glbs"], rep, dry, args.library_id) if found["glbs"] else None
    except Exception as e:                                                   # <-- Disk full, locked file, bad image ...
        rep.step("Publish Files", False, f"{type(e).__name__}: {e}. The library may be part-updated; nothing was pushed.")
        return rep.finish()

    try:
        raw = record_path.read_text(encoding="utf-8") if record_path.is_file() else None
        record = json.loads(raw) if raw is not None else na_new_record(args)
        if not isinstance(record, dict):
            raise ValueError("the record is not a JSON object")
    except (OSError, ValueError) as e:
        rep.step("Update Project Record", False, f"{record_path.name} unreadable: {e}. Nothing was pushed.")
        return rep.finish()
    before = json.dumps(record, ensure_ascii=False, sort_keys=False)
    notes = []
    if images is not None:
        kept = na_set_image_lists(record, project, images)
        moved, orphaned = na_repoint_scene_thumbnails(record, images)
        notes.append(f"{len(images)} image(s)" + (f" + {len(kept)} added by hand" if kept else ""))
        if moved or orphaned:
            notes.append(f"{moved} Views-bar thumbnail(s) re-pointed"
                         + (f"; no image this time for: {', '.join(orphaned)}" if orphaned else ""))
    if models is not None:
        record[NA__PUB__KEY_MODELS] = models
        notes.append(f"{len(models)} model name(s)")
    if found["camera"] is not None:
        record[NA__PUB__KEY_CAMERA] = found["camera"]
        notes.append("camera data")
    changed = json.dumps(record, ensure_ascii=False, sort_keys=False) != before or raw is None
    if changed and not dry:
        na_write_record(record_path, record, raw.endswith("\n") if raw is not None else True)
    rep.step("Update Project Record", True, (f"{record_path.name}: " if changed else "Unchanged: ")
             + ", ".join(notes) + ("." if notes else "nothing to set."))
    if changed:
        rep.extra["published"] += 1

    # 5. VERIFY | Every name the record lists is in its bucket
    if not dry:
        missing = []
        for name in (record.get("images") or []) if images is not None else []:
            wanted = [(NA__PUB__BUCKET_FULL, name)]
            if NA__PUB__IMAGE_MARKER in name:
                webp, jpg = na_thumb_names(name)
                wanted += [(NA__PUB__BUCKET_THUMB, webp), (NA__PUB__BUCKET_524P, jpg), (NA__PUB__BUCKET_SCENES, webp)]
            missing += [f"{b}/{n}" for b, n in wanted if not (project / b / n).is_file()]
        for name in (record.get(NA__PUB__KEY_MODELS) or []) if models is not None else []:
            if not (project / NA__PUB__BUCKET_GLB / name).is_file():
                missing.append(f"{NA__PUB__BUCKET_GLB}/{name}")
        if models is not None:                                               # <-- The bucket holds this sync's set and nothing else
            listed = set(record.get(NA__PUB__KEY_MODELS) or [])
            missing += [f"{NA__PUB__BUCKET_GLB}/{p.name} is not a current model"
                        for p in na_glbs_in(project / NA__PUB__BUCKET_GLB) if p.name not in listed]
        try:
            json.loads(record_path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            missing.append(f"{record_path.name} does not read back ({e})")
        if missing:
            rep.step("Verify Library", False, "Not pushed: " + "; ".join(missing[:6])
                     + (f" (+{len(missing) - 6} more)" if len(missing) > 6 else ""))
            return rep.finish()
        rep.step("Verify Library", True, "Every file the record names is in the library.")

    # 6. PUSH | This project folder only
    if args.local_only or dry:
        rep.step("Push To Server", True, "Not pushed (" + ("dry run" if dry else "server sync is off in the AppConfig")
                 + "). Push it later from the Vale Virtual Server Manager.", status="skip")
        return rep.finish("Dry run complete: nothing was written." if dry else "Published to the Project Library (not pushed).")
    prune = (f"{rel}/{NA__PUB__BUCKET_GLB}",) if models is not None else ()  # <-- The server's GLB bucket ends up the PC's set
    out = na_engine(args, "push", rel, prune)
    counts = na_plan_counts(out, args.mapping)
    result = out.get("result") or {}
    if not out.get("ok"):
        rep.step("Push To Server", False, f"Not pushed: {out.get('error')}. The library on this PC is up to date; "
                 "run the sync again, or push 'projects' from the Vale Virtual Server Manager.")
        return rep.finish()
    pushed = sum(len(p.get("added", [])) + len(p.get("replaced", [])) for p in result.get("plans", []))
    removed = sum(len(p.get("deleted", [])) for p in result.get("plans", []))
    rep.extra["pushed"] = pushed
    rep.extra["server_removed"] = removed
    mb = ((out.get("plans") or {}).get(args.mapping) or {}).get("push_bytes", 0) / 1e6
    notes = []
    if removed:
        notes.append(f"{removed} superseded file(s) removed from the server's GLB folder (kept in the server backup)")
    if counts.get("content_server_newer"):
        notes.append(f"{counts['content_server_newer']} file(s) newer on the server were left as they are")
    if counts.get("shared_collect"):
        rep.step("Push To Server", False, "The server's record changed while this sync ran, so this sync's record "
                 "was not sent. Run the sync again.")
        return rep.finish()
    rep.step("Push To Server", True, (f"Pushed {pushed} file(s), {mb:.1f} MB, to app.valegardenhouses.com"
                                      if pushed else "No new files to push" if removed
                                      else "Nothing to push: the server already matches")
             + (" (" + "; ".join(notes) + ")" if notes else "") + ".")
    return rep.finish(f"Synced {args.library_id} to app.valegardenhouses.com.")
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
    ap = argparse.ArgumentParser(description="ValeVision Cloud Sync: publish to the Project Library, push one project")
    ap.add_argument("--project-root", required=True, help="the SketchUp project folder (C:/01__ValeProjects/...)")
    ap.add_argument("--library-id", required=True, help="the library folder name, e.g. 64135__Washington")
    ap.add_argument("--year", default=str(datetime.now().year), help="year folder for a NEW library project")
    ap.add_argument("--action", choices=NA__PUB__ACTIONS, required=True)
    ap.add_argument("--sync-map", required=True, help="the Server Manager's VirtualServerManager__SyncMap__.json")
    ap.add_argument("--engine", required=True, help="the Server Manager's VirtualServerManager__SyncEngine__.py")
    ap.add_argument("--mapping", default="projects")
    ap.add_argument("--create-new", action="store_true", help="the user confirmed a new library project")
    ap.add_argument("--local-only", action="store_true", help="publish into the library, do not fetch or push")
    ap.add_argument("--dry-run", action="store_true", help="check and report only; write nothing")
    ap.add_argument("--report-file", default="")
    ap.add_argument("--json", action="store_true", help="also print the report as the last stdout line")
    args = ap.parse_args()
    print(f"ValeVision Cloud Sync publisher {NA__PUB__VERSION}: {args.action} {args.library_id}", flush=True)
    try:
        report = na_sync(args)
    except Exception as e:                                                   # <-- Never leave the dialog without a report
        import traceback
        traceback.print_exc()
        report = {"success": False, "message": f"Publisher error: {type(e).__name__}: {e}", "steps": [
            {"label": "Publisher", "success": False, "message": f"{type(e).__name__}: {e}"}]}
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
