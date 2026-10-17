import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PolicyPagesTests(unittest.TestCase):
    def test_generation_prunes_unused_pages_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in ('tools/build_policy_pages.py', 'tools/policy_config.py',
                         'policies/config.json'):
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            output = project / 'assets/legal'
            output.mkdir(parents=True)
            (output / 'unused.html').write_text('Unexpected document')
            bundled = project / 'lib/services/policy_pages.g.dart'
            bundled.parent.mkdir(parents=True)
            command = [sys.executable, str(project / 'tools/build_policy_pages.py')]
            subprocess.run(command, check=True, capture_output=True)
            expected = {'index', 'privacy', 'terms', 'permissions', 'sdk', 'support'}
            self.assertEqual({path.stem for path in output.glob('*.html')}, expected)
            first = bundled.read_text()
            self.assertNotIn('Unexpected document', first)
            for name in expected:
                self.assertIn(f"  '{name}':", first)
            pages = {path.name: path.read_bytes() for path in output.glob('*.html')}
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(bundled.read_text(), first)
            self.assertEqual(
                {path.name: path.read_bytes() for path in output.glob('*.html')}, pages)


if __name__ == '__main__':
    unittest.main()
