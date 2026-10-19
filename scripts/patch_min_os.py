#!/usr/bin/env python3
"""Lower the minimum-OS stamp of every Mach-O in an .app bundle to a target iOS version.

Needed because a few upstream prebuilt xcframeworks (e.g. RealTimeCutVADCXXLibrary
1.0.3) are built with a minos newer than the deployment target the package claims.
dyld refuses to load such a dylib on older iOS, so the app dies on launch with
"Library not loaded ... built for iOS X.Y". Rewriting the stamp is safe: the
library only links Foundation/CoreML/libc++ which all exist on iOS 15.

Usage: patch_min_os.py <path-to-.app or .appex dir> <major>.<minor> [--plist]
"""
import os
import plistlib
import struct
import sys

MH_MAGIC = 0xFEEDFACE
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_VERSION_MIN_IPHONEOS = 0x24
LC_BUILD_VERSION = 0x32
PLATFORM_IOS = 2


def encode(major, minor, patch=0):
    return (major << 16) | (minor << 8) | patch


def decode(v):
    return "%d.%d.%d" % (v >> 16, (v >> 8) & 0xFF, v & 0xFF)


def patch_slice(buf, offset, want):
    """Patch one thin Mach-O slice inside buf at offset. Returns (old, new) or None."""
    magic = struct.unpack_from("<I", buf, offset)[0]
    if magic == MH_MAGIC_64:
        hdrsize, is64 = 32, True
    elif magic == MH_MAGIC:
        hdrsize, is64 = 28, False
    else:
        return None
    ncmds = struct.unpack_from("<I", buf, offset + 16)[0]
    p = offset + hdrsize
    found = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<2I", buf, p)
        if cmdsize < 8:
            break
        if cmd == LC_BUILD_VERSION:
            platform, minos = struct.unpack_from("<2I", buf, p + 8)
            if platform == PLATFORM_IOS and minos > want:
                found = decode(minos)
                struct.pack_into("<I", buf, p + 12, want)
        elif cmd == LC_VERSION_MIN_IPHONEOS:
            version = struct.unpack_from("<I", buf, p + 8)[0]
            if version > want:
                found = found or decode(version)
                struct.pack_into("<I", buf, p + 8, want)
        p += cmdsize
    return (found, decode(want)) if found else None


def patch_macho(path, want):
    with open(path, "rb") as fh:
        buf = bytearray(fh.read())
    if len(buf) < 32:
        return None
    magic_be = struct.unpack_from(">I", buf, 0)[0]
    changes = []
    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        nfat = struct.unpack_from(">I", buf, 4)[0]
        wide = magic_be == FAT_MAGIC_64
        entsize = 32 if wide else 20
        for i in range(nfat):
            base = 8 + i * entsize
            if wide:
                _, _, off, size, _, _ = struct.unpack_from(">iiQQII", buf, base)
            else:
                _, _, off, size, _ = struct.unpack_from(">5I", buf, base)
            r = patch_slice(buf, off, want)
            if r:
                changes.append(r)
    else:
        r = patch_slice(buf, 0, want)
        if r:
            changes.append(r)
    if changes:
        with open(path, "wb") as fh:
            fh.write(buf)
    return changes


def patch_plist(app, want):
    changed = []
    target = "%d.%d" % (want >> 16, (want >> 8) & 0xFF)
    for root, _dirs, files in os.walk(app):
        for name in files:
            if name != "Info.plist":
                continue
            path = os.path.join(root, name)
            try:
                with open(path, "rb") as fh:
                    data = plistlib.load(fh)
            except Exception:
                continue
            old = data.get("MinimumOSVersion")
            if not old:
                continue
            try:
                parts = [int(x) for x in str(old).split(".")]
            except ValueError:
                continue
            cur = (parts[0] << 16) | ((parts[1] << 8) if len(parts) > 1 else 0)
            if cur > want:
                data["MinimumOSVersion"] = target
                with open(path, "wb") as fh:
                    plistlib.dump(data, fh, fmt=plistlib.FMT_BINARY)
                changed.append((path, old, target))
    return changed


def main():
    if len(sys.argv) < 3:
        print("usage: patch_min_os.py <.app dir> <major>.<minor>")
        return 2
    app = sys.argv[1]
    ver = sys.argv[2].split(".")
    want = encode(int(ver[0]), int(ver[1]) if len(ver) > 1 else 0)
    total = 0
    for root, _dirs, files in os.walk(app):
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                continue
            try:
                with open(path, "rb") as fh:
                    head = fh.read(4)
            except OSError:
                continue
            if len(head) < 4:
                continue
            if head not in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",
                            b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
                continue
            changes = patch_macho(path, want)
            for old, new in changes or []:
                print("  patched %s: %s -> %s" % (os.path.relpath(path, app), old, new))
                total += 1
    for path, old, new in patch_plist(app, want):
        print("  plist   %s: %s -> %s" % (os.path.relpath(path, app), old, new))
        total += 1
    print("DONE: %d stamp(s) rewritten to %s" % (total, sys.argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
