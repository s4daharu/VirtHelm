#!/usr/bin/env python3
"""Use GitHub-hosted Linux runner resources without changing local build caps."""
import os
from pathlib import Path
import sys


def resource_properties(cpu_count, memory_mib):
    if cpu_count < 1 or memory_mib < 4096:
        raise ValueError('Expected at least one CPU and 4 GiB RAM on the hosted runner.')
    # Leave roughly a third of RAM for Flutter, native workers, and the OS.
    return {
        'org.gradle.jvmargs': (
            f'-Xmx{memory_mib // 2}m '
            f'-XX:MaxMetaspaceSize={min(1024, memory_mib // 16)}m'
        ),
        'org.gradle.workers.max': str(cpu_count),
        'org.gradle.parallel': 'true',
        'org.gradle.caching': 'true',
        'kotlin.daemon.jvmargs': f'-Xmx{memory_mib // 8}m',
    }


def write_properties(home, properties):
    path = home / 'gradle.properties'
    lines = path.read_text(encoding='utf-8').splitlines() if path.exists() else []
    lines = [line for line in lines if line.split('=', 1)[0].strip() not in properties]
    lines.extend(f'{key}={value}' for key, value in properties.items())
    home.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main():
    # Fail before touching any files on local or self-hosted machines.
    if (os.environ.get('GITHUB_ACTIONS') != 'true' or
            os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted' or
            sys.platform != 'linux'):
        raise SystemExit('Resource overrides are only allowed on GitHub-hosted Linux runners.')

    cpu_count = len(os.sched_getaffinity(0))
    memory_kib = next(
        int(line.split()[1])
        for line in Path('/proc/meminfo').read_text(encoding='utf-8').splitlines()
        if line.startswith('MemTotal:')
    )
    memory_mib = memory_kib // 1024
    properties = resource_properties(cpu_count, memory_mib)
    home = Path(os.environ.get('GRADLE_USER_HOME', str(Path.home() / '.gradle')))
    # Gradle user-home properties override the generated runner's local caps.
    # Do not modify the generated runner or cache this file.
    write_properties(home, properties)
    print(f'CI Gradle: {cpu_count} workers, {memory_mib} MiB runner RAM, parallel builds enabled.')
    for key, value in properties.items():
        print(f'{key}={value}')


if __name__ == '__main__':
    main()
