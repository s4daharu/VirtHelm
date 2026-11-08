"""Offline regression tests for generated runner and release shell logic."""
from pathlib import Path
import json
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
        activity = self.root / 'app/android/app/src/main/kotlin/com/s4daharu/virthelm/MainActivity.kt'
        activity.parent.mkdir(parents=True)
        activity.write_text('package com.s4daharu.virthelm\n'
                            'import io.flutter.embedding.android.FlutterActivity\n'
                            'class MainActivity : FlutterActivity() {}\n')
        template = self.root / 'scripts/android/MainActivity.kt'
        template.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'scripts/android/MainActivity.kt', template)
        launcher = self.root / 'scripts/android/launcher'
        shutil.copytree(ROOT / 'scripts/android/launcher', launcher)
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
        first = (manifest.read_bytes(), gradle.read_bytes(), activity.read_bytes())
        self.run_checked(['python3', str(self.root / 'scripts/harden_android.py')])
        self.assertEqual(first, (manifest.read_bytes(), gradle.read_bytes(), activity.read_bytes()))
        self.run_checked(['python3', str(self.root / 'scripts/check_android_generated.py')])
        properties = (self.root / 'app/android/gradle.properties').read_text()
        self.assertNotIn('-Xmx8G', properties)
        self.assertIn('android.useAndroidX=true', properties)
        self.assertIn('ACCESS_NETWORK_STATE', manifest.read_text())
        self.assertIn('registerDefaultNetworkCallback', activity.read_text())
        icon = self.root / 'app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml'
        foreground = self.root / 'app/android/app/src/main/res/drawable/virthelm_icon_foreground.xml'
        self.assertEqual(
            icon.read_text(),
            (ROOT / 'scripts/android/launcher/mipmap-anydpi-v26/ic_launcher.xml').read_text(),
        )
        self.assertEqual(
            foreground.read_text(),
            (ROOT / 'scripts/android/launcher/drawable/virthelm_icon_foreground.xml').read_text(),
        )
        self.assertIn('android:roundIcon="@mipmap/ic_launcher_round"', manifest.read_text())

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
        for key in ('release_url', 'arm64_url', 'armv7_url', 'checksums_url'):
            script = script.replace('${{ steps.release.outputs.' + key + ' }}',
                                    f'https://github.com/s4daharu/VirtHelm/releases/{key}')
        summary = self.root / 'summary.md'
        result = self.run_checked(['bash', '-euo', 'pipefail', '-c', script],
                                  env=dict(os.environ, GITHUB_STEP_SUMMARY=str(summary)))
        self.assertEqual(result.stderr, '')
        self.assertIn('`VirtHelm-v0.1.0-arm64-v8a.apk`', summary.read_text())
        self.assertIn('`VirtHelm-v0.1.0-armeabi-v7a.apk`', summary.read_text())
        self.assertIn('[Download ARM64 APK](https://github.com/s4daharu/VirtHelm/releases/arm64_url)', summary.read_text())
        self.assertIn('not Actions artifacts', summary.read_text())

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
        self.assertIn(
            "awk -F': ' '/certificate SHA-256 digest:/ {print $NF; exit}'",
            text,
        )
        self.assertIn('test -n "$signer_digest"', text)
        self.assertIn('test "$signer_digest" = "$expected_digest"', text)
        self.assertIn(
            "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
            text,
        )
        for script in [release_script(name) for name in [
            'Restore required release keystore', 'Build split release APKs',
            'Verify APK set, signatures, and ABIs', 'Create GitHub prerelease',
        ]]:
            script = re.sub(r'\$\{\{.*?\}\}', 'SAFE_TEST_VALUE', script)
            self.run_checked(['bash', '-n'], input=script)

    def test_workflows_never_store_apks_as_actions_artifacts(self):
        for path in (ROOT / '.github/workflows').iterdir():
            if path.suffix not in ('.yml', '.yaml'):
                continue
            text = path.read_text()
            self.assertNotIn('actions/upload-artifact@', text, path.name)
            self.assertNotIn('actions/download-artifact@', text, path.name)
        release = (ROOT / '.github/workflows/release-android.yml').read_text()
        self.assertIn('  workflow_dispatch:', release)
        self.assertIn('  workflow_run:', release)
        self.assertIn('workflows: ["Docs and Android checks"]', release)
        self.assertIn("github.event.workflow_run.event == 'push'", release)
        self.assertIn("github.event.workflow_run.head_branch == 'main'", release)
        self.assertIn("github.event.workflow_run.conclusion == 'success'", release)
        self.assertIn('github.event.workflow_run.head_sha || github.sha', release)
        self.assertNotIn('\n  push:', release)

    def publish_fixture(self, *, existing=False, attempt='1', upload_failure=False,
                        transient_upload=False, omit_remote_asset=False,
                        wrong_remote_size=False, missing_local_asset=False):
        """Execute the real publication block with a local GitHub CLI stub."""
        paths = [self.root / name for name in (
            'VirtHelm-v0.1.0-arm64-v8a.apk',
            'VirtHelm-v0.1.0-armeabi-v7a.apk', 'SHA256SUMS.txt')]
        for path in paths:
            path.write_text('offline-test-fixture')
        assets = [{'name': path.name, 'size': path.stat().st_size} for path in paths]
        if omit_remote_asset:
            assets.pop()
        if wrong_remote_size:
            assets[0]['size'] += 1
        if missing_local_asset:
            paths[-1].unlink()
        log = self.root / 'gh-calls.jsonl'
        output = self.root / 'release-output.txt'
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['MOCK_GH_LOG'], 'a') as handle:
    handle.write(json.dumps(args) + '\\n')
state = Path(os.environ['MOCK_GH_STATE'])
if args[:2] == ['release', 'view']:
    if '--json' in args:
        print(os.environ['MOCK_GH_ASSETS'])
    elif not state.exists() and os.environ['MOCK_GH_EXISTING'] != 'true':
        sys.exit(1)
elif args[:2] == ['release', 'create']:
    state.touch()
elif args[:2] == ['release', 'edit']:
    pass
elif args[:2] == ['release', 'upload']:
    marker = Path(os.environ['MOCK_GH_UPLOAD_MARKER'])
    if os.environ['MOCK_GH_UPLOAD_FAILURE'] == 'true':
        sys.exit(1)
    if os.environ['MOCK_GH_TRANSIENT'] == 'true' and not marker.exists():
        marker.touch()
        sys.exit(1)
else:
    sys.exit(94)
''')
        gh.chmod(0o700)
        sleeper = bin_dir / 'sleep'
        sleeper.write_text('#!/bin/sh\nexit 0\n')
        sleeper.chmod(0o700)
        env = dict(os.environ,
                   PATH=f'{bin_dir}:{os.environ["PATH"]}',
                   GH_TOKEN='offline-stub-only',
                   RELEASE_VERSION='0.1.0',
                   ARM64_APK=str(paths[0]), ARMV7_APK=str(paths[1]), CHECKSUMS=str(paths[2]),
                   GITHUB_SHA='a' * 40, RELEASE_SHA='a' * 40,
                   GITHUB_REPOSITORY='s4daharu/VirtHelm',
                   GITHUB_SERVER_URL='https://github.com', GITHUB_RUN_NUMBER='42',
                   GITHUB_RUN_ATTEMPT=attempt, GITHUB_OUTPUT=str(output),
                   MOCK_GH_LOG=str(log), MOCK_GH_STATE=str(self.root / 'created'),
                   MOCK_GH_EXISTING=str(existing).lower(), MOCK_GH_ASSETS=json.dumps({'assets': assets}),
                   MOCK_GH_UPLOAD_FAILURE=str(upload_failure).lower(),
                   MOCK_GH_TRANSIENT=str(transient_upload).lower(),
                   MOCK_GH_UPLOAD_MARKER=str(self.root / 'transient-failure'))
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', release_script('Create GitHub prerelease')],
                                cwd=self.root, env=env, capture_output=True, text=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        outputs = dict(line.split('=', 1) for line in output.read_text().splitlines()) if output.exists() else {}
        return result, calls, outputs

    def test_direct_release_publication_uploads_and_verifies_all_assets(self):
        result, calls, outputs = self.publish_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(args for args in calls if args[:2] == ['release', 'create'])
        self.assertEqual(create[2], 'v0.1.0-build-42')
        self.assertEqual(create[create.index('--target') + 1], 'a' * 40)
        self.assertIn('--prerelease', create)
        upload = next(args for args in calls if args[:2] == ['release', 'upload'])
        self.assertEqual(sum(arg.endswith('.apk') for arg in upload), 2)
        self.assertTrue(any(arg.endswith('SHA256SUMS.txt') for arg in upload))
        self.assertEqual(outputs['release_url'], 'https://github.com/s4daharu/VirtHelm/releases/tag/v0.1.0-build-42')
        for key in ('arm64_url', 'armv7_url', 'checksums_url'):
            self.assertIn('/releases/download/v0.1.0-build-42/', outputs[key])

    def test_existing_release_is_reused_without_recreating_or_moving_tag(self):
        result, calls, outputs = self.publish_fixture(existing=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(args[:2] == ['release', 'edit'] for args in calls))
        self.assertFalse(any(args[:2] == ['release', 'create'] for args in calls))
        self.assertIn('release_url', outputs)

    def test_rerun_uses_separate_release_tag(self):
        result, calls, outputs = self.publish_fixture(attempt='2')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(outputs['release_url'].endswith('v0.1.0-build-42-attempt-2'))
        self.assertTrue(any(args[:3] == ['release', 'create', 'v0.1.0-build-42-attempt-2'] for args in calls))

    def test_transient_release_upload_is_retried(self):
        result, calls, outputs = self.publish_fixture(transient_upload=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(args[:2] == ['release', 'upload'] for args in calls), 2)
        self.assertIn('release_url', outputs)

    def test_failed_upload_does_not_claim_success_or_emit_download_links(self):
        result, calls, outputs = self.publish_fixture(upload_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sum(args[:2] == ['release', 'upload'] for args in calls), 3)
        self.assertEqual(outputs, {})

    def test_missing_remote_asset_prevents_successful_publication_summary(self):
        result, calls, outputs = self.publish_fixture(omit_remote_asset=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Release asset missing or wrong size', result.stderr)
        self.assertEqual(outputs, {})

    def test_missing_local_asset_prevents_any_release_api_calls(self):
        result, calls, outputs = self.publish_fixture(missing_local_asset=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
        self.assertEqual(outputs, {})

    def test_wrong_remote_asset_size_prevents_successful_publication_summary(self):
        result, calls, outputs = self.publish_fixture(wrong_remote_size=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Release asset missing or wrong size', result.stderr)
        self.assertEqual(outputs, {})


if __name__ == '__main__':
    unittest.main()
