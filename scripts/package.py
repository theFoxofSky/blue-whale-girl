"""Package only a verified app and the self-contained source project."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import zipfile

from report import fingerprints
from importlib.util import module_from_spec, spec_from_file_location


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == '__main__':
    project = Path(__file__).resolve().parent.parent
    output = project / '.build/regression'
    regression = json.loads((output / 'results.json').read_text())
    portable = json.loads((output / 'portable.json').read_text())
    inputs = fingerprints(project)
    if not (regression['ok'] and regression['mode'] == 'full'
            and regression['inputs'] == portable['inputs'] == inputs and portable['ok']):
        raise SystemExit('Run full regression and verify-portable.py on the current source first.')
    app = output / '蓝色大肥鱼.app'
    if digest(app / 'Contents/MacOS/BlueWhalePet') != regression['binary_sha256']:
        raise SystemExit('The tested executable changed.')
    fixture = json.loads((project / 'Tests/Fixtures/high-resolution-sha256.json').read_text())
    fixture.update(json.loads((project / 'Tests/Fixtures/dizzy-sha256.json').read_text()))
    for name, expected in fixture.items():
        if digest(app / 'Contents/Resources/HighResolution' / name) != expected:
            raise SystemExit('Packaged artwork changed: ' + name)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    version = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    dist = project / 'dist'
    dist.mkdir(exist_ok=True)
    app_zip = dist / ('蓝色大肥鱼-Mac-v' + version + '.zip')
    source_zip = dist / ('蓝色大肥鱼-Mac-源码-v' + version + '.zip')
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(app), str(app_zip)], check=True)
    spec = spec_from_file_location('portable_project', project / 'scripts/verify-portable.py')
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    prefix = '蓝色大肥鱼-Mac-源码-v' + version
    with zipfile.ZipFile(source_zip, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in module.PROJECT_FILES:
            source = project / name
            files = sorted(source.rglob('*')) if source.is_dir() else [source]
            for file in files:
                if file.is_file() and '__pycache__' not in file.parts and file.name != '.DS_Store':
                    archive.write(file, str(Path(prefix) / file.relative_to(project)))
    for archive in [app_zip, source_zip]:
        with zipfile.ZipFile(archive) as check:
            if check.testzip() is not None:
                raise SystemExit('ZIP integrity check failed')
    checksums = {p.name: digest(p) for p in [app_zip, source_zip]}
    (dist / 'SHA256SUMS').write_text(''.join(sha + '  ' + name + '\n' for name, sha in checksums.items()))
    print(json.dumps({'version': version, 'packages': checksums, 'original_hd_frames': 103,
                      'total_hd_frames': 104}, ensure_ascii=False, indent=2))
