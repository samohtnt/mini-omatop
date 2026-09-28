"""Regression checks for the sampler's isolated Python launch."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class IsolatedSamplerTests(unittest.TestCase):
    def test_sampler_ignores_import_path_and_environment_overrides(self):
        source = Path(__file__).resolve().parents[1] / "sample.py"
        with tempfile.TemporaryDirectory(prefix="mini-omatop security ") as directory:
            working = Path(directory)
            script = working / "sample.py"
            shutil.copy2(source, script)
            # Harmless traps fail the test if Python imports user-controlled code.
            for module in ("json.py", "argparse.py", "sitecustomize.py", "usercustomize.py"):
                (working / module).write_text('raise RuntimeError("unexpected external import")\n')
            environment = os.environ.copy()
            environment.update(
                PYTHONPATH=str(working),
                PYTHONHOME=str(working / "nonexistent-python-home"),
                PYTHONUSERBASE=str(working),
                PYTHONINSPECT="1",
            )
            result = subprocess.run(
                [sys.executable, "-I", "-u", str(script), "--once"],
                cwd=working,
                env=environment,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=5,
                check=True,
            )
            payload = json.loads(result.stdout)
            self.assertIn("cpuLogical", payload)
            self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
