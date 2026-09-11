#!/usr/bin/env python3
"""Build pinned libssh2 for the app and its macOS connection checks."""
from pathlib import Path
import subprocess, shutil
ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / '.build/references'
NATIVE = ROOT / '.build/native'
SSH_REV = 'bb8e0957b8091e5b6668b2ffe647721f5cc2fb7d'
SSL_REV = '4b1188ba947ddc23d03b13096b9e44b804e146c9'

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

def checkout(name, url, revision):
    path = REF / name
    if not (path / '.git').exists():
        run('git', 'clone', '--no-checkout', '--filter=blob:none', url, path)
    run('git', '-C', path, 'checkout', '--detach', revision)
    return path

REF.mkdir(parents=True, exist_ok=True)
ssh = checkout('libssh2', 'https://github.com/libssh2/libssh2.git', SSH_REV)
ssl = checkout('OpenSSL', 'https://github.com/krzyzanowskim/OpenSSL.git', SSL_REV)
framework = ssl / 'Frameworks/OpenSSL.xcframework'
for name, sdk, slice_name in [('macos', 'macosx', 'macos-arm64_x86_64'), ('iphoneos', 'iphoneos', 'ios-arm64'), ('iphonesimulator', 'iphonesimulator', 'ios-arm64_x86_64-simulator')]:
    build = NATIVE / name
    headers = build / 'ssl-include'
    headers.mkdir(parents=True, exist_ok=True)
    link = headers / 'openssl'
    if not link.exists(): link.symlink_to(framework / slice_name / 'OpenSSL.framework/Headers')
    ssl_binary = framework / slice_name / 'OpenSSL.framework/OpenSSL'
    sdkpath = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
    options = ['-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_OSX_SYSROOT='+sdkpath,
               '-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0', '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_EXAMPLES=OFF',
               '-DBUILD_TESTING=OFF', '-DCRYPTO_BACKEND=OpenSSL', '-DCMAKE_BUILD_TYPE=Release',
               '-DOPENSSL_INCLUDE_DIR='+str(headers), '-DOPENSSL_CRYPTO_LIBRARY='+str(ssl_binary),
               '-DOPENSSL_SSL_LIBRARY='+str(ssl_binary), '-DENABLE_ZLIB_COMPRESSION=ON']
    if name != 'macos': options += ['-DCMAKE_SYSTEM_NAME=iOS']
    run('cmake', '-S', ssh, '-B', build, *options)
    run('cmake', '--build', build, '--parallel', '8')
(NATIVE / 'include').mkdir(exist_ok=True)
for f in ['libssh2.h', 'libssh2_publickey.h', 'libssh2_sftp.h']:
    shutil.copy2(ssh / 'include' / f, NATIVE / 'include' / f)
print('Native libraries ready.')
