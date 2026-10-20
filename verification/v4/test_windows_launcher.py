"""Developer check; end users do not need Python. No MATLAB is launched."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WindowsLauncherTests(unittest.TestCase):
    def run_launcher(self, executable, mode=None, root=ROOT, check=True, extra_env=None):
        env = os.environ.copy()
        env['NBIOT_MATLAB_EXE'] = str(executable)
        env['NBIOT_START_MODE'] = mode or 'demo'
        if extra_env:
            env.update(extra_env)
        option = '--check' if check else ''
        command = f'"{env.get("COMSPEC", "cmd.exe")}" /d /s /c ""{root / "START.cmd"}" {option}"'
        return subprocess.run(command, env=env, cwd=root, text=True, errors='replace',
                              capture_output=True, timeout=10)

    def test_missing_matlab_has_actionable_error(self):
        result = self.run_launcher(ROOT / 'missing-MATLAB.exe')
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('R2025b', result.stdout + result.stderr)
        self.assertIn('MATLAB', result.stdout + result.stderr)

    def test_spaces_unicode_and_shell_characters_are_supported(self):
        with tempfile.TemporaryDirectory(prefix="NB IoT & test's ! ") as folder:
            root = Path(folder) / 'проверка запуска'
            root.mkdir()
            executable = root / 'MATLAB R2025b.exe'
            executable.write_bytes(b'not executed in --check mode')
            (root / 'START.cmd').write_bytes((ROOT / 'START.cmd').read_bytes())
            result = self.run_launcher(executable, root=root)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('STARTUP_CHECK_OK', result.stdout)

    def test_saved_report_mode_is_selected(self):
        with tempfile.TemporaryDirectory() as folder:
            executable = Path(folder) / 'matlab.exe'
            executable.write_bytes(b'not executed')
            result = self.run_launcher(executable, mode='saved100')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('saved100', result.stdout)

    def test_invalid_mode_fails_before_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            executable = Path(folder) / 'matlab.exe'
            executable.write_bytes(b'not executed')
            result = self.run_launcher(executable, mode='wrong')
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_real_dispatch_preserves_arguments_in_complex_path(self):
        compiler = Path(os.environ.get('WINDIR', 'C:/Windows')) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        self.assertTrue(compiler.is_file(), 'The release build host needs the installed .NET C# compiler for this developer test.')
        with tempfile.TemporaryDirectory(prefix="NB IoT & dispatch's ! ") as folder:
            root = Path(folder) / 'проверка запуска'
            root.mkdir()
            source = root / 'Capture.cs'
            source.write_text('using System; using System.IO; class Capture { static void Main(string[] args) { File.WriteAllLines(Environment.GetEnvironmentVariable("NBIOT_ARGV_CAPTURE"), args); } }', encoding='utf-8')
            executable = root / 'MATLAB R2025b.exe'
            compiled = subprocess.run([str(compiler), '/nologo', '/target:winexe', '/out:' + str(executable), str(source)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            (root / 'START.cmd').write_bytes((ROOT / 'START.cmd').read_bytes())
            for mode in ['demo', 'saved100']:
                capture = root / (mode + '.txt')
                result = self.run_launcher(executable, mode=mode, root=root, check=False, extra_env={'NBIOT_ARGV_CAPTURE': str(capture)})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                deadline = time.monotonic() + 5
                while not capture.exists() and time.monotonic() < deadline:
                    time.sleep(.05)
                self.assertTrue(capture.is_file(), result.stdout + result.stderr)
                args = capture.read_text(encoding='utf-8-sig').splitlines()
                self.assertEqual(args[:2], ['-sd', str(root)])
                self.assertEqual(args[-2:], ['-r', f"startNBIoT('{mode}');"])
                self.assertEqual(args[2], '-logfile')
                self.assertEqual(Path(args[3]).parent, root / 'logs')

if __name__ == '__main__':
    unittest.main(verbosity=2)
