"""Offline tests for hosted-runner tuning; never alter the machine's Gradle home."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/configure_ci_gradle.py'
SPEC = importlib.util.spec_from_file_location('configure_ci_gradle', SCRIPT)
CI_GRADLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI_GRADLE)


class CiGradleTests(unittest.TestCase):
    def test_all_cpus_and_memory_scale_with_runner(self):
        for cpus, memory in [(2, 7168), (4, 16384), (16, 65536)]:
            with self.subTest(cpus=cpus, memory=memory):
                properties = CI_GRADLE.resource_properties(cpus, memory)
                self.assertEqual(properties['org.gradle.workers.max'], str(cpus))
                self.assertEqual(properties['org.gradle.parallel'], 'true')
                self.assertEqual(properties['org.gradle.caching'], 'true')
                self.assertEqual(properties['org.gradle.jvmargs'],
                                 f'-Xmx{memory // 2}m '
                                 f'-XX:MaxMetaspaceSize={min(1024, memory // 16)}m')
                self.assertEqual(properties['kotlin.daemon.jvmargs'], f'-Xmx{memory // 8}m')

    def test_invalid_resource_detection_fails_closed(self):
        for cpus, memory in [(0, 7168), (4, 0), (4, 2048)]:
            with self.subTest(cpus=cpus, memory=memory):
                with self.assertRaises(ValueError):
                    CI_GRADLE.resource_properties(cpus, memory)

    def test_properties_are_repeatable_and_preserve_unrelated_settings(self):
        with tempfile.TemporaryDirectory(prefix='virthelm-ci-gradle-') as directory:
            home = Path(directory) / 'gradle'
            properties = CI_GRADLE.resource_properties(4, 16384)
            CI_GRADLE.write_properties(home, properties)
            path = home / 'gradle.properties'
            path.write_text('android.useAndroidX=true\n# Keep this comment\n'
                            'org.gradle.workers.max=2\norg.gradle.workers.max=1\n'
                            'org.gradle.parallel=false\norg.gradle.jvmargs=-Xmx2048m\n'
                            'kotlin.daemon.jvmargs=-Xmx512m\n')
            CI_GRADLE.write_properties(home, properties)
            first = path.read_text()
            CI_GRADLE.write_properties(home, properties)
            self.assertEqual(first, path.read_text())
            self.assertIn('android.useAndroidX=true\n# Keep this comment\n', first)
            for key, value in properties.items():
                self.assertEqual(first.count(key + '='), 1)
                self.assertIn(f'{key}={value}\n', first)

    def test_local_and_self_hosted_execution_cannot_change_caps(self):
        with tempfile.TemporaryDirectory(prefix='virthelm-ci-gradle-') as directory:
            home = Path(directory)
            path = home / 'gradle.properties'
            original = 'org.gradle.workers.max=2\norg.gradle.parallel=false\n'
            path.write_text(original)
            for actions, runner in [('false', 'github-hosted'), ('true', 'self-hosted'),
                                    ('', '')]:
                with self.subTest(actions=actions, runner=runner):
                    result = subprocess.run(
                        ['python3', str(SCRIPT)], capture_output=True, text=True,
                        env=dict(os.environ, GITHUB_ACTIONS=actions,
                                 RUNNER_ENVIRONMENT=runner, GRADLE_USER_HOME=str(home)),
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('only allowed on GitHub-hosted', result.stderr)
                    self.assertEqual(path.read_text(), original)

    def test_hosted_entrypoint_uses_affinity_ram_and_gradle_user_home(self):
        with mock.patch.dict(os.environ, {
            'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
            'GRADLE_USER_HOME': '/offline-fixture/gradle',
        }), mock.patch.object(CI_GRADLE.sys, 'platform', 'linux'), \
                mock.patch.object(CI_GRADLE.os, 'sched_getaffinity', return_value={0, 1, 2, 3}), \
                mock.patch.object(Path, 'read_text', return_value='MemTotal: 16777216 kB\n'), \
                mock.patch.object(CI_GRADLE, 'write_properties') as write, \
                mock.patch('builtins.print'):
            CI_GRADLE.main()
        write.assert_called_once_with(Path('/offline-fixture/gradle'),
                                      CI_GRADLE.resource_properties(4, 16384))

    def test_android_workflows_bootstrap_before_gradle_cache_and_build(self):
        cache_specs = []
        for name, step_name, action in (
            ('android-ci.yml', 'Cache Gradle dependencies', 'actions/cache'),
            ('release-android.yml', 'Restore Gradle dependencies', 'actions/cache/restore'),
        ):
            with self.subTest(workflow=name):
                text = (ROOT / '.github/workflows' / name).read_text()
                tune = text.index('run: python3 ../scripts/configure_ci_gradle.py')
                bootstrap = text.index('run: bash ../scripts/bootstrap_android.sh')
                cache = text.index(f'      - name: {step_name}\n')
                build = text.index('flutter build apk')
                self.assertLess(tune, bootstrap)
                self.assertLess(bootstrap, cache)
                self.assertLess(cache, build)
                self.assertIn("flutter-version: '3.44.4'\n          cache: true", text)

                cache_step = text[cache:].split('\n      - name:', 1)[0]
                self.assertRegex(cache_step, rf'uses: {action}@[0-9a-f]{{40}}')
                spec = cache_step.split('          path: |\n', 1)[1].strip()
                self.assertEqual(spec.splitlines()[:2], [
                    '~/.gradle/caches/modules-2',
                    '            ~/.gradle/wrapper/dists',
                ])
                self.assertEqual(len(spec.splitlines()), 3)
                self.assertIn('key: gradle-deps-v1-', spec)
                self.assertIn('app/pubspec.lock', spec)
                self.assertIn('gradle-wrapper.properties', spec)
                cache_specs.append(spec)
                if name == 'release-android.yml':
                    self.assertLess(cache, text.index('name: Restore required release keystore'))

                self.assertRegex(text, r'name: Stop Gradle daemons\n\s+if: always\(\)')
                step = text.split('      - name: Stop Gradle daemons\n', 1)[1]
                step = step.split('\n      - name:', 1)[0]
                self.assertIn('./gradlew --stop', step)
                self.assertNotRegex(text, r'ionice|taskset|nice -n')
        self.assertEqual(len(set(cache_specs)), 1)


if __name__ == '__main__':
    unittest.main()
