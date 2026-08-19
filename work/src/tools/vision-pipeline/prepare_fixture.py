#!/usr/bin/env python3
# SPDX-License-Identifier: MIT

import argparse
import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

VIDEO_SHA256 = "452b11b7e0efbd019f1d9570d0c790e90416ad4ad29eec6003872d08443140ef"
MODEL_XML_SHA384 = "8c4f1a14c1e00709391c2bded1157d4497cf56be6a1d919b09747cecef183380dbae659a5c555dedbc81b9e4da579096"
MODEL_BIN_SHA384 = "2217e4a07f0fe94a2e13bb80c359c4d6125454956e08e806eacc81176a888060f573a7f7352c5a4f4fa0288f2c53bb78"
OMZ_COMMIT = "7cc29a91472b4cb1289a11e655ba3e188e1d4a31"
MAGIC = b"PVMVIS10"
VERSION = 1
FRAME_COUNT = 30
WIDTH = 32
HEIGHT = 32
STRIDE = WIDTH * 3
ACTIVE_SIZE = STRIDE * HEIGHT
PAGE_SIZE = 4096
MAX_DETECTIONS = 16
HEADER = struct.Struct("<8sIIIIIIII32s")
RECORD_PREFIX = struct.Struct("<IIII32s")
DETECTION = struct.Struct("<IIIIII")
FRAME_RE = re.compile(r"Frame #\s+(\d+)")
DET_RE = re.compile(
    r"^\[ DEBUG \]\s+#(\d+)\s+\|\s+([0-9.]+)\s+\|\s+(-?\d+)\s+\|"
    r"\s+(-?\d+)\s+\|\s+(-?\d+)\s+\|\s+(-?\d+)"
)


def digest(path: Path, algorithm: str) -> str:
    value = hashlib.new(algorithm)
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def q16(value: float) -> int:
    return min(65536, max(0, int(value * 65536.0 + 0.5)))


def parse_demo_log(path: Path, source_width: int, source_height: int):
    by_frame = {}
    current = None
    openvino_build = "unknown"
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("[ INFO ] \tbuild:"):
            openvino_build = line.split("build:", 1)[1].strip()
        match = FRAME_RE.search(line)
        if match:
            current = int(match.group(1))
            by_frame.setdefault(current, [])
            continue
        match = DET_RE.match(line)
        if not match or current is None:
            continue
        class_id = int(match.group(1))
        confidence = float(match.group(2))
        xmin, ymin, xmax, ymax = (int(match.group(i)) for i in range(3, 7))
        if class_id not in (0, 1, 2) or confidence < 0.5:
            continue
        by_frame[current].append(
            {
                "class_id": class_id,
                "confidence_q16": q16(confidence),
                "xmin_q16": q16(xmin / source_width),
                "ymin_q16": q16(ymin / source_height),
                "xmax_q16": q16(xmax / source_width),
                "ymax_q16": q16(ymax / source_height),
            }
        )
    return by_frame, openvino_build


def probe(ffprobe: str, video: Path):
    command = [
        ffprobe,
        "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,nb_frames,avg_frame_rate",
        "-of", "json", str(video),
    ]
    stream = json.loads(subprocess.check_output(command))["streams"][0]
    return int(stream["width"]), int(stream["height"]), int(stream["nb_frames"]), stream["avg_frame_rate"]


def decode(ffmpeg: str, video: Path):
    command = [
        ffmpeg, "-v", "error", "-i", str(video), "-an",
        "-vf", f"scale={WIDTH}:{HEIGHT}:flags=bilinear",
        "-pix_fmt", "bgr24", "-f", "rawvideo", "-",
    ]
    return subprocess.check_output(command)


def selected_indices(total: int):
    return [(index * (total - 1) + (FRAME_COUNT - 1) // 2) // (FRAME_COUNT - 1)
            for index in range(FRAME_COUNT)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--model-xml", required=True, type=Path)
    parser.add_argument("--model-bin", required=True, type=Path)
    parser.add_argument("--demo-log", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    args = parser.parse_args()

    if digest(args.video, "sha256") != VIDEO_SHA256:
        raise SystemExit("video SHA-256 mismatch")
    if digest(args.model_xml, "sha384") != MODEL_XML_SHA384:
        raise SystemExit("model XML SHA-384 mismatch")
    if digest(args.model_bin, "sha384") != MODEL_BIN_SHA384:
        raise SystemExit("model BIN SHA-384 mismatch")

    source_width, source_height, total_frames, frame_rate = probe(args.ffprobe, args.video)
    raw = decode(args.ffmpeg, args.video)
    if len(raw) % ACTIVE_SIZE:
        raise SystemExit("decoded raw frame stream is misaligned")
    decoded_frames = len(raw) // ACTIVE_SIZE
    if decoded_frames != total_frames:
        raise SystemExit(f"frame count mismatch: probe={total_frames} decode={decoded_frames}")

    detections, openvino_build = parse_demo_log(args.demo_log, source_width, source_height)
    indices = selected_indices(total_frames)
    args.output.mkdir(parents=True, exist_ok=True)
    frames_path = args.output / "frames.bin"
    oracle_path = args.output / "oracle.bin"
    records = []
    seen_classes = set()

    with frames_path.open("wb") as frame_file, oracle_path.open("wb") as oracle_file:
        oracle_file.write(HEADER.pack(
            MAGIC, VERSION, FRAME_COUNT, PAGE_SIZE, MAX_DETECTIONS,
            source_width, source_height, ACTIVE_SIZE, 0,
            bytes.fromhex(VIDEO_SHA256),
        ))
        for source_index in indices:
            start = source_index * ACTIVE_SIZE
            page = raw[start:start + ACTIVE_SIZE] + bytes(PAGE_SIZE - ACTIVE_SIZE)
            frame_hash = hashlib.sha256(page).digest()
            frame_file.write(page)
            frame_detections = detections.get(source_index, [])
            frame_detections.sort(key=lambda item: (
                -item["confidence_q16"], item["class_id"], item["xmin_q16"],
                item["ymin_q16"], item["xmax_q16"], item["ymax_q16"],
            ))
            truncated = int(len(frame_detections) > MAX_DETECTIONS)
            frame_detections = frame_detections[:MAX_DETECTIONS]
            seen_classes.update(item["class_id"] for item in frame_detections)
            oracle_file.write(RECORD_PREFIX.pack(
                source_index, len(frame_detections), truncated, 0, frame_hash,
            ))
            for item in frame_detections:
                oracle_file.write(DETECTION.pack(
                    item["class_id"], item["confidence_q16"], item["xmin_q16"],
                    item["ymin_q16"], item["xmax_q16"], item["ymax_q16"],
                ))
            oracle_file.write(bytes((MAX_DETECTIONS - len(frame_detections)) * DETECTION.size))
            records.append({
                "source_frame_index": source_index,
                "frame_sha256": frame_hash.hex(),
                "detection_count": len(frame_detections),
                "truncated": bool(truncated),
                "detections": frame_detections,
            })

    if len(seen_classes) < 2:
        raise SystemExit(f"fixture class gate failed: classes={sorted(seen_classes)}")

    ffmpeg_version = subprocess.check_output([args.ffmpeg, "-version"], text=True).splitlines()[0]
    manifest = {
        "fixture_version": VERSION,
        "open_model_zoo_commit": OMZ_COMMIT,
        "video_sha256": VIDEO_SHA256,
        "model_xml_sha384": MODEL_XML_SHA384,
        "model_bin_sha384": MODEL_BIN_SHA384,
        "openvino_build": openvino_build,
        "ffmpeg_version": ffmpeg_version,
        "source_width": source_width,
        "source_height": source_height,
        "source_frame_count": total_frames,
        "source_frame_rate": frame_rate,
        "selection": "nearest(i * (total_frames - 1) / 29), i=0..29",
        "resize": "ffmpeg scale=32:32:flags=bilinear,pix_fmt=bgr24",
        "page_size": PAGE_SIZE,
        "active_size": ACTIVE_SIZE,
        "frame_count": FRAME_COUNT,
        "max_detections": MAX_DETECTIONS,
        "class_ids": sorted(seen_classes),
        "demo_log_sha256": digest(args.demo_log, "sha256"),
        "frames_bin_sha256": digest(frames_path, "sha256"),
        "oracle_bin_sha256": digest(oracle_path, "sha256"),
        "records": records,
    }
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"PVM_VISION_FIXTURE_OK: frames={FRAME_COUNT} classes={','.join(map(str, sorted(seen_classes)))}")
    print(f"PVM_VISION_FRAMES_SHA256: {manifest['frames_bin_sha256']}")
    print(f"PVM_VISION_ORACLE_SHA256: {manifest['oracle_bin_sha256']}")


if __name__ == "__main__":
    main()
