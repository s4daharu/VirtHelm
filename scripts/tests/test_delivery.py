"""Offline regression tests for generated runner and release shell logic."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]


def release_script(name):
    text = (ROOT / '.github/workflows/release-android.yml').read_text()
    step = text.split(f'      - name: {name}\n', 1)[1].split('\n      - name:', 1)[0]
    return textwrap.dedent(step.split('        run: |\n', 1)[1])


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='virthelm-delivery-test-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'app').mkdir()

    def run_checked(self, args, **kwargs):
        result = subprocess.run(args, capture_output=True, text=True, **kwargs)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_hardening_can_be_repeated_without_weakening_runner(self):
        for name in ['harden_android.py', 'check_android_generated.py']:
            shutil.copy2(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        manifest = self.root / 'app/android/app/src/main/AndroidManifest.xml'
        manifest.parent.mkdir(parents=True)
        manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                            '<application android:label="virthelm"></application></manifest>')
        gradle = self.root / 'app/android/app/build.gradle.kts'
        (self.root / 'app/android/gradle.properties').write_text(
            'org.gradle.jvmargs=-Xmx8G\nandroid.useAndroidX=true\n')
        gradle.write_text('''plugins {}
android {
    defaultConfig {
        applicationId = "com.s4daharu.virthelm"
        minSdk = flutter.minSdkVersion
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
''')
        self.run_checked(['python3', str(self.root / 'scripts/harden_android.py')])
        first = (manifest.read_bytes(), gradle.read_bytes())
        self.run_checked(['python3', str(self.root / 'scripts/harden_android.py')])
        self.assertEqual(first, (manifest.read_bytes(), gradle.read_bytes()))
        self.run_checked(['python3', str(self.root / 'scripts/check_android_generated.py')])
        properties = (self.root / 'app/android/gradle.properties').read_text()
        self.assertNotIn('-Xmx8G', properties)
        self.assertIn('android.useAndroidX=true', properties)

        script = release_script('Configure generated runner for release signing')
        self.run_checked(['bash', '-euo', 'pipefail', '-c', script], cwd=self.root / 'app')
        signed = gradle.read_text()
        self.assertTrue(signed.startswith('import java.util.Properties\n'))
        self.assertIn('signingConfigs.getByName("release")', signed)
        self.assertNotIn('signingConfigs.getByName("debug")', signed)

    def test_bootstrap_restores_lockfile_even_when_generator_fails(self):
        shutil.copy2(ROOT / 'scripts/bootstrap_android.sh', self.root / 'scripts/bootstrap_android.sh')
        lock = self.root / 'app/pubspec.lock'
        lock.write_text('original-locked-dependencies\n')
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        flutter = bin_dir / 'flutter'
        flutter.write_text('#!/bin/sh\nprintf "unexpected rewrite\\n" > pubspec.lock\nexit 7\n')
        flutter.chmod(0o700)
        result = subprocess.run(['bash', str(self.root / 'scripts/bootstrap_android.sh')],
                                env=dict(os.environ, PATH=f'{bin_dir}:{os.environ["PATH"]}'),
                                capture_output=True)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(lock.read_text(), 'original-locked-dependencies\n')

    def test_release_summary_backticks_are_literal_not_shell_commands(self):
        script = release_script('Build summary')
        script = script.replace('${{ steps.metadata.outputs.version }}', '0.1.0')
        script = script.replace('${{ steps.metadata.outputs.build_number }}', '43')
        summary = self.root / 'summary.md'
        result = self.run_checked(['bash', '-euo', 'pipefail', '-c', script],
                                  env=dict(os.environ, GITHUB_STEP_SUMMARY=str(summary)))
        self.assertEqual(result.stderr, '')
        self.assertIn('`VirtHelm-v0.1.0-arm64-v8a.apk`', summary.read_text())
        self.assertIn('`VirtHelm-v0.1.0-armeabi-v7a.apk`', summary.read_text())

    def test_release_version_code_increases_and_invalid_version_is_rejected(self):
        script = release_script('Read app version')
        (self.root / 'pubspec.yaml').write_text('version: 0.1.0+1\n')
        output = self.root / 'output.txt'
        self.run_checked(['bash', '-euo', 'pipefail', '-c', script], cwd=self.root,
                         env=dict(os.environ, GITHUB_OUTPUT=str(output), GITHUB_RUN_NUMBER='42'))
        self.assertIn('build_number=43\n', output.read_text())
        (self.root / 'pubspec.yaml').write_text('version: unsafe+1\n')
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script], cwd=self.root,
                                env=dict(os.environ, GITHUB_OUTPUT=str(output), GITHUB_RUN_NUMBER='42'),
                                capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_signing_material_is_private_and_cleaned_after_failure(self):
        text = (ROOT / '.github/workflows/release-android.yml').read_text()
        self.assertIn('umask 077', release_script('Restore required release keystore'))
        self.assertRegex(text, r'name: Remove temporary signing material\n\s+if: always\(\)')
        self.assertIn('test "$signer_digest" = "$expected_digest"', text)
        self.assertIn("if: github.ref == 'refs/heads/main'", text)
        for script in [release_script(name) for name in [
            'Restore required release keystore', 'Build split release APKs',
            'Verify APK set, signatures, and ABIs', 'Create GitHub prerelease',
        ]]:
            script = re.sub(r'\$\{\{.*?\}\}', 'SAFE_TEST_VALUE', script)
            self.run_checked(['bash', '-n'], input=script)


if __name__ == '__main__':
    unittest.main()
