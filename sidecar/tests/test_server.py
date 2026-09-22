import subprocess
import sys
import unittest
from pathlib import Path


class ServerTests(unittest.TestCase):
    def test_sidecar_exits_when_stdin_closes(self):
        root = Path(__file__).resolve().parents[1]
        proc = subprocess.Popen(
            [sys.executable, "-m", "rolltag_sidecar"],
            cwd=root,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        try:
            line = proc.stdout.readline()
            self.assertTrue(line.startswith("READY"), line)
            proc.stdin.close()
            proc.stdout.close()
            self.assertEqual(proc.wait(timeout=2), 0)
        except subprocess.TimeoutExpired:
            proc.kill()
            self.fail("sidecar did not exit after stdin closed")
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=2)


if __name__ == "__main__":
    unittest.main()
