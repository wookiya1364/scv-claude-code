#!/usr/bin/env bash
# Resolve and maintain DeckUI's mutable runtime outside the immutable Core tree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CORE_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SOURCE_DECKUI="$CORE_DIR/DeckUI"
COMMAND="${1:-}"
LEGACY_ROOT=
REUSE_EXISTING=0

usage() {
  cat <<'EOF' >&2
Usage:
  deck-runtime.sh path
  deck-runtime.sh ensure
  deck-runtime.sh migrate --from LEGACY_DECKUI [--reuse-existing]

SCV_DECK_CACHE_DIR overrides the cache base. The selected cache is always
namespaced by the canonical Core source-payload SHA-256.
EOF
}

case "$COMMAND" in
  path|ensure)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    ;;
  migrate)
    if [[ $# -eq 3 && "$2" == "--from" ]]; then
      :
    elif [[
      $# -eq 4 &&
      "$2" == "--from" &&
      "$4" == "--reuse-existing"
    ]]; then
      REUSE_EXISTING=1
    else
      usage
      exit 2
    fi
    LEGACY_ROOT="$3"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ -n "${SCV_DECK_CACHE_DIR:-}" ]]; then
  CACHE_BASE="$SCV_DECK_CACHE_DIR"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  CACHE_BASE="$XDG_CACHE_HOME/scv/deckui"
elif [[ -n "${HOME:-}" ]]; then
  CACHE_BASE="$HOME/.cache/scv/deckui"
else
  echo "ERROR: set SCV_DECK_CACHE_DIR, XDG_CACHE_HOME, or HOME" >&2
  exit 1
fi

exec python3 - \
  "$COMMAND" "$SOURCE_DECKUI" "$CORE_DIR" "$CACHE_BASE" "$LEGACY_ROOT" \
  "$REUSE_EXISTING" <<'PY'
from __future__ import annotations

import contextlib
import ctypes
import errno
import hashlib
import json
import os
import signal
import stat
import sys
import time
import uuid
from pathlib import Path
from typing import NoReturn

(
    command,
    source_arg,
    core_arg,
    base_arg,
    legacy_arg,
    reuse_existing_arg,
) = sys.argv[1:]
source = Path(source_arg)
core = Path(core_arg)
raw_base = Path(base_arg).expanduser()
reuse_existing = reuse_existing_arg == "1"

RUNTIME_DIR_NAMES = {
    "node_modules",
    "dist",
    "dist-deck",
    ".vite",
    ".cache",
    "coverage",
}
MANAGED_DECKS = {"demo-prd", "refund"}
REUSE_EXISTING_NOTICE = (
    "NOTICE: existing Deck runtime cache differs; reusing it as "
    "authoritative and skipping this legacy migration"
)


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def _rename_noreplace(
    source_parent_fd: int,
    source_name: str,
    destination_parent_fd: int,
    destination_name: str,
) -> None:
    """Atomically move one dirfd-relative entry without replacement."""
    libc = ctypes.CDLL(None, use_errno=True)
    source = os.fsencode(source_name)
    destination = os.fsencode(destination_name)

    if sys.platform.startswith("linux"):
        operation = getattr(libc, "renameat2", None)
        if operation is None:
            fail("this Linux runtime does not provide atomic no-replace rename")
        operation.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        operation.restype = ctypes.c_int
        result = operation(
            source_parent_fd,
            source,
            destination_parent_fd,
            destination,
            1,  # RENAME_NOREPLACE
        )
    elif sys.platform == "darwin":
        operation = getattr(libc, "renameatx_np", None)
        if operation is None:
            fail("this macOS runtime does not provide atomic no-replace rename")
        operation.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        operation.restype = ctypes.c_int
        result = operation(
            source_parent_fd,
            source,
            destination_parent_fd,
            destination,
            0x00000004,  # RENAME_EXCL
        )
    else:
        fail("atomic no-replace cache installation requires Linux or macOS")

    if result == 0:
        return
    error_number = ctypes.get_errno()
    if error_number in {errno.EEXIST, errno.ENOTEMPTY}:
        raise FileExistsError(
            error_number,
            os.strerror(error_number),
            destination_name,
        )
    raise OSError(
        error_number,
        os.strerror(error_number),
        f"{source_name} -> {destination_name}",
    )


def rename_noreplace_at(
    source_parent_fd: int,
    source_name: str,
    destination_parent_fd: int,
    destination_name: str,
) -> None:
    """Atomically move between two already-open directory parents."""
    if (
        not source_name
        or source_name in {".", ".."}
        or "/" in source_name
        or not destination_name
        or destination_name in {".", ".."}
        or "/" in destination_name
    ):
        fail("unsafe dirfd-relative rename name")
    _rename_noreplace(
        source_parent_fd,
        source_name,
        destination_parent_fd,
        destination_name,
    )


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def source_payload_key() -> str:
    candidates = (
        core / "core.lock",
        core / "core.lock.json",
        core.parent / "core.lock",
        core.parent / "core.lock.json",
    )
    for candidate in candidates:
        if not candidate.exists() and not candidate.is_symlink():
            continue
        if candidate.is_symlink() or not candidate.is_file():
            fail(f"Core lock is unsafe: {candidate}")
        try:
            value = json.loads(candidate.read_text(encoding="utf-8")).get(
                "source_payload_sha256"
            )
        except (OSError, json.JSONDecodeError) as error:
            fail(f"Core lock is invalid: {candidate}: {error}")
        if not (
            isinstance(value, str)
            and len(value) == 64
            and all(character in "0123456789abcdef" for character in value)
        ):
            fail(f"Core lock has no valid source_payload_sha256: {candidate}")
        return value

    # Source checkouts have no generated core.lock. Hash only immutable DeckUI
    # inputs, pruning every runtime directory and non-sample generated deck.
    digest = hashlib.sha256()
    for current, directories, files in os.walk(source, topdown=True):
        current_path = Path(current)
        kept_directories: list[str] = []
        for name in sorted(directories):
            if name in RUNTIME_DIR_NAMES:
                continue
            path = current_path / name
            entry = path.lstat()
            if not stat.S_ISDIR(entry.st_mode):
                fail(f"immutable DeckUI source contains a link or special file: {path}")
            relative = path.relative_to(source)
            digest.update(b"D\0" + relative.as_posix().encode() + b"\0")
            kept_directories.append(name)
        directories[:] = kept_directories
        for name in sorted(files):
            if name in RUNTIME_DIR_NAMES:
                continue
            path = current_path / name
            relative = path.relative_to(source)
            if (
                len(relative.parts) == 5
                and relative.parts[:3] == ("src", "deck", "decks")
                and relative.parts[-1] == "deck.json"
                and relative.parts[-2] not in MANAGED_DECKS
            ):
                continue
            entry = path.lstat()
            if not stat.S_ISREG(entry.st_mode):
                fail(f"immutable DeckUI source contains a link or special file: {path}")
            encoded = relative.as_posix().encode()
            digest.update(encoded + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


if not source.is_dir() or source.is_symlink():
    fail(f"immutable DeckUI source is missing or unsafe: {source}")
source = source.resolve()

if not raw_base.is_absolute():
    fail("SCV Deck cache base must be an absolute path")
if raw_base.is_symlink():
    fail(f"SCV Deck cache base must not be a symlink: {raw_base}")
base = Path(os.path.abspath(os.fspath(raw_base)))
home = Path(os.environ["HOME"]).resolve() if os.environ.get("HOME") else None
if base == Path(base.anchor) or (home is not None and base == home):
    fail(f"SCV Deck cache base is too broad: {base}")
if is_relative_to(base, source) or is_relative_to(source, base):
    fail("SCV Deck cache must be outside the immutable DeckUI source")

key = source_payload_key()
namespace = base / key
target = namespace / "DeckUI"
marker_name = ".scv-deck-runtime.json"
marker = target / marker_name


def same_entry(first: os.stat_result, second: os.stat_result) -> bool:
    return (
        first.st_dev == second.st_dev
        and first.st_ino == second.st_ino
        and stat.S_IFMT(first.st_mode) == stat.S_IFMT(second.st_mode)
    )


def same_mode(first: os.stat_result, second: os.stat_result) -> bool:
    return stat.S_IMODE(first.st_mode) == stat.S_IMODE(second.st_mode)


def entry_at(parent_fd: int, name: str) -> os.stat_result | None:
    try:
        return os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None


def open_directory_at(
    parent_fd: int,
    name: str,
    label: Path | str,
) -> tuple[int, os.stat_result]:
    before = entry_at(parent_fd, name)
    if before is None or not stat.S_ISDIR(before.st_mode):
        fail(f"cache path is not an ordinary directory: {label}")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        fail(f"cannot open ordinary cache directory {label}: {error}")
    opened = os.fstat(descriptor)
    after = entry_at(parent_fd, name)
    if (
        after is None
        or not same_entry(before, opened)
        or not same_entry(before, after)
    ):
        os.close(descriptor)
        fail(f"cache directory changed while opening: {label}")
    return descriptor, opened


def open_absolute_directory(path: Path, create: bool) -> tuple[int, os.stat_result]:
    if not path.is_absolute():
        fail(f"cache path is not absolute: {path}")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path.anchor, flags)
    current = Path(path.anchor)
    try:
        for component in path.parts[1:]:
            current /= component
            before = entry_at(descriptor, component)
            if before is None:
                if not create:
                    fail(f"cache directory is missing: {current}")
                try:
                    os.mkdir(component, mode=0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
                before = entry_at(descriptor, component)
            if before is None or not stat.S_ISDIR(before.st_mode):
                fail(f"cache path is a link or non-directory: {current}")
            child, opened = open_directory_at(descriptor, component, current)
            os.close(descriptor)
            descriptor = child
        return descriptor, os.fstat(descriptor)
    except BaseException:
        os.close(descriptor)
        raise


def verify_absolute_directory(
    path: Path,
    expected: os.stat_result,
) -> None:
    descriptor, opened = open_absolute_directory(path, create=False)
    try:
        if not same_entry(expected, opened):
            fail(f"cache directory identity changed: {path}")
    finally:
        os.close(descriptor)


def ensure_directory_at(
    parent_fd: int,
    name: str,
    label: Path | str,
    mode: int = 0o700,
) -> tuple[int, os.stat_result]:
    if entry_at(parent_fd, name) is None:
        try:
            os.mkdir(name, mode=mode, dir_fd=parent_fd)
        except FileExistsError:
            pass
    return open_directory_at(parent_fd, name, label)


def open_relative_parent(
    root_fd: int,
    relative: Path,
    create: bool,
    created_directories: list[tuple[Path, os.stat_result]] | None = None,
) -> int | None:
    if relative.is_absolute() or not relative.parts:
        fail(f"unsafe cache-relative destination: {relative}")
    descriptor = os.dup(root_fd)
    try:
        for index, component in enumerate(relative.parts[:-1]):
            if component in {"", ".", ".."}:
                fail(f"unsafe cache-relative destination: {relative}")
            before = entry_at(descriptor, component)
            created_now = False
            if before is None:
                if not create:
                    os.close(descriptor)
                    return None
                try:
                    os.mkdir(component, mode=0o755, dir_fd=descriptor)
                    created_now = True
                except FileExistsError:
                    pass
                before = entry_at(descriptor, component)
            if before is None or not stat.S_ISDIR(before.st_mode):
                fail(
                    "cache destination ancestor is a link or non-directory: "
                    f"{relative.parent}"
                )
            if created_now and created_directories is not None:
                created_directories.append(
                    (Path(*relative.parts[: index + 1]), before)
                )
            child, _opened = open_directory_at(
                descriptor,
                component,
                relative.parent,
            )
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def cleanup_created_directories(
    root_fd: int,
    created_directories: list[tuple[Path, os.stat_result]],
) -> None:
    for relative, expected in reversed(created_directories):
        parent_fd = open_relative_parent(root_fd, relative, create=False)
        if parent_fd is None:
            fail(f"created cache directory disappeared: {target / relative}")
        try:
            current = entry_at(parent_fd, relative.name)
            if (
                current is None
                or not same_entry(expected, current)
                or not stat.S_ISDIR(current.st_mode)
            ):
                fail(f"created cache directory changed: {target / relative}")
            directory_fd, opened = open_directory_at(
                parent_fd,
                relative.name,
                target / relative,
            )
            try:
                if (
                    not same_entry(expected, opened)
                    or os.listdir(directory_fd)
                ):
                    fail(
                        "created cache directory is no longer empty: "
                        f"{target / relative}"
                    )
            finally:
                os.close(directory_fd)
            os.rmdir(relative.name, dir_fd=parent_fd)
        finally:
            os.close(parent_fd)
    created_directories.clear()


def read_regular_at(
    parent_fd: int,
    name: str,
    label: Path | str,
    limit: int | None = None,
) -> tuple[bytes, os.stat_result]:
    before = entry_at(parent_fd, name)
    if (
        before is None
        or not stat.S_ISREG(before.st_mode)
    ):
        fail(f"cache file is missing or unsafe: {label}")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        fail(f"cannot open cache file {label}: {error}")
    try:
        opened = os.fstat(descriptor)
        if not same_entry(before, opened) or not same_mode(before, opened):
            fail(f"cache file changed while opening: {label}")
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if limit is not None and total > limit:
                fail(f"cache file is too large: {label}")
        after_fd = os.fstat(descriptor)
        after_path = entry_at(parent_fd, name)
        if (
            after_path is None
            or not same_entry(before, after_fd)
            or not same_entry(before, after_path)
            or not same_mode(before, after_fd)
            or not same_mode(before, after_path)
            or before.st_size != after_fd.st_size
            or before.st_mtime_ns != after_fd.st_mtime_ns
        ):
            fail(f"cache file changed while reading: {label}")
        return b"".join(chunks), before
    finally:
        os.close(descriptor)


def write_regular_at(
    parent_fd: int,
    name: str,
    payload: bytes,
    mode: int,
    label: Path | str,
    on_created=None,
) -> os.stat_result:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(name, flags, 0o600, dir_fd=parent_fd)
    except OSError as error:
        fail(f"cannot create cache file {label}: {error}")
    try:
        created = os.fstat(descriptor)
        visible = entry_at(parent_fd, name)
        if visible is None or not same_entry(created, visible):
            fail(f"cache file changed after creation: {label}")
        if on_created is not None:
            on_created(created)
        offset = 0
        while offset < len(payload):
            offset += os.write(descriptor, payload[offset:])
        os.fsync(descriptor)
        # Writing can clear setuid/setgid bits. Apply the exact source mode only
        # after the payload is durable, then persist and verify that metadata.
        os.fchmod(descriptor, mode)
        os.fsync(descriptor)
        created = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    visible = entry_at(parent_fd, name)
    if visible is None or not same_entry(created, visible):
        fail(f"cache file changed after creation: {label}")
    return created


def read_link_at(parent_fd: int, name: str, label: Path | str) -> str:
    before = entry_at(parent_fd, name)
    if before is None or not stat.S_ISLNK(before.st_mode):
        fail(f"runtime link is missing or unsafe: {label}")
    value = os.readlink(name, dir_fd=parent_fd)
    after = entry_at(parent_fd, name)
    if after is None or not same_entry(before, after):
        fail(f"runtime link changed while reading: {label}")
    return value


def update_digest_record(
    digest,
    kind: bytes,
    *fields: bytes,
) -> None:
    if len(kind) != 1 or len(fields) > 255:
        fail("invalid Deck runtime digest record")
    digest.update(kind)
    digest.update(len(fields).to_bytes(1, "big"))
    for field in fields:
        digest.update(len(field).to_bytes(8, "big"))
        digest.update(field)


def entry_digest_at(parent_fd: int, name: str, label: Path | str) -> str:
    root = entry_at(parent_fd, name)
    if root is None:
        fail(f"runtime entry is missing: {label}")
    digest = hashlib.sha256()
    if stat.S_ISLNK(root.st_mode):
        update_digest_record(
            digest,
            b"L",
            os.fsencode(read_link_at(parent_fd, name, label)),
        )
        return digest.hexdigest()
    if stat.S_ISREG(root.st_mode):
        payload, metadata = read_regular_at(parent_fd, name, label)
        update_digest_record(
            digest,
            b"F",
            str(stat.S_IMODE(metadata.st_mode)).encode(),
            payload,
        )
        return digest.hexdigest()
    if not stat.S_ISDIR(root.st_mode):
        fail(f"runtime contains a special file: {label}")
    update_digest_record(
        digest,
        b"D",
        str(stat.S_IMODE(root.st_mode)).encode(),
    )
    root_fd, opened_root = open_directory_at(parent_fd, name, label)
    if not same_mode(root, opened_root):
        os.close(root_fd)
        fail(f"runtime directory mode changed while opening: {label}")

    def visit(directory_fd: int, prefix: Path) -> None:
        for child_name in sorted(os.listdir(directory_fd)):
            child = entry_at(directory_fd, child_name)
            if child is None:
                fail(f"runtime entry disappeared: {label}/{prefix}/{child_name}")
            relative = prefix / child_name
            encoded = relative.as_posix().encode()
            if stat.S_ISLNK(child.st_mode):
                update_digest_record(
                    digest,
                    b"L",
                    encoded,
                    os.fsencode(
                        read_link_at(
                            directory_fd,
                            child_name,
                            f"{label}/{relative}",
                        )
                    ),
                )
            elif stat.S_ISDIR(child.st_mode):
                update_digest_record(
                    digest,
                    b"D",
                    encoded,
                    str(stat.S_IMODE(child.st_mode)).encode(),
                )
                child_fd, opened_child = open_directory_at(
                    directory_fd,
                    child_name,
                    f"{label}/{relative}",
                )
                try:
                    if not same_mode(child, opened_child):
                        fail(
                            "runtime directory mode changed while opening: "
                            f"{label}/{relative}"
                        )
                    visit(child_fd, relative)
                    after_fd = os.fstat(child_fd)
                    after_path = entry_at(directory_fd, child_name)
                    if (
                        after_path is None
                        or not same_entry(child, after_fd)
                        or not same_entry(child, after_path)
                        or not same_mode(child, after_fd)
                        or not same_mode(child, after_path)
                    ):
                        fail(
                            "runtime directory changed while reading: "
                            f"{label}/{relative}"
                        )
                finally:
                    os.close(child_fd)
            elif stat.S_ISREG(child.st_mode):
                payload, metadata = read_regular_at(
                    directory_fd,
                    child_name,
                    f"{label}/{relative}",
                )
                update_digest_record(
                    digest,
                    b"F",
                    encoded,
                    str(stat.S_IMODE(metadata.st_mode)).encode(),
                    payload,
                )
            else:
                fail(f"runtime contains a special file: {label}/{relative}")

    try:
        visit(root_fd, Path())
        after_root_fd = os.fstat(root_fd)
        after_root_path = entry_at(parent_fd, name)
        if (
            after_root_path is None
            or not same_entry(root, after_root_fd)
            or not same_entry(root, after_root_path)
            or not same_mode(root, after_root_fd)
            or not same_mode(root, after_root_path)
        ):
            fail(f"runtime directory changed while reading: {label}")
    finally:
        os.close(root_fd)
    return digest.hexdigest()


def open_path_entry_parent(path: Path) -> tuple[int, str]:
    parent, _metadata = open_absolute_directory(path.parent, create=False)
    return parent, path.name


def path_entry_digest(path: Path) -> str:
    parent_fd, name = open_path_entry_parent(path)
    try:
        return entry_digest_at(parent_fd, name, path)
    finally:
        os.close(parent_fd)


def copy_file_between(
    source_parent_fd: int,
    source_name: str,
    destination_parent_fd: int,
    destination_name: str,
    label: Path | str,
    on_created=None,
) -> os.stat_result:
    payload, metadata = read_regular_at(
        source_parent_fd,
        source_name,
        label,
    )
    return write_regular_at(
        destination_parent_fd,
        destination_name,
        payload,
        stat.S_IMODE(metadata.st_mode),
        label,
        on_created,
    )


def copy_entry_between(
    source_parent_fd: int,
    source_name: str,
    destination_parent_fd: int,
    destination_name: str,
    label: Path | str,
    *,
    source_relative: Path | None = None,
    immutable_source: bool = False,
    on_created=None,
) -> None:
    metadata = entry_at(source_parent_fd, source_name)
    if metadata is None:
        fail(f"runtime source disappeared: {label}")
    if stat.S_ISLNK(metadata.st_mode):
        if immutable_source:
            fail(f"immutable DeckUI source contains a link: {label}")
        os.symlink(
            read_link_at(source_parent_fd, source_name, label),
            destination_name,
            dir_fd=destination_parent_fd,
        )
        created = entry_at(destination_parent_fd, destination_name)
        if created is None or not stat.S_ISLNK(created.st_mode):
            fail(f"runtime staging link changed after creation: {label}")
        if on_created is not None:
            on_created(created)
        return
    if stat.S_ISREG(metadata.st_mode):
        copy_file_between(
            source_parent_fd,
            source_name,
            destination_parent_fd,
            destination_name,
            label,
            on_created,
        )
        return
    if not stat.S_ISDIR(metadata.st_mode):
        fail(f"runtime source contains a special file: {label}")
    os.mkdir(
        destination_name,
        mode=0o700,
        dir_fd=destination_parent_fd,
    )
    created = entry_at(destination_parent_fd, destination_name)
    if created is None or not stat.S_ISDIR(created.st_mode):
        fail(f"runtime staging directory changed after creation: {label}")
    if on_created is not None:
        on_created(created)
    source_fd, source_opened = open_directory_at(
        source_parent_fd,
        source_name,
        label,
    )
    destination_fd, _destination_opened = open_directory_at(
        destination_parent_fd,
        destination_name,
        label,
    )
    try:
        relative_root = source_relative or Path()
        for child_name in sorted(os.listdir(source_fd)):
            child_relative = relative_root / child_name
            if immutable_source:
                if child_name in RUNTIME_DIR_NAMES:
                    continue
                if (
                    len(child_relative.parts) == 5
                    and child_relative.parts[:3]
                    == ("src", "deck", "decks")
                    and child_relative.parts[-1] == "deck.json"
                    and child_relative.parts[-2] not in MANAGED_DECKS
                ):
                    continue
            copy_entry_between(
                source_fd,
                child_name,
                destination_fd,
                child_name,
                f"{label}/{child_name}",
                source_relative=child_relative,
                immutable_source=immutable_source,
            )
        if not same_entry(source_opened, os.fstat(source_fd)):
            fail(f"runtime source changed while copying: {label}")
        os.fchmod(destination_fd, stat.S_IMODE(metadata.st_mode))
    finally:
        os.close(destination_fd)
        os.close(source_fd)


def remove_owned_tree_at(
    parent_fd: int,
    name: str,
    expected: os.stat_result,
    label: Path | str,
) -> None:
    current = entry_at(parent_fd, name)
    if current is None:
        return
    if not same_entry(expected, current) or not stat.S_ISDIR(current.st_mode):
        fail(f"refusing to clean changed cache staging directory: {label}")
    directory_fd, opened = open_directory_at(parent_fd, name, label)
    try:
        if not same_entry(expected, opened):
            fail(f"cache staging directory changed: {label}")
        os.fchmod(directory_fd, 0o700)
        for child_name in sorted(os.listdir(directory_fd)):
            child = entry_at(directory_fd, child_name)
            if child is None:
                fail(f"cache staging entry changed: {label}/{child_name}")
            if stat.S_ISDIR(child.st_mode):
                remove_owned_tree_at(
                    directory_fd,
                    child_name,
                    child,
                    f"{label}/{child_name}",
                )
            else:
                before = entry_at(directory_fd, child_name)
                if before is None or not same_entry(child, before):
                    fail(f"cache staging entry changed: {label}/{child_name}")
                os.unlink(child_name, dir_fd=directory_fd)
        current = entry_at(parent_fd, name)
        if current is None or not same_entry(expected, current):
            fail(f"cache staging directory changed: {label}")
        os.rmdir(name, dir_fd=parent_fd)
    finally:
        os.close(directory_fd)


def validate_target_at(
    namespace_fd: int,
) -> tuple[int, os.stat_result] | None:
    target_entry = entry_at(namespace_fd, "DeckUI")
    if target_entry is None:
        return None
    if not stat.S_ISDIR(target_entry.st_mode):
        fail(f"SCV Deck runtime target is unsafe: {target}")
    target_fd, opened = open_directory_at(namespace_fd, "DeckUI", target)
    try:
        marker_entry = entry_at(target_fd, marker_name)
        if marker_entry is None or marker_entry.st_nlink != 1:
            fail(f"SCV Deck runtime marker is missing or unsafe: {marker}")
        payload, _marker_entry = read_regular_at(
            target_fd,
            marker_name,
            marker,
            limit=64 * 1024,
        )
        try:
            metadata = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            fail(f"SCV Deck runtime marker is invalid: {error}")
        if (
            not isinstance(metadata, dict)
            or metadata.get("source_payload_sha256") != key
        ):
            fail(
                "SCV Deck runtime marker does not match the selected "
                "Core payload"
            )
        current = entry_at(namespace_fd, "DeckUI")
        if current is None or not same_entry(opened, current):
            fail(f"SCV Deck runtime target changed while validating: {target}")
        return target_fd, opened
    except BaseException:
        os.close(target_fd)
        raise


def process_is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


class RetryableLockRace(Exception):
    """An ordinary existing lock disappeared or changed during handoff."""


def open_lock_directory(
    base_fd: int,
    lock_name: str,
    *,
    pause_before_open: bool = True,
    retry_on_change: bool = False,
) -> tuple[int, os.stat_result]:
    before = entry_at(base_fd, lock_name)
    if before is None:
        if retry_on_change:
            raise RetryableLockRace(lock_name)
        fail(f"SCV Deck runtime lock disappeared: {base / lock_name}")
    if not stat.S_ISDIR(before.st_mode):
        fail(f"SCV Deck runtime lock is unsafe: {base / lock_name}")
    if pause_before_open:
        runtime_test_pause("lock-before-open", lock_name)
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(lock_name, flags, dir_fd=base_fd)
    except OSError as error:
        current = entry_at(base_fd, lock_name)
        if current is not None and not stat.S_ISDIR(current.st_mode):
            fail(f"SCV Deck runtime lock is unsafe: {base / lock_name}")
        if retry_on_change and (
            (error.errno == errno.ENOENT and current is None)
            or (
                current is not None
                and not same_entry(before, current)
            )
        ):
            raise RetryableLockRace(lock_name) from error
        fail(f"cannot open SCV Deck runtime lock safely: {error}")
    opened = os.fstat(descriptor)
    after = entry_at(base_fd, lock_name)
    if after is None or not same_entry(before, opened) or not same_entry(
        before,
        after,
    ):
        os.close(descriptor)
        if retry_on_change and (
            after is None
            or (
                stat.S_ISDIR(after.st_mode)
                and not same_entry(before, after)
            )
        ):
            raise RetryableLockRace(lock_name)
        fail(f"SCV Deck runtime lock changed while opening: {base / lock_name}")
    return descriptor, opened


def read_lock_owner(lock_fd: int) -> tuple[dict[str, object], os.stat_result]:
    try:
        names = sorted(os.listdir(lock_fd))
    except OSError as error:
        raise ValueError(f"cannot list lock: {error}") from error
    if names != ["owner.json"]:
        raise ValueError("unexpected lock entries")
    try:
        before = os.stat("owner.json", dir_fd=lock_fd, follow_symlinks=False)
    except OSError as error:
        raise ValueError(f"cannot inspect lock owner: {error}") from error
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError("unsafe lock owner")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        owner_fd = os.open("owner.json", flags, dir_fd=lock_fd)
    except OSError as error:
        raise ValueError(f"cannot open lock owner: {error}") from error
    try:
        opened = os.fstat(owner_fd)
        if not same_entry(before, opened):
            raise ValueError("lock owner changed while opening")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(owner_fd, 4096)
            if not chunk:
                break
            chunks.append(chunk)
            if sum(len(item) for item in chunks) > 4096:
                raise ValueError("lock owner is too large")
        after_open = os.fstat(owner_fd)
        after_path = os.stat(
            "owner.json",
            dir_fd=lock_fd,
            follow_symlinks=False,
        )
        if (
            not same_entry(before, after_open)
            or not same_entry(before, after_path)
            or before.st_size != after_open.st_size
            or before.st_mtime_ns != after_open.st_mtime_ns
        ):
            raise ValueError("lock owner changed while reading")
        try:
            data = json.loads(b"".join(chunks).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError("invalid lock owner JSON") from error
    finally:
        os.close(owner_fd)
    if not isinstance(data, dict):
        raise ValueError("invalid lock owner")
    try:
        raw_pid = data["pid"]
        owner_token = data["token"]
    except KeyError as error:
        raise ValueError("invalid lock owner") from error
    if (
        set(data) != {"pid", "token"}
        or type(raw_pid) is not int
        or raw_pid <= 0
        or not isinstance(owner_token, str)
        or len(owner_token) != 32
        or any(
            character not in "0123456789abcdef"
            for character in owner_token
        )
    ):
        raise ValueError("invalid lock owner")
    return {"pid": raw_pid, "token": owner_token}, before


def write_lock_owner(lock_fd: int, token: str) -> os.stat_result:
    payload = (
        json.dumps(
            {"pid": os.getpid(), "token": token},
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
    owner_fd = os.open("owner.json", flags, 0o600, dir_fd=lock_fd)
    try:
        os.fchmod(owner_fd, 0o600)
        offset = 0
        while offset < len(payload):
            offset += os.write(owner_fd, payload[offset:])
        os.fsync(owner_fd)
        created = os.fstat(owner_fd)
    finally:
        os.close(owner_fd)
    visible = entry_at(lock_fd, "owner.json")
    if visible is None or not same_entry(created, visible):
        fail("SCV Deck runtime lock owner changed after creation")
    return created


def remove_lock_directory(
    parent_fd: int,
    name: str,
    expected_directory: os.stat_result,
    lock_fd: int,
    expected_owner: os.stat_result,
    label: Path | str,
) -> None:
    current_directory = entry_at(parent_fd, name)
    if (
        current_directory is None
        or not same_entry(expected_directory, current_directory)
        or not same_entry(expected_directory, os.fstat(lock_fd))
    ):
        fail(f"SCV Deck runtime lock changed before cleanup: {label}")
    if sorted(os.listdir(lock_fd)) != ["owner.json"]:
        fail(f"SCV Deck runtime lock has unexpected data: {label}")
    current_owner = entry_at(lock_fd, "owner.json")
    if (
        current_owner is None
        or not same_entry(expected_owner, current_owner)
    ):
        fail(f"SCV Deck runtime lock owner changed before cleanup: {label}")
    os.unlink("owner.json", dir_fd=lock_fd)
    if os.listdir(lock_fd):
        fail(f"SCV Deck runtime lock changed during cleanup: {label}")
    current_directory = entry_at(parent_fd, name)
    if (
        current_directory is None
        or not same_entry(expected_directory, current_directory)
    ):
        fail(f"SCV Deck runtime lock changed during cleanup: {label}")
    os.rmdir(name, dir_fd=parent_fd)


def remove_empty_lock_candidate(
    parent_fd: int,
    name: str,
    expected_directory: os.stat_result,
    label: Path | str,
) -> None:
    current = entry_at(parent_fd, name)
    if current is None:
        return
    if not same_entry(expected_directory, current):
        fail(f"SCV Deck runtime lock candidate changed: {label}")
    descriptor, opened = open_lock_directory(
        parent_fd,
        name,
        pause_before_open=False,
    )
    try:
        if not same_entry(expected_directory, opened) or os.listdir(
            descriptor
        ):
            fail(f"SCV Deck runtime lock candidate has external data: {label}")
        os.rmdir(name, dir_fd=parent_fd)
    finally:
        os.close(descriptor)


def runtime_test_pause(point: str, detail: str = "") -> None:
    if os.environ.get("SCV_DECK_RUNTIME_TEST_PAUSE") != point:
        return
    ready_value = os.environ.get("SCV_DECK_RUNTIME_TEST_READY_FILE", "")
    continue_value = os.environ.get(
        "SCV_DECK_RUNTIME_TEST_CONTINUE_FILE",
        "",
    )
    if not ready_value or not continue_value:
        fail("Deck runtime lock test pause requires ready and continue files")
    ready = Path(ready_value)
    proceed = Path(continue_value)
    ready.write_text(detail + "\n", encoding="utf-8")
    deadline = time.monotonic() + 30
    while not proceed.exists():
        if time.monotonic() >= deadline:
            fail(f"timed out at Deck runtime test pause: {point}")
        time.sleep(0.02)


def runtime_test_fail(point: str) -> None:
    if os.environ.get("SCV_DECK_RUNTIME_TEST_FAIL") == point:
        fail(f"injected Deck runtime failure: {point}")


class RuntimeSignal(BaseException):
    def __init__(self, signum: int) -> None:
        super().__init__(signum)
        self.signum = signum


@contextlib.contextmanager
def catch_runtime_signals():
    handled = (
        signal.SIGINT,
        signal.SIGTERM,
        signal.SIGHUP,
        signal.SIGQUIT,
    )
    previous = {
        signum: signal.getsignal(signum)
        for signum in handled
    }

    def raise_signal(signum: int, _frame: object) -> None:
        raise RuntimeSignal(signum)

    try:
        for signum in handled:
            signal.signal(signum, raise_signal)
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


class RuntimeContext:
    def __init__(
        self,
        base_fd: int,
        base_entry: os.stat_result,
        namespace_fd: int,
        namespace_entry: os.stat_result,
    ) -> None:
        self.base_fd = base_fd
        self.base_entry = base_entry
        self.namespace_fd = namespace_fd
        self.namespace_entry = namespace_entry
        self.target_entry: os.stat_result | None = None

    def register_target(self, target_entry: os.stat_result) -> None:
        self.target_entry = target_entry

    def verify_visible(self) -> None:
        verify_absolute_directory(base, self.base_entry)
        visible_namespace = entry_at(self.base_fd, key)
        if (
            visible_namespace is None
            or not same_entry(self.namespace_entry, visible_namespace)
            or not same_entry(
                self.namespace_entry,
                os.fstat(self.namespace_fd),
            )
        ):
            fail(f"SCV Deck cache namespace identity changed: {namespace}")
        if self.target_entry is not None:
            visible_target = entry_at(self.namespace_fd, "DeckUI")
            if (
                visible_target is None
                or not same_entry(self.target_entry, visible_target)
            ):
                fail(f"SCV Deck runtime target identity changed: {target}")


def create_lock_candidate(
    base_fd: int,
    lock_name: str,
    token: str,
) -> tuple[str, int, os.stat_result, os.stat_result]:
    candidate_name = f"{lock_name}.new-{uuid.uuid4().hex}"
    os.mkdir(candidate_name, mode=0o700, dir_fd=base_fd)
    candidate_entry = entry_at(base_fd, candidate_name)
    if candidate_entry is None or not stat.S_ISDIR(candidate_entry.st_mode):
        fail("SCV Deck runtime lock candidate was not created safely")
    try:
        runtime_test_pause("candidate-before-open", candidate_name)
        candidate_fd, opened = open_lock_directory(
            base_fd,
            candidate_name,
            pause_before_open=False,
        )
    except BaseException:
        current = entry_at(base_fd, candidate_name)
        if current is not None and same_entry(candidate_entry, current):
            remove_empty_lock_candidate(
                base_fd,
                candidate_name,
                candidate_entry,
                base / candidate_name,
            )
        raise
    owner_entry: os.stat_result | None = None
    try:
        if not same_entry(candidate_entry, opened):
            fail("SCV Deck runtime lock candidate changed while opening")
        os.fchmod(candidate_fd, 0o700)
        candidate_entry = os.fstat(candidate_fd)
        current_candidate = entry_at(base_fd, candidate_name)
        if (
            current_candidate is None
            or not same_entry(candidate_entry, current_candidate)
        ):
            fail("SCV Deck runtime lock candidate changed after chmod")
        owner_entry = write_lock_owner(candidate_fd, token)
        data, verified_owner = read_lock_owner(candidate_fd)
        if data.get("pid") != os.getpid() or data.get("token") != token:
            fail("SCV Deck runtime lock candidate ownership changed")
        if not same_entry(owner_entry, verified_owner):
            fail("SCV Deck runtime lock candidate owner changed")
        return (
            candidate_name,
            candidate_fd,
            candidate_entry,
            owner_entry,
        )
    except BaseException:
        try:
            current = entry_at(base_fd, candidate_name)
            owner = entry_at(candidate_fd, "owner.json")
            if (
                owner_entry is not None
                and current is not None
                and same_entry(candidate_entry, current)
                and owner is not None
                and same_entry(owner_entry, owner)
                and sorted(os.listdir(candidate_fd)) == ["owner.json"]
            ):
                remove_lock_directory(
                    base_fd,
                    candidate_name,
                    candidate_entry,
                    candidate_fd,
                    owner_entry,
                    base / candidate_name,
                )
            elif (
                current is not None
                and same_entry(candidate_entry, current)
                and not os.listdir(candidate_fd)
            ):
                os.rmdir(candidate_name, dir_fd=base_fd)
        finally:
            os.close(candidate_fd)
        raise


@contextlib.contextmanager
def runtime_lock():
    lock_name = f".{key}.lock"
    lock = base / lock_name
    token = uuid.uuid4().hex
    deadline = time.monotonic() + 30
    base_fd, base_entry = open_absolute_directory(base, create=True)
    runtime_test_pause("base-opened", os.fspath(base))
    namespace_fd, namespace_entry = ensure_directory_at(
        base_fd,
        key,
        namespace,
    )
    runtime_test_pause("namespace-opened", key)
    context = RuntimeContext(
        base_fd,
        base_entry,
        namespace_fd,
        namespace_entry,
    )
    owned_lock_fd: int | None = None
    owned_lock_entry: os.stat_result | None = None
    owned_owner_entry: os.stat_result | None = None
    try:
        while time.monotonic() < deadline:
            (
                candidate_name,
                candidate_fd,
                candidate_entry,
                candidate_owner_entry,
            ) = create_lock_candidate(base_fd, lock_name, token)
            try:
                rename_noreplace_at(
                    base_fd,
                    candidate_name,
                    base_fd,
                    lock_name,
                )
            except FileExistsError:
                current_candidate = entry_at(base_fd, candidate_name)
                if (
                    current_candidate is not None
                    and same_entry(candidate_entry, current_candidate)
                ):
                    remove_lock_directory(
                        base_fd,
                        candidate_name,
                        candidate_entry,
                        candidate_fd,
                        candidate_owner_entry,
                        base / candidate_name,
                    )
                os.close(candidate_fd)
                try:
                    lock_fd, lock_entry = open_lock_directory(
                        base_fd,
                        lock_name,
                        retry_on_change=True,
                    )
                except RetryableLockRace:
                    time.sleep(0.05)
                    continue
                try:
                    try:
                        data, stale_owner_before = read_lock_owner(lock_fd)
                    except ValueError:
                        # Compatibility with an older creator that may be
                        # between mkdir and owner write.
                        if time.time() - lock_entry.st_mtime < 5:
                            time.sleep(0.05)
                            continue
                        fail(
                            "SCV Deck runtime lock metadata is malformed: "
                            f"{lock}"
                        )
                    pid = int(data["pid"])
                    if process_is_alive(pid):
                        time.sleep(0.05)
                        continue
                    quarantine_name = f".{key}.stale-{uuid.uuid4().hex}"
                    runtime_test_pause(
                        "stale-before-rename",
                        quarantine_name,
                    )
                    try:
                        rename_noreplace_at(
                            base_fd,
                            lock_name,
                            base_fd,
                            quarantine_name,
                        )
                    except (
                        FileNotFoundError,
                        FileExistsError,
                        OSError,
                    ):
                        time.sleep(0.05)
                        continue
                    quarantine_entry = entry_at(
                        base_fd,
                        quarantine_name,
                    )
                    if (
                        quarantine_entry is None
                        or not same_entry(lock_entry, quarantine_entry)
                        or not same_entry(lock_entry, os.fstat(lock_fd))
                    ):
                        fail(
                            "stale SCV Deck runtime lock changed during "
                            f"quarantine: {base / quarantine_name}"
                        )
                    stale_data, stale_owner_after = read_lock_owner(lock_fd)
                    if (
                        stale_data.get("pid") != pid
                        or stale_data.get("token") != data.get("token")
                        or process_is_alive(pid)
                        or not same_entry(
                            stale_owner_before,
                            stale_owner_after,
                        )
                    ):
                        fail(
                            "stale SCV Deck runtime lock ownership changed "
                            f"during quarantine: {base / quarantine_name}"
                        )
                    remove_lock_directory(
                        base_fd,
                        quarantine_name,
                        lock_entry,
                        lock_fd,
                        stale_owner_after,
                        base / quarantine_name,
                    )
                finally:
                    os.close(lock_fd)
                continue
            except BaseException:
                current_candidate = entry_at(base_fd, candidate_name)
                if (
                    current_candidate is not None
                    and same_entry(candidate_entry, current_candidate)
                ):
                    remove_lock_directory(
                        base_fd,
                        candidate_name,
                        candidate_entry,
                        candidate_fd,
                        candidate_owner_entry,
                        base / candidate_name,
                    )
                os.close(candidate_fd)
                raise
            try:
                runtime_test_pause("acquire-before-open", lock_name)
                reopened_lock_fd, reopened_lock_entry = open_lock_directory(
                    base_fd,
                    lock_name,
                    pause_before_open=False,
                )
            except BaseException:
                current_lock = entry_at(base_fd, lock_name)
                if (
                    current_lock is not None
                    and same_entry(candidate_entry, current_lock)
                ):
                    remove_lock_directory(
                        base_fd,
                        lock_name,
                        candidate_entry,
                        candidate_fd,
                        candidate_owner_entry,
                        lock,
                    )
                os.close(candidate_fd)
                raise
            if not same_entry(candidate_entry, reopened_lock_entry):
                os.close(reopened_lock_fd)
                os.close(candidate_fd)
                fail(
                    "SCV Deck runtime lock changed while reopening after "
                    f"atomic installation: {lock}"
                )
            os.close(candidate_fd)
            owned_lock_fd = reopened_lock_fd
            owned_lock_entry = reopened_lock_entry
            owned_owner_entry = candidate_owner_entry
            current = entry_at(base_fd, lock_name)
            if (
                current is None
                or not same_entry(owned_lock_entry, current)
                or not same_entry(
                    owned_lock_entry,
                    os.fstat(owned_lock_fd),
                )
            ):
                fail(
                    "SCV Deck runtime lock changed during acquisition: "
                    f"{lock}"
                )
            break
        if (
            owned_lock_fd is None
            or owned_lock_entry is None
            or owned_owner_entry is None
        ):
            fail("timed out waiting for the SCV Deck runtime lock")

        try:
            runtime_test_pause("locked-before-operation", lock_name)
            yield context
            context.verify_visible()
        finally:
            runtime_test_pause("release-before-delete", lock_name)
            current = entry_at(base_fd, lock_name)
            if (
                current is None
                or not same_entry(owned_lock_entry, current)
                or not same_entry(
                    owned_lock_entry,
                    os.fstat(owned_lock_fd),
                )
            ):
                fail(f"SCV Deck runtime lock ownership changed: {lock}")
            try:
                data, owner_entry = read_lock_owner(owned_lock_fd)
            except ValueError:
                data = {}
                owner_entry = None
            if (
                data.get("pid") != os.getpid()
                or data.get("token") != token
                or owner_entry is None
                or not same_entry(owned_owner_entry, owner_entry)
            ):
                fail(f"SCV Deck runtime lock ownership changed: {lock}")
            remove_lock_directory(
                base_fd,
                lock_name,
                owned_lock_entry,
                owned_lock_fd,
                owner_entry,
                lock,
            )
            # The release pause is an adversarial boundary too. Revalidate
            # every visible cache identity after the lock has been removed,
            # before the caller is allowed to print a usable target path.
            context.verify_visible()
    finally:
        if owned_lock_fd is not None:
            os.close(owned_lock_fd)
        os.close(namespace_fd)
        os.close(base_fd)


def cleanup_owned_entry_at(
    parent_fd: int,
    name: str,
    expected: os.stat_result,
    label: Path | str,
) -> None:
    current = entry_at(parent_fd, name)
    if current is None:
        return
    if not same_entry(expected, current):
        fail(f"refusing to clean changed cache staging entry: {label}")
    if stat.S_ISDIR(current.st_mode):
        remove_owned_tree_at(parent_fd, name, expected, label)
    else:
        os.unlink(name, dir_fd=parent_fd)


def relative_entry_digest(
    root_fd: int,
    relative: Path,
) -> str | None:
    parent_fd = open_relative_parent(root_fd, relative, create=False)
    if parent_fd is None:
        return None
    try:
        if entry_at(parent_fd, relative.name) is None:
            return None
        return entry_digest_at(
            parent_fd,
            relative.name,
            target / relative,
        )
    finally:
        os.close(parent_fd)


def ensure_locked(
    context: RuntimeContext,
) -> tuple[int, os.stat_result]:
    existing = validate_target_at(context.namespace_fd)
    if existing is not None:
        target_fd, target_entry = existing
        context.register_target(target_entry)
        runtime_test_pause("target-opened", "DeckUI")
        return target_fd, target_entry

    stage_name = f".DeckUI.stage-{uuid.uuid4().hex}"
    source_parent_fd, source_name = open_path_entry_parent(source)
    stage_entries: list[os.stat_result] = []

    def record_stage(created: os.stat_result) -> None:
        if stage_entries:
            fail("SCV Deck runtime stage identity was recorded twice")
        stage_entries.append(created)
        runtime_test_fail("ensure-stage-created")

    try:
        copy_entry_between(
            source_parent_fd,
            source_name,
            context.namespace_fd,
            stage_name,
            source,
            source_relative=Path(),
            immutable_source=True,
            on_created=record_stage,
        )
        stage_entry = stage_entries[0] if stage_entries else None
        if stage_entry is None or not stat.S_ISDIR(stage_entry.st_mode):
            fail("SCV Deck runtime staging directory is unsafe")
        stage_fd, opened_stage = open_directory_at(
            context.namespace_fd,
            stage_name,
            namespace / stage_name,
        )
        try:
            if not same_entry(stage_entry, opened_stage):
                fail("SCV Deck runtime staging directory changed")
            marker_payload = (
                json.dumps(
                    {
                        "schema_version": 1,
                        "source_payload_sha256": key,
                        "source": str(source),
                    },
                    indent=2,
                )
                + "\n"
            ).encode("utf-8")
            write_regular_at(
                stage_fd,
                marker_name,
                marker_payload,
                0o600,
                namespace / stage_name / marker_name,
            )
            os.fsync(stage_fd)
        finally:
            os.close(stage_fd)
        try:
            rename_noreplace_at(
                context.namespace_fd,
                stage_name,
                context.namespace_fd,
                "DeckUI",
            )
        except FileExistsError:
            pass
        result = validate_target_at(context.namespace_fd)
        if result is None:
            fail(
                "SCV Deck runtime target disappeared during initialization: "
                f"{target}"
            )
        target_fd, target_entry = result
        context.register_target(target_entry)
        runtime_test_pause("target-opened", "DeckUI")
        return target_fd, target_entry
    finally:
        os.close(source_parent_fd)
        if stage_entries:
            cleanup_owned_entry_at(
                context.namespace_fd,
                stage_name,
                stage_entries[0],
                namespace / stage_name,
            )


def copy_runtime_entry(
    context: RuntimeContext,
    target_fd: int,
    source_entry: Path,
    destination: Path,
    expected_source_digest: str,
    expected_destination_digest: str | None,
) -> None:
    source_digest = path_entry_digest(source_entry)
    if source_digest != expected_source_digest:
        fail(
            "legacy Deck runtime changed after migration preflight: "
            f"{source_entry}"
        )
    existing_digest = relative_entry_digest(target_fd, destination)
    if existing_digest != expected_destination_digest:
        fail(
            "Deck runtime cache changed after migration preflight: "
            f"{target / destination}"
        )
    if existing_digest is not None:
        if source_digest != existing_digest:
            fail(f"Deck runtime migration collision: {target / destination}")
        return

    source_parent_fd, source_name = open_path_entry_parent(source_entry)
    stage_name = f".{destination.name}.stage-{uuid.uuid4().hex}"
    stage_entries: list[os.stat_result] = []
    install_stage_name: str | None = None
    install_stage_entries: list[os.stat_result] = []
    created_directories: list[tuple[Path, os.stat_result]] = []
    destination_parent_fd: int | None = None
    keep_created_directories = False

    def record_stage(created: os.stat_result) -> None:
        if stage_entries:
            fail("Deck runtime migration stage identity was recorded twice")
        stage_entries.append(created)
        runtime_test_fail("migrate-stage-created")

    try:
        copy_entry_between(
            source_parent_fd,
            source_name,
            context.namespace_fd,
            stage_name,
            source_entry,
            on_created=record_stage,
        )
        stage_entry = stage_entries[0] if stage_entries else None
        if stage_entry is None:
            fail(f"Deck runtime migration staging disappeared: {source_entry}")
        staged_root = entry_at(context.namespace_fd, stage_name)
        if staged_root is None or not same_entry(stage_entry, staged_root):
            fail(f"Deck runtime migration staging changed: {source_entry}")
        if entry_digest_at(
            context.namespace_fd,
            stage_name,
            namespace / stage_name,
        ) != source_digest:
            fail(f"Deck runtime migration copy changed: {source_entry}")
        if path_entry_digest(source_entry) != source_digest:
            fail(f"legacy Deck runtime changed while copying: {source_entry}")
        destination_parent_fd = open_relative_parent(
            target_fd,
            destination,
            create=True,
            created_directories=created_directories,
        )
        if destination_parent_fd is None:
            fail(
                f"cannot open cache destination parent: "
                f"{target / destination}"
            )
        runtime_test_fail("migrate-parent-created")
        install_parent_fd = context.namespace_fd
        install_name = stage_name
        if (
            stat.S_ISDIR(staged_root.st_mode)
            and not staged_root.st_mode & stat.S_IWUSR
        ):
            # Linux requires write permission on a moved directory when its
            # parent changes (the `..` entry changes). Preserve exact read-only
            # modes by cloning the already-verified stage into the destination
            # parent and performing the final no-replace rename there.
            install_stage_name = (
                f".{destination.name}.install-{uuid.uuid4().hex}"
            )

            def record_install_stage(created: os.stat_result) -> None:
                if install_stage_entries:
                    fail(
                        "Deck runtime install stage identity was "
                        "recorded twice"
                    )
                install_stage_entries.append(created)
                runtime_test_fail("migrate-install-stage-created")

            copy_entry_between(
                context.namespace_fd,
                stage_name,
                destination_parent_fd,
                install_stage_name,
                target / destination.parent / install_stage_name,
                on_created=record_install_stage,
            )
            install_stage_entry = (
                install_stage_entries[0] if install_stage_entries else None
            )
            if install_stage_entry is None:
                fail(
                    "Deck runtime migration install staging disappeared: "
                    f"{source_entry}"
                )
            if entry_digest_at(
                destination_parent_fd,
                install_stage_name,
                target / destination.parent / install_stage_name,
            ) != source_digest:
                fail(
                    "Deck runtime migration install copy changed: "
                    f"{source_entry}"
                )
            install_parent_fd = destination_parent_fd
            install_name = install_stage_name
        try:
            rename_noreplace_at(
                install_parent_fd,
                install_name,
                destination_parent_fd,
                destination.name,
            )
            keep_created_directories = True
        except FileExistsError:
            keep_created_directories = True
            fail(
                "Deck runtime cache changed after migration preflight: "
                f"{target / destination}"
            )
    finally:
        os.close(source_parent_fd)
        try:
            if (
                destination_parent_fd is not None
                and install_stage_name is not None
                and install_stage_entries
            ):
                cleanup_owned_entry_at(
                    destination_parent_fd,
                    install_stage_name,
                    install_stage_entries[0],
                    target / destination.parent / install_stage_name,
                )
        finally:
            if destination_parent_fd is not None:
                os.close(destination_parent_fd)
            try:
                if stage_entries:
                    cleanup_owned_entry_at(
                        context.namespace_fd,
                        stage_name,
                        stage_entries[0],
                        namespace / stage_name,
                    )
            finally:
                if created_directories and not keep_created_directories:
                    cleanup_created_directories(
                        target_fd,
                        created_directories,
                    )


def resolve_legacy_root(legacy_arg: str) -> Path:
    legacy_raw = Path(legacy_arg).expanduser()
    if legacy_raw.is_symlink() or not legacy_raw.is_dir():
        fail(f"legacy DeckUI path is missing or unsafe: {legacy_raw}")
    legacy = legacy_raw.resolve()
    resolved_target = target.resolve(strict=False)
    if legacy == resolved_target:
        return legacy
    if is_relative_to(resolved_target, legacy) or is_relative_to(
        legacy, resolved_target
    ):
        fail("legacy DeckUI and the selected runtime cache must not overlap")
    return legacy


def migration_entries(legacy: Path) -> list[tuple[Path, Path]]:
    entries: list[tuple[Path, Path]] = []
    for relative in (
        Path("node_modules"),
        Path("scripts/deckdoc/node_modules"),
        Path("dist-deck"),
    ):
        source_entry = legacy / relative
        if source_entry.exists() or source_entry.is_symlink():
            entries.append((source_entry, relative))
    decks = legacy / "src/deck/decks"
    if decks.is_dir() and not decks.is_symlink():
        for deck_directory in sorted(decks.iterdir()):
            if deck_directory.is_symlink():
                fail(f"legacy generated Deck directory is a symlink: {deck_directory}")
            if not deck_directory.is_dir():
                continue
            generated = deck_directory / "deck.json"
            if not generated.exists() and not generated.is_symlink():
                continue
            if generated.is_symlink() or not generated.is_file():
                fail(f"legacy generated Deck file is unsafe: {generated}")
            if deck_directory.name not in MANAGED_DECKS:
                entries.append(
                    (
                        generated,
                        Path("src/deck/decks")
                        / deck_directory.name
                        / "deck.json",
                    )
                )
    return entries


def migrate_locked(
    context: RuntimeContext,
    target_fd: int,
    legacy: Path,
    reuse_existing_cache: bool,
) -> bool:
    if legacy == target.resolve(strict=False):
        return False

    # Compare every collision before copying anything.
    entries = migration_entries(legacy)
    source_digests: dict[Path, str] = {}
    destination_digests: dict[Path, str | None] = {}
    collisions: list[Path] = []
    for source_entry, destination in entries:
        source_digest = path_entry_digest(source_entry)
        source_digests[source_entry] = source_digest
        destination_digest = relative_entry_digest(target_fd, destination)
        destination_digests[destination] = destination_digest
        if destination_digest is not None and source_digest != destination_digest:
            collisions.append(destination)

    if collisions and not reuse_existing_cache:
        fail(f"Deck runtime migration collision: {target / collisions[0]}")

    if collisions:
        runtime_test_pause(
            "migrate-reuse-before-revalidate",
            ",".join(destination.as_posix() for destination in collisions),
        )
        if migration_entries(legacy) != entries:
            fail(
                "legacy Deck runtime entry set changed during reuse "
                f"preflight: {legacy}"
            )
        for source_entry, source_digest in source_digests.items():
            if path_entry_digest(source_entry) != source_digest:
                fail(
                    "legacy Deck runtime changed during reuse preflight: "
                    f"{source_entry}"
                )
        for destination, destination_digest in destination_digests.items():
            if (
                relative_entry_digest(target_fd, destination)
                != destination_digest
            ):
                fail(
                    "Deck runtime cache changed during reuse preflight: "
                    f"{target / destination}"
                )
        if migration_entries(legacy) != entries:
            fail(
                "legacy Deck runtime entry set changed during reuse "
                f"preflight: {legacy}"
            )
        return True

    runtime_test_pause("migrate-before-copy", "")
    for source_entry, destination in entries:
        copy_runtime_entry(
            context,
            target_fd,
            source_entry,
            destination,
            source_digests[source_entry],
            destination_digests[destination],
        )
    for source_entry, source_digest in source_digests.items():
        if path_entry_digest(source_entry) != source_digest:
            fail(f"legacy Deck runtime changed during migration: {source_entry}")
    return False


if command == "path":
    print(target)
else:
    try:
        with catch_runtime_signals():
            if command == "ensure":
                with runtime_lock() as context:
                    target_fd, _target_entry = ensure_locked(context)
                    os.close(target_fd)
            else:
                legacy = resolve_legacy_root(legacy_arg)
                reused_existing_cache = False
                with runtime_lock() as context:
                    target_fd, _target_entry = ensure_locked(context)
                    try:
                        reused_existing_cache = migrate_locked(
                            context,
                            target_fd,
                            legacy,
                            reuse_existing,
                        )
                    finally:
                        os.close(target_fd)
                if reused_existing_cache:
                    print(REUSE_EXISTING_NOTICE, file=sys.stderr)
        print(target)
    except RuntimeSignal as received:
        raise SystemExit(128 + received.signum) from None
PY
