#!/usr/bin/env python3
# Copyright 2026 The RLinf Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""Select and materialize a deterministic stratified LeRobot episode subset."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from typing import Any

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    """Read a JSON Lines file."""
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    """Write records as JSON Lines."""
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )


def select_episodes(
    episodes: list[dict[str, Any]], count: int, seed: int
) -> list[dict[str, Any]]:
    """Select episodes while preserving the source success/failure ratio."""
    if not 0 < count <= len(episodes):
        raise ValueError(f"count must be in [1, {len(episodes)}], got {count}")
    if any("is_success" not in episode for episode in episodes):
        raise ValueError("Every episode must contain is_success for stratification")

    successful = [row for row in episodes if bool(row["is_success"])]
    failed = [row for row in episodes if not bool(row["is_success"])]
    success_count = round(count * len(successful) / len(episodes))
    success_count = min(len(successful), max(0, success_count))
    failure_count = count - success_count
    if failure_count > len(failed):
        failure_count = len(failed)
        success_count = count - failure_count

    rng = np.random.default_rng(seed)
    chosen = [
        *(
            successful[i]
            for i in rng.choice(len(successful), success_count, replace=False)
        ),
        *(failed[i] for i in rng.choice(len(failed), failure_count, replace=False)),
    ]
    chosen.sort(key=lambda row: int(row["episode_index"]))
    return chosen


def build_manifest(
    source_dir: Path, count: int, seed: int, source_repo: str
) -> dict[str, Any]:
    """Build the reproducibility manifest for a subset."""
    episodes = read_jsonl(source_dir / "meta" / "episodes.jsonl")
    selected = select_episodes(episodes, count, seed)
    return {
        "source_repo": source_repo,
        "source_dataset": source_dir.name,
        "selection": "stratified_is_success",
        "seed": seed,
        "source_episode_count": len(episodes),
        "episode_count": len(selected),
        "success_count": sum(bool(row["is_success"]) for row in selected),
        "failure_count": sum(not bool(row["is_success"]) for row in selected),
        "episodes": [
            {
                "source_episode_index": int(row["episode_index"]),
                "episode_index": new_index,
                "is_success": bool(row["is_success"]),
                "length": int(row["length"]),
            }
            for new_index, row in enumerate(selected)
        ],
    }


def build_download_file_list(source_dir: Path, manifest: dict[str, Any]) -> list[str]:
    """Return Hub-relative data and video paths required by a manifest."""
    info = json.loads((source_dir / "meta" / "info.json").read_text())
    chunk_size = int(info.get("chunks_size", 1000))
    video_keys = [
        key
        for key, feature in info.get("features", {}).items()
        if feature.get("dtype") == "video"
    ]
    prefix = manifest["source_dataset"]
    files: list[str] = []
    for episode in manifest["episodes"]:
        index = int(episode["source_episode_index"])
        chunk = index // chunk_size
        files.append(f"{prefix}/data/chunk-{chunk:03d}/episode_{index:06d}.parquet")
        files.extend(
            f"{prefix}/videos/chunk-{chunk:03d}/{key}/episode_{index:06d}.mp4"
            for key in video_keys
        )
    return files


def _replace_integer_column(table: pa.Table, name: str, values: list[int]) -> pa.Table:
    """Replace an integer column while preserving its Arrow type."""
    column_index = table.schema.get_field_index(name)
    if column_index < 0:
        raise ValueError(f"Missing required parquet column: {name}")
    column_type = table.schema.field(column_index).type
    return table.set_column(column_index, name, pa.array(values, type=column_type))


def materialize_subset(
    source_dir: Path, output_dir: Path, manifest: dict[str, Any]
) -> None:
    """Copy selected episodes into a contiguous, self-contained LeRobot dataset."""
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"Output directory is not empty: {output_dir}")

    info = json.loads((source_dir / "meta" / "info.json").read_text())
    source_episodes = {
        int(row["episode_index"]): row
        for row in read_jsonl(source_dir / "meta" / "episodes.jsonl")
    }
    source_chunk_size = int(info.get("chunks_size", 1000))
    video_keys = [
        key
        for key, feature in info.get("features", {}).items()
        if feature.get("dtype") == "video"
    ]

    (output_dir / "meta").mkdir(parents=True, exist_ok=True)
    (output_dir / "data" / "chunk-000").mkdir(parents=True, exist_ok=True)
    for key in video_keys:
        (output_dir / "videos" / "chunk-000" / key).mkdir(parents=True, exist_ok=True)

    output_episodes: list[dict[str, Any]] = []
    global_frame_index = 0
    for selected in manifest["episodes"]:
        source_index = int(selected["source_episode_index"])
        new_index = int(selected["episode_index"])
        source_chunk = source_index // source_chunk_size
        parquet_path = (
            source_dir
            / "data"
            / f"chunk-{source_chunk:03d}"
            / f"episode_{source_index:06d}.parquet"
        )
        table = pq.read_table(parquet_path)
        frame_count = table.num_rows
        table = _replace_integer_column(
            table, "episode_index", [new_index] * frame_count
        )
        table = _replace_integer_column(
            table,
            "index",
            list(range(global_frame_index, global_frame_index + frame_count)),
        )
        pq.write_table(
            table,
            output_dir / "data" / "chunk-000" / f"episode_{new_index:06d}.parquet",
        )

        episode_meta = dict(source_episodes[source_index])
        episode_meta["episode_index"] = new_index
        episode_meta["length"] = frame_count
        output_episodes.append(episode_meta)
        for key in video_keys:
            source_video = (
                source_dir
                / "videos"
                / f"chunk-{source_chunk:03d}"
                / key
                / f"episode_{source_index:06d}.mp4"
            )
            shutil.copy2(
                source_video,
                output_dir
                / "videos"
                / "chunk-000"
                / key
                / f"episode_{new_index:06d}.mp4",
            )
        global_frame_index += frame_count

    info.update(
        {
            "total_episodes": len(output_episodes),
            "total_frames": global_frame_index,
            "total_videos": len(output_episodes) * len(video_keys),
            "total_chunks": 1,
            "chunks_size": 1000,
            "splits": {"train": f"0:{len(output_episodes)}"},
        }
    )
    (output_dir / "meta" / "info.json").write_text(
        json.dumps(info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    write_jsonl(output_dir / "meta" / "episodes.jsonl", output_episodes)
    shutil.copy2(
        source_dir / "meta" / "tasks.jsonl", output_dir / "meta" / "tasks.jsonl"
    )
    source_stats = source_dir / "meta" / "stats.json"
    if source_stats.is_file():
        shutil.copy2(source_stats, output_dir / "meta" / "stats.json")
    (output_dir / "meta" / "subset_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def main() -> None:
    """Run selection or materialization from the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    select_parser = subparsers.add_parser("select")
    select_parser.add_argument("--source-dir", type=Path, required=True)
    select_parser.add_argument("--count", type=int, default=256)
    select_parser.add_argument("--seed", type=int, default=0)
    select_parser.add_argument("--source-repo", required=True)
    select_parser.add_argument("--manifest", type=Path, required=True)
    select_parser.add_argument("--file-list", type=Path, required=True)

    materialize_parser = subparsers.add_parser("materialize")
    materialize_parser.add_argument("--source-dir", type=Path, required=True)
    materialize_parser.add_argument("--output-dir", type=Path, required=True)
    materialize_parser.add_argument("--manifest", type=Path, required=True)

    args = parser.parse_args()
    if args.command == "select":
        manifest = build_manifest(
            args.source_dir, args.count, args.seed, args.source_repo
        )
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        files = build_download_file_list(args.source_dir, manifest)
        args.file_list.write_text("\n".join(files) + "\n", encoding="utf-8")
        print(
            f"Selected {manifest['episode_count']} episodes: "
            f"{manifest['success_count']} success, {manifest['failure_count']} failure"
        )
    else:
        manifest = json.loads(args.manifest.read_text())
        materialize_subset(args.source_dir, args.output_dir, manifest)
        print(f"Materialized {manifest['episode_count']} episodes at {args.output_dir}")


if __name__ == "__main__":
    main()
