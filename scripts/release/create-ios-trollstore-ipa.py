#!/usr/bin/env python3
"""Add shared-group entitlements to an unsigned XSIME IPA for TrollStore.

macOS only; no Apple certificate, provisioning profile or product rebuild needed.
This is an ad-hoc package for TrollStore, not an App Store/self-signing package.
"""
import argparse
import hashlib
import json
import plistlib
import runpy
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

VERIFY = runpy.run_path(str(Path(__file__).resolve().parents[2]
                           / 'platforms/ios/scripts/verify-release-ipa.py'))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate_zip(ipa):
    # ditto preserves executable permissions; reject links and traversal first.
    with zipfile.ZipFile(ipa) as archive:
        names = set()
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            require(not path.is_absolute() and '..' not in path.parts
                    and '\\' not in entry.filename and path.parts
                    and (path.parts[0] == 'Payload' or
                         (path.parts[0] == '__MACOSX' and
                          (len(path.parts) == 1 or path.parts[1] == 'Payload'))),
                    'Unsafe IPA entry')
            require(not stat.S_ISLNK(entry.external_attr >> 16), 'IPA symlinks are unsupported')
            require(str(path) not in names, 'Duplicate IPA entry')
            names.add(str(path))


def bundles(app):
    extension = app / 'PlugIns/RIMESKeyboard.appex'
    require(list((app / 'PlugIns').glob('*.appex')) == [extension],
            'Expected exactly the XSIME keyboard extension')
    require(not any(p.suffix in ('.framework', '.dylib', '.app')
                    or (p.suffix == '.appex' and p != extension)
                    for p in app.rglob('*')), 'Unexpected nested code; signing rules need review')
    VERIFY['validate_unsigned_app'](app)
    result = []
    for bundle, identifier in ((extension, VERIFY['KEYBOARD_ID']), (app, VERIFY['APP_ID'])):
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        require(info.get('CFBundleIdentifier') == identifier, 'Unexpected bundle identifier')
        executable = info.get('CFBundleExecutable', '')
        require(executable and Path(executable).name == executable
                and (bundle / executable).is_file(), 'Missing bundle executable')
        require((bundle / 'PrivacyInfo.xcprivacy').is_file(), 'Missing privacy manifest')
        require(not (bundle / 'embedded.mobileprovision').exists(),
                'Use the unsigned community IPA, not an Apple provisioned package')
        result.append((bundle, info))
    for field in ('CFBundleShortVersionString', 'CFBundleVersion'):
        require(result[0][1].get(field) and result[0][1][field] == result[1][1].get(field),
                'App and keyboard versions differ')
    return result


def entitlements(info):
    return {
        'application-identifier': VERIFY['TEAM_ID'] + '.' + info['CFBundleIdentifier'],
        'com.apple.developer.team-identifier': VERIFY['TEAM_ID'],
        'com.apple.security.application-groups': [info['RIMESAppGroup']],
        'keychain-access-groups': [info['RIMESKeychainGroup']],
    }


def verify_signatures(app):
    receipt = []
    for bundle, info in bundles(app):
        subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
        signed = plistlib.loads(subprocess.check_output(
            ['codesign', '--display', '--entitlements', '-', '--xml', str(bundle)],
            stderr=subprocess.DEVNULL))
        require(signed == entitlements(info), f'{bundle.name}: unexpected signed entitlements')
        receipt.append({'bundle_id': info['CFBundleIdentifier'], 'entitlements': signed})
    return receipt


def package(ipa, output, expected_sha256):
    ipa, output = Path(ipa).resolve(), Path(output).resolve()
    require(digest(ipa) == expected_sha256.lower(), 'Source IPA SHA-256 mismatch')
    sidecars = [output.with_suffix('.sha256'), output.with_suffix('.verification.json')]
    require(not any(p.exists() for p in [output, *sidecars]), 'Refusing to overwrite output')
    validate_zip(ipa)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        subprocess.run(['ditto', '-x', '-k', '--norsrc', str(ipa), str(root)], check=True)
        apps = list((root / 'Payload').glob('*.app'))
        require(len(apps) == 1 and apps[0].name == 'RIMES.app', 'Expected Payload/RIMES.app')
        app = apps[0]
        targets = bundles(app)
        # Preserve all original resources and metadata; only signatures/binaries change.
        executables = {bundle / info['CFBundleExecutable'] for bundle, info in targets}
        resources = {p.relative_to(app): digest(p) for p in app.rglob('*')
                     if p.is_file() and p not in executables}
        for bundle, info in targets:  # Extension first, containing app last.
            original = subprocess.run(['codesign', '--display', str(bundle)], capture_output=True)
            require(original.returncode != 0 and b'not signed at all' in original.stderr,
                    'Expected an unsigned source bundle')
            rights = root / (bundle.name + '.entitlements')
            rights.write_bytes(plistlib.dumps(entitlements(info)))
            subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none',
                            '--generate-entitlement-der', '--entitlements', str(rights),
                            str(bundle)], check=True)
        require(all(digest(app / p) == value for p, value in resources.items()),
                'Original bundle resources changed')
        signed_bundles = verify_signatures(app)
        staged = root / 'trollstore.ipa'
        subprocess.run(['ditto', '-c', '-k', '--keepParent', '--norsrc',
                        str(root / 'Payload'), str(staged)], check=True)
        # Verify the serialized deliverable, not just the staging directory.
        unpacked = root / 'readback'
        validate_zip(staged)
        subprocess.run(['ditto', '-x', '-k', str(staged), str(unpacked)], check=True)
        verify_signatures(unpacked / 'Payload/RIMES.app')
        info = targets[-1][1]
        receipt = {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                   'source_sha256': digest(ipa), 'sha256': digest(staged),
                   'signing': 'ad-hoc with shared-group entitlements; TrollStore only',
                   'original_resources_unchanged': True, 'bundles': signed_bundles,
                   'device_acceptance': 'pending: app save and keyboard read on iOS 17'}
        with output.open('xb') as destination:
            destination.write(staged.read_bytes())
        sidecars[0].write_text(f'{receipt["sha256"]}  {output.name}\n')
        sidecars[1].write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--sha256', required=True, help='Published SHA-256 of the unsigned source IPA')
    args = parser.parse_args()
    print(json.dumps(package(args.ipa, args.output, args.sha256), indent=2))
