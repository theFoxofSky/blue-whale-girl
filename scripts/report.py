"""Summarize actual regression outputs and record the exact tested inputs."""
import datetime
import hashlib
import json
from pathlib import Path
import sys


def input_files(project):
    files = []
    for name in ['Sources', 'Tests', 'scripts', 'Assets', 'HighResolution']:
        files.extend(p for p in (project / name).rglob('*')
                     if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc')
    files.extend(project / name for name in ['build.sh', 'Info.plist', 'PetIcon.icns'])
    return sorted(files)


def fingerprints(project):
    return {str(p.relative_to(project)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in input_files(project)}


if __name__ == '__main__':
    project, output = (Path(p).resolve() for p in sys.argv[1:3])
    mode = sys.argv[3]
    names = ['assets.json', 'model.json'] if mode == '--headless' else [
        'assets.json', 'self-test.json', 'native/ui-smoke-test.json', 'gaze.json']
    reports = {name: json.loads((output / name).read_text()) for name in names}
    if not all(report['ok'] for report in reports.values()):
        raise SystemExit('Regression failed')
    binary = output / '蓝色大肥鱼.app/Contents/MacOS/BlueWhalePet'
    result = {
        'ok': True, 'mode': mode, 'native_ui': 'passed' if mode == 'full' else 'not_run',
        'verified_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'checks': {name: len(report['checks']) for name, report in reports.items()},
        'inputs': fingerprints(project),
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
    }
    (output / 'results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'inputs'}, indent=2))
