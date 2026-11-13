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

    def test_both_workflows_tune_before_build_and_cache_only_dependencies(self):
        keys = []
        for name in ('checks.yml', 'release-android.yml'):
            with self.subTest(workflow=name):
                text = (ROOT / '.github/workflows' / name).read_text()
                tune = text.index('run: python3 ../scripts/configure_ci_gradle.py')
                bootstrap = text.index('run: bash ../scripts/bootstrap_android.sh')
                self.assertLess(tune, bootstrap)
                self.assertLess(bootstrap, text.index('flutter build apk'))
                self.assertIn("flutter-version: '3.44.4'\n          cache: true", text)
                cache = text.split('      - name: Cache Gradle dependencies\n', 1)[1]
                cache = cache.split('\n      - name:', 1)[0]
                self.assertIn('actions/cache@cdf6c1fa76f9f475f3d7449005a359c84ca0f306', cache)
                paths = cache.split('          path: |\n', 1)[1].split('          key:', 1)[0]
                self.assertEqual(paths.split(), ['~/.gradle/caches/modules-2', '~/.gradle/wrapper'])
                keys.append(cache.split('          key: ', 1)[1].strip())
                self.assertRegex(text, r'name: Stop Gradle daemons\n\s+if: always\(\)')
                step = text.split('      - name: Stop Gradle daemons\n', 1)[1]
                step = step.split('\n      - name:', 1)[0]
                self.assertIn('./gradlew --stop', step)
                self.assertNotRegex(text, r'ionice|taskset|nice -n')
        self.assertEqual(keys[0], keys[1])


if __name__ == '__main__':
    unittest.main()
