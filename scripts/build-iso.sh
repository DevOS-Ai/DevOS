#!/usr/bin/env bash
# Build the DevOS live ISO (SRS OS-008, OS-009, BLD-001..005).
#
# Usage: sudo scripts/build-iso.sh [-o OUTPUT_DIR] [-w WORK_DIR] [-k]
#   -o  output directory (default: dist/)
#   -w  work directory   (default: work/iso)
#   -k  keep the work directory after the build
#
# Output: dist/devos-<VERSION>-x86_64.iso and its .sha256
#
# Needs the [devos] repository built first (scripts/build-repo.sh, as a normal user).
# Environment:
#   DEVOS_REPO_DIR  local [devos] repository (default: repo/x86_64)
#   DEVOS_REPO_URL  published [devos] URL for installed systems (optional; see OS-011)
#   DEVOS_OFFLINE   1 (default): put every package an install can need on the ISO
#                   (installer/packages.list and every developer profile)
#   DEVOS_PKG_CACHE download cache kept between builds (default: work/pkgcache)
#   DEVOS_MEDIUM_DIR staging of the files placed on the ISO next to the live system
#                   (default: work/medium; several GB, may be on another disk)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/dist"
WORK_DIR="$ROOT/work/iso"
KEEP_WORK=false

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while getopts "o:w:kh" opt; do
    case "$opt" in
        o) OUT_DIR="$(realpath -m "$OPTARG")" ;;
        w) WORK_DIR="$(realpath -m "$OPTARG")" ;;
        k) KEEP_WORK=true ;;
        *) sed -n '2,9p' "$0"; exit 1 ;;
    esac
done

(( EUID == 0 )) || die "mkarchiso needs root: run with sudo"
for cmd in mkarchiso mksquashfs grub-mkstandalone xorriso mformat mcopy; do
    command -v "$cmd" >/dev/null || die "missing '$cmd' (pacman -S archiso grub mtools)"
done
CACHE="$(realpath -m "${DEVOS_PKG_CACHE:-$ROOT/work/pkgcache}")"
MEDIUM="$(realpath -m "${DEVOS_MEDIUM_DIR:-$ROOT/work/medium}")"

DEVOS_VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"
[[ "$DEVOS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "VERSION is not SemVer: '$DEVOS_VERSION'"
export DEVOS_VERSION
# Reproducible timestamps: the last commit, not the build time (BLD-005).
SOURCE_DATE_EPOCH="$(git -c safe.directory="$ROOT" -C "$ROOT" log -1 --format=%ct 2>/dev/null || date +%s)"
export SOURCE_DATE_EPOCH

REPO_DIR="$(realpath -m "${DEVOS_REPO_DIR:-$ROOT/repo/x86_64}")"
[[ -f "$REPO_DIR/devos.db.tar.zst" ]] || die "no [devos] repository at $REPO_DIR; run scripts/build-repo.sh first"

log "Checking package lists"
"$ROOT/scripts/check-packages.sh" -r "$REPO_DIR" "$ROOT/iso/packages.x86_64"

# Stale mkarchiso state silently skips build steps, so always start clean.
rm -rf -- "$WORK_DIR"
mkdir -p -- "$WORK_DIR" "$OUT_DIR"
PROFILE="$WORK_DIR/profile"

log "Staging profile"
cp -a -- "$ROOT/iso" "$PROFILE"
# The checkout belongs to whoever built it; on the ISO these files are root's (uid 1000 is
# the live user there).
chown -R 0:0 -- "$PROFILE/airootfs"
# Theme files land in /boot/grub/themes/devos on the ISO (mkarchiso copies
# every non-.cfg file under grub/).
mkdir -p -- "$PROFILE/grub/themes"
cp -a -- "$ROOT/boot/grub/themes/devos" "$PROFILE/grub/themes/devos"
sed -i "s|%DEVOS_VERSION%|$DEVOS_VERSION|g" "$PROFILE"/grub/*.cfg "$PROFILE"/airootfs/etc/os-release "$PROFILE"/airootfs/etc/issue

# Package repositories live on the medium itself, next to the live system (not inside its
# squashfs: packages are compressed already, and the live system stays small). The live
# system reads them where archiso mounts the medium:
#   /run/archiso/bootmnt/devos/repo     [devos]
#   /run/archiso/bootmnt/devos/offline  every package an install needs, with signatures
# TODO(SEC-011): switch to SigLevel = Required once packages are signed.
LIVE_MEDIUM=/run/archiso/bootmnt/devos
DEVOS_REPO_CONF='[devos]
SigLevel = Optional TrustAll'
# Building: [devos] from the local build; downloads into the cache kept between builds
# (the host's pacman cache is reused read-only).
printf '\n%s\nServer = file://%s\n' "$DEVOS_REPO_CONF" "$REPO_DIR" >>"$PROFILE/pacman.conf"
install -d "$CACHE"
sed -i "/^\[options\]/a CacheDir = $CACHE/\nCacheDir = /var/cache/pacman/pkg/" "$PROFILE/pacman.conf"

rm -rf -- "$MEDIUM"
install -d "$MEDIUM/devos/repo" "$PROFILE/airootfs/etc/devos"
cp -- "$REPO_DIR"/devos.db* "$REPO_DIR"/devos.files* "$REPO_DIR"/*.pkg.tar.zst "$MEDIUM/devos/repo/"
{ cat "$ROOT/iso/pacman.conf"; printf '\n%s\nServer = file://%s/repo\n' "$DEVOS_REPO_CONF" "$LIVE_MEDIUM"; } \
    >"$PROFILE/airootfs/etc/pacman.conf"
[[ -n "${DEVOS_REPO_URL:-}" ]] && echo "$DEVOS_REPO_URL" >"$PROFILE/airootfs/etc/devos/repo-url"

# Offline install: every package an install can need (the base system and every developer
# profile), plus the signed official databases from the same moment, so pacman verifies
# every package offline exactly as it would online. Listed first; mirrors remain the fallback.
if [[ "${DEVOS_OFFLINE:-1}" == 1 ]]; then
    log "Building the offline package repository"
    OFF="$MEDIUM/devos/offline"
    DB="$WORK_DIR/offline-db"
    install -d "$OFF" "$DB"
    mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$ROOT/installer/packages.list" \
        | grep -v '^devos-profile-'; printf 'devos-profile-%s\n' general web backend systems ai embedded)
    pac=(pacman --noconfirm --config "$PROFILE/pacman.conf" --dbpath "$DB")
    "${pac[@]}" -Sy >/dev/null
    # Arch databases no longer embed signatures: each package needs its .sig.
    # Re-fetch cached packages whose signature download failed earlier.
    for f in "$CACHE"/*.pkg.tar.zst; do
        [[ -e "$f" && ! -e "$f.sig" ]] && rm -f -- "$f"
    done
    for attempt in 1 2 3 4 5; do
        "${pac[@]}" -Sw "${pkgs[@]}" >/dev/null && break
        (( attempt < 5 )) || die "downloading the offline packages failed"
        log "Download failed, retrying ($attempt/5)"
        sleep 5
    done
    # Copy exactly the resolved set; [devos] packages are in devos/repo already.
    while read -r repo file; do
        [[ "$repo" == devos ]] && continue
        pkg=""
        for dir in "$CACHE" /var/cache/pacman/pkg; do
            [[ -f "$dir/$file" && -f "$dir/$file.sig" ]] && { pkg="$dir/$file"; break; }
        done
        [[ -n "$pkg" ]] || die "missing $file or its signature; run the build again"
        # Hard links where the cache and the medium share a file system; copies otherwise.
        cp -l -- "$pkg" "$pkg.sig" "$OFF/" 2>/dev/null || cp -- "$pkg" "$pkg.sig" "$OFF/"
    done < <("${pac[@]}" -Sp --print-format '%r %f' "${pkgs[@]}")
    cp -- "$DB/sync/core.db" "$DB/sync/extra.db" "$OFF/"
    sed -i -e "/^\[core\]\$/a Server = file://$LIVE_MEDIUM/offline" \
           -e "/^\[extra\]\$/a Server = file://$LIVE_MEDIUM/offline" "$PROFILE/airootfs/etc/pacman.conf"
    log "Offline repository: $(find "$OFF" -name '*.pkg.tar.zst' | wc -l) packages, $(du -sh "$OFF" | cut -f1)"
fi

# mkarchiso puts only its own tree on the ISO; graft the repositories in next to it.
MKARCHISO="$WORK_DIR/mkarchiso"
# The ${…} below are mkarchiso's own variables, expanded when it runs: single quotes on purpose.
# shellcheck disable=SC2016
sed 's|^        "${isofs_dir}/"$|        -graft-points "${isofs_dir}/" "/devos/=${DEVOS_MEDIUM_DIR}/devos/"|' \
    "$(command -v mkarchiso)" >"$MKARCHISO"
# shellcheck disable=SC2016
[[ "$(grep -c '"/devos/=${DEVOS_MEDIUM_DIR}/devos/"' "$MKARCHISO")" == 1 ]] \
    || die "this mkarchiso version is not supported (could not add the repositories to the ISO)"
chmod +x "$MKARCHISO"
export DEVOS_MEDIUM_DIR="$MEDIUM"

log "Building DevOS $DEVOS_VERSION"
"$MKARCHISO" -v -w "$WORK_DIR/build" -o "$OUT_DIR" "$PROFILE"

ISO="$OUT_DIR/devos-$DEVOS_VERSION-x86_64.iso"
[[ -f "$ISO" ]] || die "expected $ISO was not produced"
(cd "$OUT_DIR" && sha256sum "$(basename "$ISO")" >"$(basename "$ISO").sha256")

# Hand the results back to the invoking user.
if [[ -n "${SUDO_UID:-}" ]]; then
    chown "$SUDO_UID:${SUDO_GID:-}" "$OUT_DIR" "$ISO" "$ISO.sha256"
fi
$KEEP_WORK || rm -rf -- "$WORK_DIR" "$MEDIUM"

log "Done: $ISO ($(du -h "$ISO" | cut -f1))"
