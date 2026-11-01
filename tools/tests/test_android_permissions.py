from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'check_android_permissions.py'


class AndroidPermissionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.sdk = Path(self.directory.name)
        self.aapt = self.sdk / 'build-tools/36.0.0/aapt'
        self.aapt.parent.mkdir(parents=True)
        self.aapt.touch()

    def check_permissions(self, permissions):
        output = io.StringIO()
        with patch.dict(os.environ, {'ANDROID_SDK_ROOT': str(self.sdk)}), \
                patch.object(sys, 'argv', [str(SCRIPT), 'fixture.apk']), \
                patch('subprocess.check_output', return_value=permissions) as inspect, \
                redirect_stdout(output):
            runpy.run_path(str(SCRIPT), run_name='__main__')
        inspect.assert_called_once_with(
            [str(self.aapt), 'dump', 'permissions', 'fixture.apk'], text=True)
        return output.getvalue()

    def test_release_and_debug_internal_receiver_permissions_are_allowed(self):
        for package in ('studio.framecoach.framecoach',
                        'studio.framecoach.framecoach.debug'):
            with self.subTest(package=package):
                permissions = (
                    f'package: {package}\n'
                    "uses-permission: name='android.permission.CAMERA'\n"
                    f"uses-permission: name='{package}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'\n"
                )
                self.assertIn('Merged APK permission check passed',
                              self.check_permissions(permissions))

    def test_unreviewed_sensitive_permissions_are_rejected(self):
        for permission in ('RECORD_AUDIO', 'ACCESS_FINE_LOCATION',
                           'READ_EXTERNAL_STORAGE', 'READ_MEDIA_IMAGES'):
            with self.subTest(permission=permission), self.assertRaisesRegex(
                    SystemExit, 'Unreviewed permission in final APK'):
                self.check_permissions(
                    f"uses-permission: name='android.permission.{permission}'\n")

    def test_internal_receiver_permission_names_must_match_exactly(self):
        for permission in (
                'other.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
                'studio.framecoach.framecoach.debug.extra.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
                'studio.framecoach.framecoach.debug.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION_EXTRA'):
            with self.subTest(permission=permission), self.assertRaisesRegex(
                    SystemExit, 'Unreviewed permission in final APK'):
                self.check_permissions(f"uses-permission: name='{permission}'\n")

    def test_storage_write_is_allowed_when_limited_to_api_29(self):
        self.assertIn('Merged APK permission check passed', self.check_permissions(
            "uses-permission: name='android.permission.WRITE_EXTERNAL_STORAGE' maxSdkVersion='29'\n"))

    def test_storage_write_without_the_api_limit_is_rejected(self):
        for limit in ('', " maxSdkVersion='30'"):
            with self.subTest(limit=limit), self.assertRaisesRegex(
                    SystemExit, 'Storage write permission must be restricted'):
                self.check_permissions(
                    f"uses-permission: name='android.permission.WRITE_EXTERNAL_STORAGE'{limit}\n")


if __name__ == '__main__':
    unittest.main()
