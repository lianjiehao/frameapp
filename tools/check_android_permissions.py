"""Check sensitive permissions in the merged APK, including transitive plugins."""
import os
from pathlib import Path
import subprocess
import sys

apk = Path(sys.argv[1])
sdk = os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME')
if not sdk:
    local = Path('android/local.properties')
    if local.exists():
        sdk = next((line.split('=', 1)[1] for line in local.read_text().splitlines()
                    if line.startswith('sdk.dir=')), None)
if not sdk:
    raise SystemExit('Android SDK path is unavailable')
tools = list((Path(sdk) / 'build-tools').glob('*/aapt'))
if not tools:
    raise SystemExit('aapt is unavailable')
aapt = max(tools, key=lambda path: tuple(int(part) if part.isdigit() else 0
                                      for part in path.parent.name.split('.')))
permissions = subprocess.check_output([str(aapt), 'dump', 'permissions', str(apk)], text=True)
allowed = {'android.permission.INTERNET', 'android.permission.CAMERA',
           'android.permission.WRITE_EXTERNAL_STORAGE', 'android.permission.ACCESS_NETWORK_STATE',
           'studio.framecoach.framecoach.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
           'studio.framecoach.framecoach.debug.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}
for line in permissions.splitlines():
    if line.startswith('uses-permission:'):
        name = line.split("name='", 1)[1].split("'", 1)[0]
        if name not in allowed:
            raise SystemExit(f'Unreviewed permission in final APK: {name}')
        if name == 'android.permission.WRITE_EXTERNAL_STORAGE' and "maxSdkVersion='29'" not in line:
            raise SystemExit('Storage write permission must be restricted to Android API 29 or earlier')
print(permissions)
print('Merged APK permission check passed')
