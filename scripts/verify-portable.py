"""Build and check a fresh, self-contained source copy without local caches."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile

from report import fingerprints

PROJECT_FILES = ['Sources', 'Tests', 'scripts', 'Assets', 'HighResolution', 'Docs',
                 'build.sh', 'Info.plist', 'PetIcon.icns', 'README.md', '.gitignore', '使用说明.txt',
                 'LICENSE', '.gitattributes', 'teaser.png']


def copy_project(project, target):
    for name in PROJECT_FILES:
        source = project / name
        if source.is_dir():
            shutil.copytree(source, target / name,
                            ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '.DS_Store'))
        else:
            shutil.copy2(source, target / name)


if __name__ == '__main__':
    project = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix='Blue Whale Clean Build ') as directory:
        target = Path(directory)
        copy_project(project, target)
        run = subprocess.run(['/bin/zsh', 'scripts/test.sh', '--headless'], cwd=target,
                             capture_output=True, text=True, timeout=180)
        if run.returncode:
            raise SystemExit(run.stdout + run.stderr)
        result = json.loads((target / '.build/regression/results.json').read_text())
        if not result['ok'] or result['inputs'] != fingerprints(project):
            raise SystemExit('Clean source copy did not match tested source inputs')
        report = {'ok': True, 'fresh_directory': True, 'space_in_path': True,
                  'native_ui': 'not_run', 'checks': result['checks'], 'inputs': result['inputs']}
    output = project / '.build/regression/portable.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    print('Fresh source copy builds and passes headless regression; no local plugins or caches needed.')
