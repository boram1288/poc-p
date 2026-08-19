#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

import argparse
import hashlib
import json
import struct
from pathlib import Path

MAGIC = b"PVMVIS10"
HEADER = struct.Struct("<8sIIIIIIII32s")
RECORD_PREFIX = struct.Struct("<IIII32s")
DETECTION = struct.Struct("<IIIIII")


def sha256(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def verify(directory: Path):
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    frames = (directory / "frames.bin").read_bytes()
    oracle = (directory / "oracle.bin").read_bytes()
    if sha256(directory / "frames.bin") != manifest["frames_bin_sha256"]:
        raise SystemExit("frames.bin digest mismatch")
    if sha256(directory / "oracle.bin") != manifest["oracle_bin_sha256"]:
        raise SystemExit("oracle.bin digest mismatch")
    fields = HEADER.unpack_from(oracle)
    magic, version, count, page_size, max_detections = fields[:5]
    source_width, source_height, active_size = fields[5:8]
    if magic != MAGIC or version != 1 or count != 30 or page_size != 4096 or max_detections != 16:
        raise SystemExit("oracle header mismatch")
    if active_size != 3072 or len(frames) != count * page_size:
        raise SystemExit("frame geometry mismatch")
    record_size = RECORD_PREFIX.size + max_detections * DETECTION.size
    if len(oracle) != HEADER.size + count * record_size:
        raise SystemExit("oracle size mismatch")
    seen_classes = set()
    for index in range(count):
        page = frames[index * page_size:(index + 1) * page_size]
        if any(page[active_size:]):
            raise SystemExit(f"non-zero page padding at frame {index}")
        offset = HEADER.size + index * record_size
        source_index, detection_count, truncated, reserved, frame_hash = RECORD_PREFIX.unpack_from(oracle, offset)
        if detection_count > max_detections or truncated not in (0, 1) or reserved:
            raise SystemExit(f"bad oracle record {index}")
        if hashlib.sha256(page).digest() != frame_hash:
            raise SystemExit(f"frame hash mismatch {index}")
        if source_index != manifest["records"][index]["source_frame_index"]:
            raise SystemExit(f"source index mismatch {index}")
        offset += RECORD_PREFIX.size
        for detection_index in range(max_detections):
            detection = DETECTION.unpack_from(oracle, offset + detection_index * DETECTION.size)
            if detection_index < detection_count:
                class_id, confidence, xmin, ymin, xmax, ymax = detection
                if class_id > 2 or confidence > 65536 or not (xmin <= xmax <= 65536) or not (ymin <= ymax <= 65536):
                    raise SystemExit(f"invalid detection {index}:{detection_index}")
                seen_classes.add(class_id)
            elif any(detection):
                raise SystemExit(f"non-zero unused detection {index}:{detection_index}")
    if len(seen_classes) < 2:
        raise SystemExit("class coverage gate failed")
    return manifest, source_width, source_height


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--compare", type=Path)
    args = parser.parse_args()
    manifest, width, height = verify(args.fixture)
    if args.compare:
        other, _, _ = verify(args.compare)
        for name in ("frames_bin_sha256", "oracle_bin_sha256"):
            if manifest[name] != other[name]:
                raise SystemExit(f"fixture reproducibility mismatch: {name}")
        left = json.dumps(manifest["records"], sort_keys=True, separators=(",", ":"))
        right = json.dumps(other["records"], sort_keys=True, separators=(",", ":"))
        if left != right:
            raise SystemExit("normalized oracle JSON mismatch")
        print("PVM_VISION_FIXTURE_REPRODUCIBLE_OK")
    print(f"PVM_VISION_FIXTURE_VERIFY_OK: source={width}x{height} classes={manifest['class_ids']}")


if __name__ == "__main__":
    main()
