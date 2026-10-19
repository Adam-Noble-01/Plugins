"""
=============================================================================
TRUEVISION3D - GLB BUILDER UTILITY - POINT CLOUD WEBP TILES
=============================================================================

FILE       : Na__TrueVision__GlbBuilder__PointCloud__WebpTiles__.py
AUTHOR     : Adam Noble - Noble Architecture
PURPOSE    : Turns the point cloud viewer's rendered tiles (stored PNG, RGBA,
             transparent where there are no points) into the WebP files
             TrueVision loads, and builds one preview image per scene.
CREATED    : 19-Oct-2026

USAGE      : python Na__TrueVision__GlbBuilder__PointCloud__WebpTiles__.py <job.json> <result.json>

JOB        : { "quality": 90, "method": 4, "previewMaxPx": 2048,
               "scenes": [ { "sceneId", "widthPx", "heightPx", "tileSizePx", "previewFile",
                             "tiles": [ { "row", "col", "x", "y", "w", "h", "png", "webp", "empty" } ] } ] }
RESULT     : { "success", "message", "scenes": [ { "sceneId", "tiles": [ {..., "bytes"} ],
               "preview": { "file", "widthPx", "heightPx", "factor", "bytes" } } ], "seconds" }

RULES      : Every written file is checked by reopening it at its stated size.
             A tile with no points is never written (TrueVision draws nothing
             there). The preview is the whole image reduced by a power of two,
             with alpha premultiplied first so edges never darken. Nothing is
             written outside the paths the job names.
=============================================================================
"""

import json
import math
import os
import sys
import time

from PIL import Image


def na_progress(path, done, total, text):
    """Write a small progress file the plugin may read; never fatal."""
    if not path:
        return
    try:
        with open(path + '.writing', 'w', encoding='utf-8') as handle:
            json.dump({'done': done, 'total': total, 'text': text}, handle)
        os.replace(path + '.writing', path)
    except OSError:
        pass


def na_save_webp(image, path, quality, method):
    image.save(path, 'WEBP', quality=quality, method=method, alpha_quality=100)
    with Image.open(path) as check:
        if check.size != image.size:
            raise RuntimeError(f'{os.path.basename(path)} reopened at {check.size}, expected {image.size}')
    return os.path.getsize(path)


def na_preview_factor(width, height, limit):
    """Smallest power of two that brings the longest side within the limit."""
    factor = 1
    while max(math.ceil(width / factor), math.ceil(height / factor)) > limit:
        factor *= 2
    return factor


def na_convert_scene(scene, quality, method, preview_limit, progress, counter):
    tiles_out = []
    tile_size = int(scene['tileSizePx'])
    factor = na_preview_factor(scene['widthPx'], scene['heightPx'], preview_limit)
    while factor > 1 and tile_size % factor:
        factor //= 2                                        # tiles start on multiples of the factor, so each lands exactly
    if max(math.ceil(scene['widthPx'] / factor), math.ceil(scene['heightPx'] / factor)) > 16383:
        raise RuntimeError('The preview would exceed the WebP size limit. Use a power of two tile size.')
    preview = Image.new('RGBA', (math.ceil(scene['widthPx'] / factor), math.ceil(scene['heightPx'] / factor)), (0, 0, 0, 0))
    for tile in scene['tiles']:
        counter['done'] += 1
        entry = dict(tile)
        if tile.get('empty'):
            entry.update(file=None, bytes=0)
            tiles_out.append(entry)
            continue
        with Image.open(tile['png']) as raw:
            image = raw.convert('RGBA')
        if image.size != (tile['w'], tile['h']):
            raise RuntimeError(f"{os.path.basename(tile['png'])} is {image.size}, expected {(tile['w'], tile['h'])}")
        entry['bytes'] = na_save_webp(image, tile['webp'], quality, method)
        entry['file'] = os.path.basename(tile['webp'])
        small = image if factor == 1 else image.convert('RGBa').reduce(factor).convert('RGBA')
        preview.paste(small, (tile['x'] // factor, tile['y'] // factor))
        tiles_out.append(entry)
        na_progress(progress, counter['done'], counter['total'], f"{scene['sceneId']} tile {tile['row']},{tile['col']}")
    # An image that is one tile at full size IS its own preview: no second copy.
    if factor == 1 and len(tiles_out) == 1 and tiles_out[0].get('file'):
        only = tiles_out[0]
        return {'sceneId': scene['sceneId'], 'tiles': tiles_out,
                'preview': {'file': only['file'], 'widthPx': only['w'], 'heightPx': only['h'], 'factor': 1, 'bytes': 0}}
    preview_bytes = na_save_webp(preview, scene['previewFile'], quality, method)
    return {
        'sceneId': scene['sceneId'],
        'tiles': tiles_out,
        'preview': {'file': os.path.basename(scene['previewFile']), 'widthPx': preview.size[0],
                    'heightPx': preview.size[1], 'factor': factor, 'bytes': preview_bytes},
    }


def main(job_path, result_path):
    started = time.time()
    with open(job_path, 'r', encoding='utf-8-sig') as handle:
        job = json.load(handle)
    quality = int(job.get('quality', 90))
    method = int(job.get('method', 4))
    preview_limit = int(job.get('previewMaxPx', 2048))
    progress = job.get('progressFile')
    counter = {'done': 0, 'total': sum(len(scene['tiles']) for scene in job['scenes'])}
    scenes = []
    for scene in job['scenes']:
        scenes.append(na_convert_scene(scene, quality, method, preview_limit, progress, counter))
    written = sum(1 for scene in scenes for tile in scene['tiles'] if tile.get('file'))
    return {
        'success': True,
        'message': f'{written} WebP tile(s) and {len(scenes)} preview(s) written.',
        'scenes': scenes,
        'seconds': round(time.time() - started, 2),
    }


if __name__ == '__main__':
    job_file, result_file = sys.argv[1], sys.argv[2]
    try:
        report = main(job_file, result_file)
    except Exception as error:                                   # reported, never raised past here
        report = {'success': False, 'message': f'{type(error).__name__}: {error}'}
    with open(result_file + '.writing', 'w', encoding='utf-8') as out:
        json.dump(report, out)
    os.replace(result_file + '.writing', result_file)
    raise SystemExit(0 if report['success'] else 1)
