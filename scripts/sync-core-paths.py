#!/usr/bin/env python3
"""Race-resistant filesystem operations for the SCV Core maintainer updater.

All mutable path traversal is anchored to opened directory descriptors.  The
shell updater supplies identities captured for the repository and transaction
roots, so replacing a pathname with a symlink cannot redirect a lock, rename,
or cleanup operation outside those roots.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import os
import re
import secrets
import stat
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn


class PathOperationError(RuntimeError):
    pass


@dataclass(frozen=True)
class LockOwner:
    pid: int
    process_start: str
    token: str
    payload: bytes


@dataclass(frozen=True)
class LockSnapshot:
    directory: os.stat_result
    owner_entry: os.stat_result
    owner: LockOwner


@dataclass(frozen=True)
class FileLockSnapshot:
    entry: os.stat_result
    payload: bytes


@dataclass
class DirectoryChain:
    descriptors: list[int]
    edges: list[tuple[int, str, os.stat_result, int]]

    @property
    def parent_fd(self) -> int:
        return self.descriptors[-1]

    def verify(self) -> None:
        for parent_fd, name, expected, child_fd in self.edges:
            current = _entry_at(parent_fd, name)
            opened = os.fstat(child_fd)
            if (
                current is None
                or not _same_entry(expected, current)
                or not _same_entry(expected, opened)
            ):
                raise PathOperationError(
                    f"directory ancestor changed before atomic rename: {name}"
                )

    def close(self) -> None:
        for descriptor in reversed(self.descriptors):
            os.close(descriptor)
        self.descriptors.clear()
        self.edges.clear()


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def _same_entry(first: os.stat_result, second: os.stat_result) -> bool:
    return (
        first.st_dev == second.st_dev
        and first.st_ino == second.st_ino
        and first.st_mode == second.st_mode
    )


def _same_identity(first: os.stat_result, second: os.stat_result) -> bool:
    return first.st_dev == second.st_dev and first.st_ino == second.st_ino


def _validate_basename(name: str, label: str) -> None:
    if (
        not name
        or name in {".", ".."}
        or "/" in name
        or (os.altsep and os.altsep in name)
        or "\x00" in name
    ):
        raise PathOperationError(f"unsafe {label} basename: {name!r}")


def _relative_parts(value: str, label: str) -> tuple[str, ...]:
    path = Path(value)
    parts = path.parts
    if (
        not value
        or path.is_absolute()
        or not parts
        or any(part in {"", ".", ".."} for part in parts)
    ):
        raise PathOperationError(f"unsafe {label} relative path: {value!r}")
    for part in parts:
        _validate_basename(part, label)
    return parts


def _entry_at(parent_fd: int, name: str) -> os.stat_result | None:
    try:
        return os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    except OSError as error:
        raise PathOperationError(
            f"cannot inspect anchored path {name}: {error}"
        ) from error


def _open_anchor(path: Path, expected_device: int, expected_inode: int) -> int:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PathOperationError(f"cannot open protected root {path}: {error}") from error
    opened = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(opened.st_mode)
        or opened.st_dev != expected_device
        or opened.st_ino != expected_inode
    ):
        os.close(descriptor)
        raise PathOperationError("protected root identity or type changed")
    return descriptor


def _open_inherited_anchor(
    inherited_fd: int, expected_device: int, expected_inode: int
) -> int:
    try:
        descriptor = os.dup(inherited_fd)
    except OSError as error:
        raise PathOperationError(
            f"cannot duplicate protected root descriptor: {error}"
        ) from error
    opened = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(opened.st_mode)
        or opened.st_dev != expected_device
        or opened.st_ino != expected_inode
    ):
        os.close(descriptor)
        raise PathOperationError("protected root descriptor identity changed")
    return descriptor


def _assert_anchor_path(
    path: Path,
    descriptor: int,
    expected_device: int,
    expected_inode: int,
) -> None:
    try:
        current = path.lstat()
    except OSError as error:
        raise PathOperationError(f"protected root path changed: {error}") from error
    opened = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(current.st_mode)
        or current.st_dev != expected_device
        or current.st_ino != expected_inode
        or opened.st_dev != expected_device
        or opened.st_ino != expected_inode
    ):
        raise PathOperationError("protected root identity or type changed")


def _open_parent_chain(
    anchor_fd: int,
    parts: tuple[str, ...],
    *,
    create: bool,
) -> DirectoryChain:
    descriptors = [os.dup(anchor_fd)]
    edges: list[tuple[int, str, os.stat_result, int]] = []
    root_device = os.fstat(anchor_fd).st_dev
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        for part in parts[:-1]:
            parent_fd = descriptors[-1]
            before = _entry_at(parent_fd, part)
            if before is None and create:
                try:
                    os.mkdir(part, mode=0o755, dir_fd=parent_fd)
                except FileExistsError:
                    pass
                before = _entry_at(parent_fd, part)
            if (
                before is None
                or not stat.S_ISDIR(before.st_mode)
                or before.st_dev != root_device
            ):
                raise PathOperationError(
                    f"unsafe or missing directory ancestor: {part}"
                )
            try:
                child_fd = os.open(part, flags, dir_fd=parent_fd)
            except OSError as error:
                raise PathOperationError(
                    f"cannot open directory ancestor {part}: {error}"
                ) from error
            opened = os.fstat(child_fd)
            if not _same_entry(before, opened):
                os.close(child_fd)
                raise PathOperationError(
                    f"directory ancestor changed while opening: {part}"
                )
            descriptors.append(child_fd)
            edges.append((parent_fd, part, before, child_fd))
        return DirectoryChain(descriptors, edges)
    except BaseException:
        for descriptor in reversed(descriptors):
            os.close(descriptor)
        raise


def _rename_noreplace(
    source_parent_fd: int,
    source_name: str,
    destination_parent_fd: int,
    destination_name: str,
) -> None:
    encoded_source = os.fsencode(source_name)
    encoded_destination = os.fsencode(destination_name)
    library = ctypes.CDLL(None, use_errno=True)
    result: int

    if hasattr(library, "renameat2"):
        operation = library.renameat2
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
            encoded_source,
            destination_parent_fd,
            encoded_destination,
            1,  # RENAME_NOREPLACE
        )
    elif hasattr(library, "renameatx_np"):
        operation = library.renameatx_np
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
            encoded_source,
            destination_parent_fd,
            encoded_destination,
            0x00000004,  # RENAME_EXCL on macOS
        )
    else:
        raise PathOperationError(
            f"atomic no-replace rename is unsupported on {sys.platform}"
        )

    if result != 0:
        error_number = ctypes.get_errno()
        detail = (
            "destination appeared concurrently"
            if error_number in {errno.EEXIST, errno.ENOTEMPTY}
            else os.strerror(error_number)
        )
        raise PathOperationError(f"atomic anchored rename failed: {detail}")


def _pause_for_test(point: str, detail: str | None = None) -> None:
    if os.environ.get("SCV_CORE_SYNC_TEST_PAUSE_AT") != point:
        return
    ready_raw = os.environ.get("SCV_CORE_SYNC_TEST_READY_FILE")
    continue_raw = os.environ.get("SCV_CORE_SYNC_TEST_CONTINUE_FILE")
    if not ready_raw or not continue_raw:
        raise PathOperationError("test pause requires ready and continue files")
    ready = Path(ready_raw)
    continuation = Path(continue_raw)
    message = point + "\n"
    if detail is not None:
        message += detail + "\n"
    ready.write_text(message, encoding="utf-8")
    deadline = time.monotonic() + 30
    while not continuation.exists():
        if time.monotonic() >= deadline:
            raise PathOperationError(f"timed out at test pause: {point}")
        time.sleep(0.02)


def identity(args: argparse.Namespace) -> None:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(args.path, flags)
    except OSError as error:
        raise PathOperationError(f"cannot open identity root {args.path}: {error}") from error
    try:
        entry = os.fstat(descriptor)
        current = args.path.lstat()
        if not stat.S_ISDIR(current.st_mode) or not _same_entry(entry, current):
            raise PathOperationError("identity root changed while opening")
        print(f"{entry.st_dev}:{entry.st_ino}")
    finally:
        os.close(descriptor)


def identity_fd(args: argparse.Namespace) -> None:
    try:
        descriptor = os.dup(args.fd)
    except OSError as error:
        raise PathOperationError(
            f"cannot duplicate identity descriptor: {error}"
        ) from error
    try:
        entry = os.fstat(descriptor)
        if not stat.S_ISDIR(entry.st_mode):
            raise PathOperationError("identity descriptor is not a directory")
        print(f"{entry.st_dev}:{entry.st_ino}")
    finally:
        os.close(descriptor)


def make_temp_directory(args: argparse.Namespace) -> None:
    if (
        not args.prefix
        or "/" in args.prefix
        or (os.altsep and os.altsep in args.prefix)
        or "\x00" in args.prefix
        or not re.fullmatch(r"[A-Za-z0-9_.-]+", args.prefix)
    ):
        raise PathOperationError("unsafe transaction directory prefix")
    anchor_fd = _open_anchor(
        args.anchor, args.anchor_device, args.anchor_inode
    )
    try:
        _assert_anchor_path(
            args.anchor,
            anchor_fd,
            args.anchor_device,
            args.anchor_inode,
        )
        for _attempt in range(100):
            name = args.prefix + secrets.token_hex(8)
            try:
                os.mkdir(name, mode=0o700, dir_fd=anchor_fd)
            except FileExistsError:
                continue
            before = _entry_at(anchor_fd, name)
            if before is None or not stat.S_ISDIR(before.st_mode):
                raise PathOperationError(
                    "transaction directory changed during creation"
                )
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
            flags |= getattr(os, "O_NOFOLLOW", 0)
            descriptor = os.open(name, flags, dir_fd=anchor_fd)
            try:
                opened = os.fstat(descriptor)
                current = _entry_at(anchor_fd, name)
                if (
                    current is None
                    or not _same_entry(before, opened)
                    or not _same_entry(before, current)
                ):
                    raise PathOperationError(
                        "transaction directory changed during creation"
                    )
                _fsync_directory(descriptor)
                print(f"{name}:{opened.st_dev}:{opened.st_ino}")
                return
            finally:
                os.close(descriptor)
        raise PathOperationError("cannot allocate a Core transaction directory")
    finally:
        os.close(anchor_fd)


def rename_noreplace(args: argparse.Namespace) -> None:
    source_parts = _relative_parts(args.source_relative, "source")
    destination_parts = _relative_parts(
        args.destination_relative, "destination"
    )
    source_anchor_fd = _open_anchor(
        args.source_anchor,
        args.source_device,
        args.source_inode,
    )
    destination_anchor_fd = _open_anchor(
        args.destination_anchor,
        args.destination_device,
        args.destination_inode,
    )
    source_chain: DirectoryChain | None = None
    destination_chain: DirectoryChain | None = None
    try:
        _assert_anchor_path(
            args.source_anchor,
            source_anchor_fd,
            args.source_device,
            args.source_inode,
        )
        _assert_anchor_path(
            args.destination_anchor,
            destination_anchor_fd,
            args.destination_device,
            args.destination_inode,
        )
        source_chain = _open_parent_chain(
            source_anchor_fd, source_parts, create=False
        )
        destination_chain = _open_parent_chain(
            destination_anchor_fd,
            destination_parts,
            create=args.create_destination_parents,
        )
        source_name = source_parts[-1]
        destination_name = destination_parts[-1]
        source_entry = _entry_at(source_chain.parent_fd, source_name)
        if source_entry is None:
            raise PathOperationError(
                f"atomic rename source is missing: {args.source_relative}"
            )
        if _entry_at(destination_chain.parent_fd, destination_name) is not None:
            raise PathOperationError(
                "atomic rename destination already exists: "
                f"{args.destination_relative}"
            )

        _pause_for_test(f"before-rename:{args.label}", args.label)
        _assert_anchor_path(
            args.source_anchor,
            source_anchor_fd,
            args.source_device,
            args.source_inode,
        )
        _assert_anchor_path(
            args.destination_anchor,
            destination_anchor_fd,
            args.destination_device,
            args.destination_inode,
        )
        source_chain.verify()
        destination_chain.verify()
        current_source = _entry_at(source_chain.parent_fd, source_name)
        if current_source is None or not _same_entry(source_entry, current_source):
            raise PathOperationError("atomic rename source identity changed")
        if _entry_at(destination_chain.parent_fd, destination_name) is not None:
            raise PathOperationError("atomic rename destination appeared concurrently")

        _rename_noreplace(
            source_chain.parent_fd,
            source_name,
            destination_chain.parent_fd,
            destination_name,
        )
        if _entry_at(source_chain.parent_fd, source_name) is not None:
            raise PathOperationError("atomic rename source remained after rename")
        installed = _entry_at(destination_chain.parent_fd, destination_name)
        if installed is None or not _same_entry(source_entry, installed):
            raise PathOperationError("atomic rename destination identity changed")
    finally:
        if source_chain is not None:
            source_chain.close()
        if destination_chain is not None:
            destination_chain.close()
        os.close(source_anchor_fd)
        os.close(destination_anchor_fd)


def _open_source_directory(path: Path) -> tuple[int, os.stat_result]:
    try:
        before = path.lstat()
    except OSError as error:
        raise PathOperationError(f"cannot inspect copy source {path}: {error}") from error
    if not stat.S_ISDIR(before.st_mode):
        raise PathOperationError(f"copy source is not a directory: {path}")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise PathOperationError(f"cannot open copy source {path}: {error}") from error
    opened = os.fstat(descriptor)
    try:
        after = path.lstat()
    except OSError:
        os.close(descriptor)
        raise
    if not _same_entry(before, opened) or not _same_entry(before, after):
        os.close(descriptor)
        raise PathOperationError("copy source changed while opening")
    return descriptor, opened


def _copy_regular_at(
    source_parent_fd: int,
    destination_parent_fd: int,
    name: str,
    expected: os.stat_result,
) -> None:
    source_flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    destination_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    destination_flags |= getattr(os, "O_NOFOLLOW", 0)
    source_fd = os.open(name, source_flags, dir_fd=source_parent_fd)
    try:
        opened = os.fstat(source_fd)
        if not _same_entry(expected, opened):
            raise PathOperationError(f"copy source changed while opening: {name}")
        destination_fd = os.open(
            name,
            destination_flags,
            stat.S_IMODE(expected.st_mode),
            dir_fd=destination_parent_fd,
        )
        try:
            while True:
                chunk = os.read(source_fd, 1024 * 1024)
                if not chunk:
                    break
                _write_all(destination_fd, chunk)
            os.fchmod(destination_fd, stat.S_IMODE(expected.st_mode))
            os.utime(
                destination_fd,
                ns=(expected.st_atime_ns, expected.st_mtime_ns),
            )
            os.fsync(destination_fd)
        finally:
            os.close(destination_fd)
    finally:
        os.close(source_fd)


def _copy_tree_contents(
    source_fd: int,
    destination_fd: int,
    source_device: int,
    relative: tuple[str, ...],
) -> None:
    try:
        names = sorted(os.listdir(source_fd))
    except OSError as error:
        raise PathOperationError(
            f"cannot list copy source {'/'.join(relative) or '.'}: {error}"
        ) from error
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    directory_flags |= getattr(os, "O_NOFOLLOW", 0)
    for name in names:
        _validate_basename(name, "copy entry")
        before = _entry_at(source_fd, name)
        if before is None:
            raise PathOperationError(f"copy source disappeared: {name}")
        display = "/".join(relative + (name,))
        if stat.S_ISDIR(before.st_mode):
            if before.st_dev != source_device:
                raise PathOperationError(
                    f"copy source crosses a filesystem boundary: {display}"
                )
            os.mkdir(
                name,
                mode=stat.S_IMODE(before.st_mode),
                dir_fd=destination_fd,
            )
            source_child = os.open(name, directory_flags, dir_fd=source_fd)
            destination_child = os.open(
                name, directory_flags, dir_fd=destination_fd
            )
            try:
                opened = os.fstat(source_child)
                if not _same_entry(before, opened):
                    raise PathOperationError(
                        f"copy source directory changed: {display}"
                    )
                _copy_tree_contents(
                    source_child,
                    destination_child,
                    source_device,
                    relative + (name,),
                )
                current = _entry_at(source_fd, name)
                if current is None or not _same_entry(before, current):
                    raise PathOperationError(
                        f"copy source directory changed: {display}"
                    )
                os.fchmod(
                    destination_child, stat.S_IMODE(before.st_mode)
                )
                os.utime(
                    destination_child,
                    ns=(before.st_atime_ns, before.st_mtime_ns),
                )
                _fsync_directory(destination_child)
            finally:
                os.close(source_child)
                os.close(destination_child)
        elif stat.S_ISREG(before.st_mode):
            _copy_regular_at(source_fd, destination_fd, name, before)
            current = _entry_at(source_fd, name)
            if current is None or not _same_entry(before, current):
                raise PathOperationError(f"copy source file changed: {display}")
        elif stat.S_ISLNK(before.st_mode):
            target = os.readlink(name, dir_fd=source_fd)
            current = _entry_at(source_fd, name)
            if current is None or not _same_entry(before, current):
                raise PathOperationError(
                    f"copy source symlink changed: {display}"
                )
            os.symlink(target, name, dir_fd=destination_fd)
            try:
                os.utime(
                    name,
                    ns=(before.st_atime_ns, before.st_mtime_ns),
                    dir_fd=destination_fd,
                    follow_symlinks=False,
                )
            except (NotImplementedError, OSError):
                pass
        else:
            raise PathOperationError(
                f"copy source contains a special file: {display}"
            )


def copy_tree(args: argparse.Namespace) -> None:
    destination_parts = _relative_parts(args.destination_relative, "destination")
    source_fd, source_entry = _open_source_directory(args.source)
    anchor_fd = _open_anchor(
        args.destination_anchor,
        args.destination_device,
        args.destination_inode,
    )
    chain: DirectoryChain | None = None
    destination_fd: int | None = None
    try:
        _assert_anchor_path(
            args.destination_anchor,
            anchor_fd,
            args.destination_device,
            args.destination_inode,
        )
        chain = _open_parent_chain(
            anchor_fd, destination_parts, create=True
        )
        chain.verify()
        name = destination_parts[-1]
        if _entry_at(chain.parent_fd, name) is not None:
            raise PathOperationError(
                f"copy destination already exists: {args.destination_relative}"
            )
        os.mkdir(name, mode=0o700, dir_fd=chain.parent_fd)
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        destination_fd = os.open(name, flags, dir_fd=chain.parent_fd)
        created = os.fstat(destination_fd)
        current = _entry_at(chain.parent_fd, name)
        if current is None or not _same_entry(created, current):
            raise PathOperationError("copy destination changed during creation")
        if args.label:
            _pause_for_test(
                f"after-copy-destination:{args.label}", args.label
            )
            chain.verify()
            current = _entry_at(chain.parent_fd, name)
            if current is None or not _same_entry(created, current):
                raise PathOperationError(
                    "copy destination changed before content copy"
                )
        _copy_tree_contents(
            source_fd,
            destination_fd,
            source_entry.st_dev,
            (name,),
        )
        os.fchmod(destination_fd, stat.S_IMODE(source_entry.st_mode))
        os.utime(
            destination_fd,
            ns=(source_entry.st_atime_ns, source_entry.st_mtime_ns),
        )
        _fsync_directory(destination_fd)
        chain.verify()
        current = _entry_at(chain.parent_fd, name)
        if current is None or not _same_identity(created, current):
            raise PathOperationError("copy destination changed during copy")
    finally:
        if destination_fd is not None:
            os.close(destination_fd)
        if chain is not None:
            chain.close()
        os.close(anchor_fd)
        os.close(source_fd)


def copy_file(args: argparse.Namespace) -> None:
    destination_parts = _relative_parts(args.destination_relative, "destination")
    try:
        before = args.source.lstat()
    except OSError as error:
        raise PathOperationError(
            f"cannot inspect copy source {args.source}: {error}"
        ) from error
    if not stat.S_ISREG(before.st_mode):
        raise PathOperationError(f"copy source is not a file: {args.source}")
    source_parent = args.source.parent
    source_name = args.source.name
    source_parent_fd, _source_parent_entry = _open_source_directory(source_parent)
    anchor_fd = _open_anchor(
        args.destination_anchor,
        args.destination_device,
        args.destination_inode,
    )
    chain: DirectoryChain | None = None
    try:
        _assert_anchor_path(
            args.destination_anchor,
            anchor_fd,
            args.destination_device,
            args.destination_inode,
        )
        chain = _open_parent_chain(
            anchor_fd, destination_parts, create=True
        )
        chain.verify()
        if args.label:
            _pause_for_test(
                f"before-copy-file:{args.label}", args.label
            )
            chain.verify()
        destination_name = destination_parts[-1]
        if _entry_at(chain.parent_fd, destination_name) is not None:
            raise PathOperationError(
                f"copy destination already exists: {args.destination_relative}"
            )
        if destination_name == source_name:
            _copy_regular_at(
                source_parent_fd,
                chain.parent_fd,
                source_name,
                before,
            )
        else:
            source_fd = os.open(
                source_name,
                os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=source_parent_fd,
            )
            try:
                opened = os.fstat(source_fd)
                if not _same_entry(before, opened):
                    raise PathOperationError(
                        "copy source changed while opening"
                    )
                flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
                flags |= getattr(os, "O_NOFOLLOW", 0)
                destination_fd = os.open(
                    destination_name,
                    flags,
                    stat.S_IMODE(before.st_mode),
                    dir_fd=chain.parent_fd,
                )
                try:
                    while True:
                        chunk = os.read(source_fd, 1024 * 1024)
                        if not chunk:
                            break
                        _write_all(destination_fd, chunk)
                    os.fchmod(destination_fd, stat.S_IMODE(before.st_mode))
                    os.utime(
                        destination_fd,
                        ns=(before.st_atime_ns, before.st_mtime_ns),
                    )
                    os.fsync(destination_fd)
                finally:
                    os.close(destination_fd)
            finally:
                os.close(source_fd)
        chain.verify()
    finally:
        if chain is not None:
            chain.close()
        os.close(anchor_fd)
        os.close(source_parent_fd)


def make_directories(args: argparse.Namespace) -> None:
    parts = _relative_parts(args.relative, "directory")
    anchor_fd = _open_anchor(
        args.anchor, args.anchor_device, args.anchor_inode
    )
    chain: DirectoryChain | None = None
    try:
        _assert_anchor_path(
            args.anchor,
            anchor_fd,
            args.anchor_device,
            args.anchor_inode,
        )
        chain = _open_parent_chain(
            anchor_fd, parts + (".scv-unused-leaf",), create=True
        )
        chain.verify()
    finally:
        if chain is not None:
            chain.close()
        os.close(anchor_fd)


def remove_entry(args: argparse.Namespace) -> None:
    parts = _relative_parts(args.relative, "removal")
    anchor_fd = _open_anchor(
        args.anchor, args.anchor_device, args.anchor_inode
    )
    chain: DirectoryChain | None = None
    try:
        _assert_anchor_path(
            args.anchor,
            anchor_fd,
            args.anchor_device,
            args.anchor_inode,
        )
        chain = _open_parent_chain(anchor_fd, parts, create=False)
        chain.verify()
        name = parts[-1]
        before = _entry_at(chain.parent_fd, name)
        if before is None:
            return
        if not (
            stat.S_ISDIR(before.st_mode)
            or stat.S_ISREG(before.st_mode)
            or stat.S_ISLNK(before.st_mode)
        ):
            raise PathOperationError(
                f"refusing to remove special projection entry: {args.relative}"
            )
        quarantine = f".scv-projection-remove.{secrets.token_hex(12)}"
        _rename_noreplace(
            chain.parent_fd, name, chain.parent_fd, quarantine
        )
        moved = _entry_at(chain.parent_fd, quarantine)
        if moved is None or not _same_entry(before, moved):
            raise PathOperationError(
                "projection entry changed before quarantine"
            )
        if stat.S_ISDIR(moved.st_mode):
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
            flags |= getattr(os, "O_NOFOLLOW", 0)
            descriptor = os.open(
                quarantine, flags, dir_fd=chain.parent_fd
            )
            try:
                opened = os.fstat(descriptor)
                if not _same_entry(moved, opened):
                    raise PathOperationError(
                        "projection directory changed during removal"
                    )
                _remove_contents(
                    descriptor, opened.st_dev, (quarantine,)
                )
                current = _entry_at(chain.parent_fd, quarantine)
                if current is None or not _same_entry(moved, current):
                    raise PathOperationError(
                        "projection directory changed during removal"
                    )
            finally:
                os.close(descriptor)
            os.rmdir(quarantine, dir_fd=chain.parent_fd)
        else:
            current = _entry_at(chain.parent_fd, quarantine)
            if current is None or not _same_entry(moved, current):
                raise PathOperationError(
                    "projection file changed during removal"
                )
            os.unlink(quarantine, dir_fd=chain.parent_fd)
    finally:
        if chain is not None:
            chain.close()
        os.close(anchor_fd)


def _write_all(descriptor: int, payload: bytes) -> None:
    offset = 0
    while offset < len(payload):
        written = os.write(descriptor, payload[offset:])
        if written <= 0:
            raise PathOperationError("cannot write Core sync lock owner")
        offset += written


def _fsync_directory(descriptor: int) -> None:
    try:
        os.fsync(descriptor)
    except OSError as error:
        if error.errno not in {errno.EINVAL, errno.ENOTSUP}:
            raise


def _read_all(descriptor: int, limit: int = 4096) -> bytes:
    chunks: list[bytes] = []
    size = 0
    while True:
        chunk = os.read(descriptor, min(4096, limit + 1 - size))
        if not chunk:
            break
        chunks.append(chunk)
        size += len(chunk)
        if size > limit:
            raise PathOperationError("unsafe or malformed Core sync lock")
    return b"".join(chunks)


def _owner_payload(pid: int, process_start: str, token: str) -> bytes:
    return (
        f"pid={pid}\n"
        f"process_start={process_start}\n"
        f"token={token}\n"
    ).encode("ascii")


def _read_file_lock_at(parent_fd: int, name: str) -> FileLockSnapshot:
    before = _entry_at(parent_fd, name)
    parent_entry = os.fstat(parent_fd)
    if (
        before is None
        or not stat.S_ISREG(before.st_mode)
        or before.st_nlink != 1
        or before.st_dev != parent_entry.st_dev
    ):
        raise PathOperationError("unsafe or malformed Git index lock")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        raise PathOperationError("unsafe or malformed Git index lock") from error
    try:
        opened = os.fstat(descriptor)
        if not _same_entry(before, opened):
            raise PathOperationError("Git index lock changed while opening")
        payload = _read_all(descriptor)
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(before, after):
            raise PathOperationError("Git index lock changed while reading")
        return FileLockSnapshot(before, payload)
    finally:
        os.close(descriptor)


def file_lock_acquire(args: argparse.Namespace) -> None:
    _validate_basename(args.lock_name, "Git index lock")
    if not re.fullmatch(r"[0-9a-f]{48}", args.token):
        raise PathOperationError("unsafe Git index lock token")
    payload = (args.token + "\n").encode("ascii")
    parent_fd = _open_inherited_anchor(
        args.parent_fd,
        args.expected_parent_device,
        args.expected_parent_inode,
    )
    try:
        _lock_directory_descriptor(parent_fd)
        _pause_for_test("before-git-index-lock-acquire", args.lock_name)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        flags |= getattr(os, "O_NOFOLLOW", 0)
        try:
            descriptor = os.open(
                args.lock_name, flags, 0o600, dir_fd=parent_fd
            )
        except FileExistsError as error:
            raise PathOperationError(
                "Git index is locked by another process"
            ) from error
        except OSError as error:
            raise PathOperationError(
                f"cannot create Git index lock safely: {error}"
            ) from error
        try:
            _write_all(descriptor, payload)
            os.fsync(descriptor)
            opened = os.fstat(descriptor)
            if (
                not stat.S_ISREG(opened.st_mode)
                or opened.st_nlink != 1
                or opened.st_dev != os.fstat(parent_fd).st_dev
            ):
                raise PathOperationError("unsafe Git index lock identity")
        finally:
            os.close(descriptor)
        observed = _read_file_lock_at(parent_fd, args.lock_name)
        if observed.payload != payload or not _same_entry(opened, observed.entry):
            raise PathOperationError("Git index lock changed during creation")
        print(f"{opened.st_dev}:{opened.st_ino}")
    finally:
        os.close(parent_fd)


def file_lock_release(args: argparse.Namespace) -> None:
    _validate_basename(args.lock_name, "Git index lock")
    if not re.fullmatch(r"[0-9a-f]{48}", args.token):
        raise PathOperationError("unsafe Git index lock token")
    payload = (args.token + "\n").encode("ascii")
    parent_fd = _open_inherited_anchor(
        args.parent_fd,
        args.expected_parent_device,
        args.expected_parent_inode,
    )
    try:
        _lock_directory_descriptor(parent_fd)
        owned = _read_file_lock_at(parent_fd, args.lock_name)
        if (
            owned.entry.st_dev != args.expected_lock_device
            or owned.entry.st_ino != args.expected_lock_inode
            or owned.payload != payload
        ):
            raise PathOperationError("Git index lock ownership or identity changed")
        quarantine = (
            f".scv-index-lock-release.{args.token}"
        )
        _validate_basename(quarantine, "Git index lock quarantine")
        _pause_for_test("before-git-index-lock-release", quarantine)
        _rename_noreplace(
            parent_fd, args.lock_name, parent_fd, quarantine
        )
        quarantined = _read_file_lock_at(parent_fd, quarantine)
        if (
            not _same_entry(owned.entry, quarantined.entry)
            or owned.payload != quarantined.payload
        ):
            raise PathOperationError(
                "Git index lock ownership or identity changed before release"
            )
        current = _entry_at(parent_fd, quarantine)
        if current is None or not _same_entry(owned.entry, current):
            raise PathOperationError("Git index lock changed during release")
        os.unlink(quarantine, dir_fd=parent_fd)
    finally:
        os.close(parent_fd)


def _parse_lock_owner(payload: bytes) -> LockOwner:
    try:
        lines = payload.decode("ascii").splitlines()
    except UnicodeDecodeError as error:
        raise PathOperationError("unsafe or malformed Core sync lock") from error
    if len(lines) != 3:
        raise PathOperationError("unsafe or malformed Core sync lock")
    values: dict[str, str] = {}
    for line in lines:
        key, separator, value = line.partition("=")
        if not separator or key in values:
            raise PathOperationError("unsafe or malformed Core sync lock")
        values[key] = value
    if set(values) != {"pid", "process_start", "token"}:
        raise PathOperationError("unsafe or malformed Core sync lock")
    if not re.fullmatch(r"[1-9][0-9]*", values["pid"]):
        raise PathOperationError("unsafe or malformed Core sync lock")
    if not re.fullmatch(r"(?:[0-9]+|unknown)", values["process_start"]):
        raise PathOperationError("unsafe or malformed Core sync lock")
    if not re.fullmatch(r"[0-9a-f]{48}", values["token"]):
        raise PathOperationError("unsafe or malformed Core sync lock")
    return LockOwner(
        pid=int(values["pid"]),
        process_start=values["process_start"],
        token=values["token"],
        payload=payload,
    )


def _open_lock_directory(
    parent_fd: int, name: str
) -> tuple[int, os.stat_result]:
    before = _entry_at(parent_fd, name)
    parent_entry = os.fstat(parent_fd)
    if (
        before is None
        or not stat.S_ISDIR(before.st_mode)
        or before.st_dev != parent_entry.st_dev
    ):
        raise PathOperationError("unsafe or malformed Core sync lock")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        raise PathOperationError("unsafe or malformed Core sync lock") from error
    opened = os.fstat(descriptor)
    if not _same_entry(before, opened):
        os.close(descriptor)
        raise PathOperationError("Core sync lock changed while opening")
    return descriptor, before


def _read_lock_owner_at(
    lock_fd: int, lock_entry: os.stat_result
) -> tuple[os.stat_result, LockOwner]:
    try:
        names = sorted(os.listdir(lock_fd))
    except OSError as error:
        raise PathOperationError("cannot list Core sync lock") from error
    if names != ["owner"]:
        raise PathOperationError("unsafe or malformed Core sync lock")
    try:
        before = os.stat("owner", dir_fd=lock_fd, follow_symlinks=False)
    except OSError as error:
        raise PathOperationError("unsafe or malformed Core sync lock") from error
    if (
        not stat.S_ISREG(before.st_mode)
        or before.st_nlink != 1
        or before.st_dev != lock_entry.st_dev
    ):
        raise PathOperationError("unsafe or malformed Core sync lock")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        owner_fd = os.open("owner", flags, dir_fd=lock_fd)
    except OSError as error:
        raise PathOperationError("unsafe or malformed Core sync lock") from error
    try:
        opened = os.fstat(owner_fd)
        if not _same_entry(before, opened):
            raise PathOperationError("Core sync lock owner changed while opening")
        payload = _read_all(owner_fd)
        after = os.stat("owner", dir_fd=lock_fd, follow_symlinks=False)
        if not _same_entry(before, after):
            raise PathOperationError("Core sync lock owner changed while reading")
    finally:
        os.close(owner_fd)
    return before, _parse_lock_owner(payload)


def _read_lock_snapshot(parent_fd: int, name: str) -> LockSnapshot:
    lock_fd, directory = _open_lock_directory(parent_fd, name)
    try:
        owner_entry, owner = _read_lock_owner_at(lock_fd, directory)
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(directory, after):
            raise PathOperationError("Core sync lock changed while reading")
        return LockSnapshot(directory, owner_entry, owner)
    finally:
        os.close(lock_fd)


def _same_lock_snapshot(first: LockSnapshot, second: LockSnapshot) -> bool:
    return (
        _same_entry(first.directory, second.directory)
        and _same_entry(first.owner_entry, second.owner_entry)
        and first.owner == second.owner
    )


def _create_lock_at(
    parent_fd: int, name: str, owner: LockOwner
) -> LockSnapshot:
    try:
        os.mkdir(name, mode=0o700, dir_fd=parent_fd)
    except FileExistsError:
        raise
    except OSError as error:
        raise PathOperationError(f"cannot create Core sync lock: {error}") from error
    _pause_for_test("after-lock-mkdir", name)
    lock_fd, lock_entry = _open_lock_directory(parent_fd, name)
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        flags |= getattr(os, "O_NOFOLLOW", 0)
        try:
            owner_fd = os.open("owner", flags, 0o600, dir_fd=lock_fd)
        except OSError as error:
            raise PathOperationError(
                "cannot create Core sync lock owner safely"
            ) from error
        try:
            _write_all(owner_fd, owner.payload)
            os.fsync(owner_fd)
        finally:
            os.close(owner_fd)
        owner_entry, observed_owner = _read_lock_owner_at(lock_fd, lock_entry)
        if observed_owner != owner:
            raise PathOperationError("Core sync lock owner changed during creation")
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(lock_entry, after):
            raise PathOperationError("Core sync lock changed during creation")
        _fsync_directory(lock_fd)
        return LockSnapshot(lock_entry, owner_entry, observed_owner)
    finally:
        os.close(lock_fd)


def _remove_lock_at(
    parent_fd: int, name: str, expected: LockSnapshot
) -> None:
    lock_fd, lock_entry = _open_lock_directory(parent_fd, name)
    try:
        owner_entry, owner = _read_lock_owner_at(lock_fd, lock_entry)
        observed = LockSnapshot(lock_entry, owner_entry, owner)
        if not _same_lock_snapshot(observed, expected):
            raise PathOperationError("Core sync lock ownership or identity changed")
        os.unlink("owner", dir_fd=lock_fd)
        if os.listdir(lock_fd):
            raise PathOperationError("Core sync lock gained an unexpected entry")
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(lock_entry, after):
            raise PathOperationError("Core sync lock changed during removal")
        _fsync_directory(lock_fd)
    finally:
        os.close(lock_fd)
    os.rmdir(name, dir_fd=parent_fd)


def _process_start_id(pid: int) -> str:
    path = Path("/proc") / str(pid) / "stat"
    try:
        return path.read_text(encoding="utf-8").rsplit(")", 1)[1].split()[19]
    except (IndexError, OSError):
        return "unknown"


def _process_is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _lock_directory_descriptor(descriptor: int) -> None:
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
    except OSError as error:
        raise PathOperationError(
            f"cannot serialize Core sync lock lifecycle: {error}"
        ) from error


def _quarantine_name(lock_name: str, token: str, suffix: str) -> str:
    if not lock_name.endswith(".lock"):
        raise PathOperationError("Core sync lock basename must end in .lock")
    return f"{lock_name[:-5]}-quarantine.{suffix}.{token}"


def lock_acquire(args: argparse.Namespace) -> None:
    _validate_basename(args.lock_name, "lock")
    owner = _parse_lock_owner(
        _owner_payload(args.pid, args.process_start, args.token)
    )
    parent_fd = _open_anchor(
        args.parent, args.expected_parent_device, args.expected_parent_inode
    )
    try:
        _lock_directory_descriptor(parent_fd)
        for attempt in range(1, 5):
            _assert_anchor_path(
                args.parent,
                parent_fd,
                args.expected_parent_device,
                args.expected_parent_inode,
            )
            try:
                created = _create_lock_at(parent_fd, args.lock_name, owner)
                print(f"{created.directory.st_dev}:{created.directory.st_ino}")
                return
            except FileExistsError:
                pass

            stale = _read_lock_snapshot(parent_fd, args.lock_name)
            if _process_is_alive(stale.owner.pid):
                current_start = _process_start_id(stale.owner.pid)
                if (
                    stale.owner.process_start == "unknown"
                    or current_start == "unknown"
                    or stale.owner.process_start == current_start
                ):
                    raise PathOperationError(
                        "another Core sync is already running "
                        f"(pid {stale.owner.pid})"
                    )

            quarantine = _quarantine_name(
                args.lock_name, args.token, f"stale-{attempt}"
            )
            _pause_for_test("before-stale-lock-quarantine", quarantine)
            _assert_anchor_path(
                args.parent,
                parent_fd,
                args.expected_parent_device,
                args.expected_parent_inode,
            )
            _rename_noreplace(
                parent_fd, args.lock_name, parent_fd, quarantine
            )
            quarantined = _read_lock_snapshot(parent_fd, quarantine)
            if not _same_lock_snapshot(stale, quarantined):
                raise PathOperationError(
                    "stale Core sync lock changed before quarantine"
                )
            _remove_lock_at(parent_fd, quarantine, quarantined)
        raise PathOperationError(
            "could not acquire Core sync lock after reclaiming stale owners"
        )
    finally:
        os.close(parent_fd)


def lock_release(args: argparse.Namespace) -> None:
    _validate_basename(args.lock_name, "lock")
    expected_owner = _parse_lock_owner(
        _owner_payload(args.pid, args.process_start, args.token)
    )
    if args.parent_fd is not None:
        parent_fd = _open_inherited_anchor(
            args.parent_fd,
            args.expected_parent_device,
            args.expected_parent_inode,
        )
    else:
        parent_fd = _open_anchor(
            args.parent, args.expected_parent_device, args.expected_parent_inode
        )
    try:
        _lock_directory_descriptor(parent_fd)
        if args.parent_fd is None:
            _assert_anchor_path(
                args.parent,
                parent_fd,
                args.expected_parent_device,
                args.expected_parent_inode,
            )
        owned = _read_lock_snapshot(parent_fd, args.lock_name)
        if (
            owned.directory.st_dev != args.expected_lock_device
            or owned.directory.st_ino != args.expected_lock_inode
            or owned.owner != expected_owner
        ):
            raise PathOperationError("Core sync lock ownership or identity changed")
        quarantine = _quarantine_name(
            args.lock_name, args.token, "release"
        )
        _pause_for_test("before-lock-release", quarantine)
        if args.parent_fd is None:
            _assert_anchor_path(
                args.parent,
                parent_fd,
                args.expected_parent_device,
                args.expected_parent_inode,
            )
        _rename_noreplace(
            parent_fd, args.lock_name, parent_fd, quarantine
        )
        quarantined = _read_lock_snapshot(parent_fd, quarantine)
        if not _same_lock_snapshot(owned, quarantined):
            raise PathOperationError(
                "Core sync lock ownership or identity changed before release"
            )
        _remove_lock_at(parent_fd, quarantine, quarantined)
    finally:
        os.close(parent_fd)


def _remove_contents(
    directory_fd: int, root_device: int, relative: tuple[str, ...]
) -> None:
    try:
        names = sorted(os.listdir(directory_fd))
    except OSError as error:
        raise PathOperationError(
            f"cannot list transaction tree {'/'.join(relative)}: {error}"
        ) from error
    for name in names:
        child_relative = relative + (name,)
        display = "/".join(child_relative)
        before = _entry_at(directory_fd, name)
        if before is None:
            raise PathOperationError(
                f"transaction entry disappeared during cleanup: {display}"
            )
        if stat.S_ISDIR(before.st_mode):
            if before.st_dev != root_device:
                raise PathOperationError(
                    f"transaction tree crosses a filesystem boundary: {display}"
                )
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
            flags |= getattr(os, "O_NOFOLLOW", 0)
            try:
                child_fd = os.open(name, flags, dir_fd=directory_fd)
            except OSError as error:
                raise PathOperationError(
                    f"cannot open transaction directory {display}: {error}"
                ) from error
            try:
                opened = os.fstat(child_fd)
                if not _same_entry(before, opened):
                    raise PathOperationError(
                        f"transaction directory changed: {display}"
                    )
                _remove_contents(child_fd, root_device, child_relative)
                after = _entry_at(directory_fd, name)
                if after is None or not _same_entry(before, after):
                    raise PathOperationError(
                        f"transaction directory changed: {display}"
                    )
            finally:
                os.close(child_fd)
            os.rmdir(name, dir_fd=directory_fd)
        elif stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode):
            os.unlink(name, dir_fd=directory_fd)
        else:
            raise PathOperationError(
                f"transaction tree contains a special file: {display}"
            )


def remove_tree(args: argparse.Namespace) -> None:
    parts = _relative_parts(args.relative, "cleanup")
    anchor_fd = _open_anchor(
        args.anchor, args.anchor_device, args.anchor_inode
    )
    chain: DirectoryChain | None = None
    try:
        _assert_anchor_path(
            args.anchor,
            anchor_fd,
            args.anchor_device,
            args.anchor_inode,
        )
        chain = _open_parent_chain(anchor_fd, parts, create=False)
        chain.verify()
        name = parts[-1]
        before = _entry_at(chain.parent_fd, name)
        if (
            before is None
            or not stat.S_ISDIR(before.st_mode)
            or before.st_dev != args.expected_device
            or before.st_ino != args.expected_inode
        ):
            raise PathOperationError(
                "transaction cleanup target identity or type changed"
            )
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(name, flags, dir_fd=chain.parent_fd)
        try:
            opened = os.fstat(descriptor)
            if not _same_entry(before, opened):
                raise PathOperationError(
                    "transaction cleanup target changed while opening"
                )
            _remove_contents(descriptor, opened.st_dev, parts)
            chain.verify()
            after = _entry_at(chain.parent_fd, name)
            if after is None or not _same_entry(before, after):
                raise PathOperationError(
                    "transaction cleanup target changed during cleanup"
                )
        finally:
            os.close(descriptor)
        os.rmdir(name, dir_fd=chain.parent_fd)
    finally:
        if chain is not None:
            chain.close()
        os.close(anchor_fd)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    identity_parser = subparsers.add_parser("identity")
    identity_parser.add_argument("--path", type=Path, required=True)
    identity_parser.set_defaults(handler=identity)

    identity_fd_parser = subparsers.add_parser("identity-fd")
    identity_fd_parser.add_argument("--fd", type=int, required=True)
    identity_fd_parser.set_defaults(handler=identity_fd)

    make_temp_parser = subparsers.add_parser("make-temp-directory")
    make_temp_parser.add_argument("--anchor", type=Path, required=True)
    make_temp_parser.add_argument("--anchor-device", type=int, required=True)
    make_temp_parser.add_argument("--anchor-inode", type=int, required=True)
    make_temp_parser.add_argument("--prefix", required=True)
    make_temp_parser.set_defaults(handler=make_temp_directory)

    rename_parser = subparsers.add_parser("rename-noreplace")
    rename_parser.add_argument("--source-anchor", type=Path, required=True)
    rename_parser.add_argument("--source-device", type=int, required=True)
    rename_parser.add_argument("--source-inode", type=int, required=True)
    rename_parser.add_argument("--source-relative", required=True)
    rename_parser.add_argument("--destination-anchor", type=Path, required=True)
    rename_parser.add_argument("--destination-device", type=int, required=True)
    rename_parser.add_argument("--destination-inode", type=int, required=True)
    rename_parser.add_argument("--destination-relative", required=True)
    rename_parser.add_argument("--label", required=True)
    rename_parser.add_argument(
        "--create-destination-parents", action="store_true"
    )
    rename_parser.set_defaults(handler=rename_noreplace)

    for command, handler in (
        ("copy-tree", copy_tree),
        ("copy-file", copy_file),
    ):
        copy_parser = subparsers.add_parser(command)
        copy_parser.add_argument("--source", type=Path, required=True)
        copy_parser.add_argument(
            "--destination-anchor", type=Path, required=True
        )
        copy_parser.add_argument(
            "--destination-device", type=int, required=True
        )
        copy_parser.add_argument(
            "--destination-inode", type=int, required=True
        )
        copy_parser.add_argument("--destination-relative", required=True)
        copy_parser.add_argument("--label")
        copy_parser.set_defaults(handler=handler)

    directories_parser = subparsers.add_parser("make-directories")
    directories_parser.add_argument("--anchor", type=Path, required=True)
    directories_parser.add_argument(
        "--anchor-device", type=int, required=True
    )
    directories_parser.add_argument(
        "--anchor-inode", type=int, required=True
    )
    directories_parser.add_argument("--relative", required=True)
    directories_parser.set_defaults(handler=make_directories)

    remove_entry_parser = subparsers.add_parser("remove-entry")
    remove_entry_parser.add_argument("--anchor", type=Path, required=True)
    remove_entry_parser.add_argument(
        "--anchor-device", type=int, required=True
    )
    remove_entry_parser.add_argument(
        "--anchor-inode", type=int, required=True
    )
    remove_entry_parser.add_argument("--relative", required=True)
    remove_entry_parser.set_defaults(handler=remove_entry)

    for command, handler in (
        ("lock-acquire", lock_acquire),
        ("lock-release", lock_release),
    ):
        lock_parser = subparsers.add_parser(command)
        if command == "lock-acquire":
            lock_parser.add_argument("--parent", type=Path, required=True)
            lock_parser.set_defaults(parent_fd=None)
        else:
            parent_group = lock_parser.add_mutually_exclusive_group(
                required=True
            )
            parent_group.add_argument("--parent", type=Path)
            parent_group.add_argument("--parent-fd", type=int)
        lock_parser.add_argument("--lock-name", required=True)
        lock_parser.add_argument("--pid", type=int, required=True)
        lock_parser.add_argument("--process-start", required=True)
        lock_parser.add_argument("--token", required=True)
        lock_parser.add_argument(
            "--expected-parent-device", type=int, required=True
        )
        lock_parser.add_argument(
            "--expected-parent-inode", type=int, required=True
        )
        if command == "lock-release":
            lock_parser.add_argument(
                "--expected-lock-device", type=int, required=True
            )
            lock_parser.add_argument(
                "--expected-lock-inode", type=int, required=True
            )
        lock_parser.set_defaults(handler=handler)

    for command, handler in (
        ("file-lock-acquire", file_lock_acquire),
        ("file-lock-release", file_lock_release),
    ):
        file_lock_parser = subparsers.add_parser(command)
        file_lock_parser.add_argument("--parent-fd", type=int, required=True)
        file_lock_parser.add_argument("--lock-name", required=True)
        file_lock_parser.add_argument("--token", required=True)
        file_lock_parser.add_argument(
            "--expected-parent-device", type=int, required=True
        )
        file_lock_parser.add_argument(
            "--expected-parent-inode", type=int, required=True
        )
        if command == "file-lock-release":
            file_lock_parser.add_argument(
                "--expected-lock-device", type=int, required=True
            )
            file_lock_parser.add_argument(
                "--expected-lock-inode", type=int, required=True
            )
        file_lock_parser.set_defaults(handler=handler)

    remove_parser = subparsers.add_parser("remove-tree")
    remove_parser.add_argument("--anchor", type=Path, required=True)
    remove_parser.add_argument("--anchor-device", type=int, required=True)
    remove_parser.add_argument("--anchor-inode", type=int, required=True)
    remove_parser.add_argument("--relative", required=True)
    remove_parser.add_argument("--expected-device", type=int, required=True)
    remove_parser.add_argument("--expected-inode", type=int, required=True)
    remove_parser.set_defaults(handler=remove_tree)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    try:
        args.handler(args)
    except PathOperationError as error:
        fail(str(error))


if __name__ == "__main__":
    main()
