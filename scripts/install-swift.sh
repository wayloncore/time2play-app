#!/usr/bin/env bash
# Installs the Swift toolchain from swift.org into /opt/swift in a Linux cloud session (Ubuntu 24.04), checks its
# signature against swift.org's published keys, and adds the packages it needs. Safe to run twice.
# Then: export PATH=/opt/swift/usr/bin:$PATH; cd Core && swift test
set -euo pipefail
V="${SWIFT_VERSION_WANTED:-6.4.2}"
if [ -x /opt/swift/usr/bin/swift ] && /opt/swift/usr/bin/swift --version 2>/dev/null | grep -q "Swift version $V "; then
  echo "Swift $V is already in /opt/swift"; exit 0
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
url="https://download.swift.org/swift-$V-release/ubuntu2404/swift-$V-RELEASE/swift-$V-RELEASE-ubuntu24.04.tar.gz"
curl -sSfL -o "$tmp/swift.tar.gz" "$url"
curl -sSfL -o "$tmp/swift.tar.gz.sig" "$url.sig"
curl -sSfL -o "$tmp/keys.asc" https://swift.org/keys/all-keys.asc
export GNUPGHOME="$tmp/gnupg"; mkdir -m 700 "$GNUPGHOME"
gpg -q --import "$tmp/keys.asc"
gpg --verify "$tmp/swift.tar.gz.sig" "$tmp/swift.tar.gz"
apt-get install -y -q binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libpython3-dev libsqlite3-0 \
  libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev pkg-config tzdata zlib1g-dev >/dev/null \
  || { apt-get update -q >/dev/null; apt-get install -y -q binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libpython3-dev libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev pkg-config tzdata zlib1g-dev >/dev/null; }
rm -rf /opt/swift; mkdir -p /opt/swift
tar -xzf "$tmp/swift.tar.gz" -C /opt/swift --strip-components=1
/opt/swift/usr/bin/swift --version
