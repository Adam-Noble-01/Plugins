"""SketchUp R2 adapter. Reuses the portal's credentials and key conventions."""
import contextlib
import importlib.util
import json
import re
import sys
from datetime import datetime
from pathlib import Path


def project_prefix(request, sync):
    year, project = request['year'], request['project']
    if not re.fullmatch(r'\d{2}-Projects', year):
        raise ValueError('Invalid project year folder')
    if not re.fullmatch(r'[A-Z]{2}\d{2}__[A-Za-z0-9_ -]+', project):
        raise ValueError('Invalid project folder')
    return f'{sync.R2_BASE_PREFIX}/{year}/{project}/{sync.TRUEVISION_CONTENT_FOLDER}/'


def list_glbs(client, bucket, prefix):
    objects = []
    for page in client.get_paginator('list_objects_v2').paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get('Contents', []):
            key = obj['Key']
            if key.startswith(prefix) and key.lower().endswith('.glb'):
                objects.append(dict(key=key, size=obj['Size'], etag=obj['ETag'],
                                    modified=obj['LastModified'].isoformat()))
    return sorted(objects, key=lambda obj: obj['key'])


def manage(request, sync, client, bucket):
    prefix = project_prefix(request, sync)
    if request['action'] == 'fetch':
        folders = {}
        for obj in list_glbs(client, bucket, prefix):
            relative = obj['key'][len(prefix):]
            if '/' not in relative:
                continue
            folder = relative.split('/')[0]
            if folder.startswith('DesignPhase'):
                folders.setdefault(folder, []).append(obj)
        return dict(success=True, bucket=bucket, prefix=prefix, folders=folders,
                    message='R2 inventory fetched. Select a cloud folder to review its GLBs.')
    folder = request['folder']
    if not re.fullmatch(r'DesignPhase[A-Za-z0-9_ -]+', folder):
        raise ValueError('Select one design phase/scheme folder')
    prefix += folder + '/'
    current = list_glbs(client, bucket, prefix)
    if request.get('bucket') != bucket or request.get('prefix') != prefix:
        raise ValueError('The bucket or folder changed. Fetch R2 again.')
    expected = request['objects']
    if not expected or current != expected:
        raise ValueError('R2 contents changed or the folder is empty. Fetch and review again.')
    deleted, errors = [], []
    # Delete only the reviewed keys; never issue a project-wide recursive delete.
    for obj in expected:
        try:
            # Recheck each object immediately before deleting it. HEAD reports
            # Last-Modified as an HTTP date, whole seconds only, while the listing
            # carries milliseconds - an exact match failed every object (131 of
            # 131 on 20-Sep-2026). Compare to the second; ETag and size carry
            # the content check.
            head = client.head_object(Bucket=bucket, Key=obj['key'])
            drift = abs((head['LastModified'] - datetime.fromisoformat(obj['modified'])).total_seconds())
            if head['ETag'] != obj['etag'] or head['ContentLength'] != obj['size'] or drift >= 1:
                raise ValueError('Object changed since preview')
            client.delete_object(Bucket=bucket, Key=obj['key'])
            deleted.append(obj['key'])
        except Exception as error:
            errors.append(f"{obj['key']}: {error}")
    remaining = list_glbs(client, bucket, prefix)
    return dict(success=not errors and not remaining, deleted=deleted, errors=errors,
                remaining=remaining, message=f'Deleted {len(deleted)} GLBs; {len(remaining)} remain; {len(errors)} errors.',
                prefix=prefix, bucket=bucket)


def main(request):
    script = Path(request['sync_script'])
    sys.path.insert(0, str(script.parent))
    spec = importlib.util.spec_from_file_location('truevision_existing_sync', script)
    sync = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sync)
    if request['action'] == 'sync':
        code = sync.run_r2_sync(target_project=request['project'],
                               dry_run_only=request['dry_run'], auto_confirm_upload=True,
                               sync_truevision=True, sync_planvision=False)
        return dict(success=code == 0, message='R2 sync finished.', exit_code=code)
    success, credentials = sync.load_r2_credentials()
    if not success:
        raise RuntimeError('R2 credentials unavailable in the existing pipeline configuration')
    client = sync.create_r2_client(credentials)
    if client is None:
        raise RuntimeError('Could not create R2 client')
    return manage(request, sync, client, credentials['bucket_name'])


if __name__ == '__main__':
    request_path, report_path = map(Path, sys.argv[1:3])
    try:
        report = main(json.loads(request_path.read_text(encoding='utf-8-sig')))
    except Exception as error:
        report = dict(success=False, message=str(error))
    report_path.write_text(json.dumps(report), encoding='utf-8')
    raise SystemExit(0 if report['success'] else 1)
