"""Read-only heuristic scan; output only file, line and rule, never matched data."""
import argparse
import re
import subprocess

RULES = {
    'github-token': rb'(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{50,255})',
    'private-key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'aws-access-key': rb'AKIA[0-9A-Z]{16}',
    'google-api-key': rb'AIza[0-9A-Za-z_-]{35}',
}
PRIVATE_NAMES = re.compile(r'(?i)(?:^|/)(?:\.env(?:\..*)?|key\.properties)$|\.(?:jks|keystore|p12|pfx|pem)$')


def inspect(name, data):
    findings = []
    if PRIVATE_NAMES.search(name):
        findings.append(f'{name}:1:credential-file')
    for number, line in enumerate(data.splitlines(), 1):
        for rule, pattern in RULES.items():
            if re.search(pattern, line):
                findings.append(f'{name}:{number}:{rule}')
    return findings


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL)


def scan(mode):
    findings = set()
    revisions = git('rev-list', '--all').decode().splitlines() if mode == 'history' else [None]
    for revision in revisions:
        if mode == 'staged':
            names = git('diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z')
        else:
            names = git('ls-tree', '-r', '--name-only', '-z', revision or 'HEAD')
        for raw in names.split(b'\0'):
            if not raw:
                continue
            name = raw.decode('utf-8', errors='replace')
            blob = f'{revision or ""}:{name}' if mode == 'staged' else f'{revision or "HEAD"}:{name}'
            data = git('show', blob)
            findings.update(inspect(name, data))
    for finding in sorted(findings):
        print(finding)
    return bool(findings)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--mode', choices=['staged', 'head', 'history'], default='staged')
    raise SystemExit(scan(parser.parse_args().mode))
