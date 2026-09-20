import hashlib
import os

CHUNK = 256 * 1024


def content_hash(path: str) -> str:
    size = os.path.getsize(path)
    digest = hashlib.sha256()
    digest.update(size.to_bytes(8, "little"))
    with open(path, "rb") as handle:
        digest.update(handle.read(CHUNK))
        if size > CHUNK * 2:
            handle.seek(max(0, size // 2 - CHUNK // 2))
            digest.update(handle.read(CHUNK))
        if size > CHUNK:
            handle.seek(max(0, size - CHUNK))
            digest.update(handle.read(CHUNK))
    return digest.hexdigest()
