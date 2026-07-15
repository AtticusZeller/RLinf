import importlib.util
import json
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

SCRIPT_PATH = Path(__file__).parents[2] / "toolkits/lerobot/subset_lerobot_dataset.py"
SPEC = importlib.util.spec_from_file_location("subset_lerobot_dataset", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))


def _make_source(root: Path, episode_count: int = 10) -> None:
    (root / "meta").mkdir(parents=True)
    (root / "data" / "chunk-000").mkdir(parents=True)
    for key in ("image", "wrist_image"):
        (root / "videos" / "chunk-000" / key).mkdir(parents=True)
    info = {
        "total_episodes": episode_count,
        "total_frames": episode_count * 2,
        "total_videos": episode_count * 2,
        "total_chunks": 1,
        "chunks_size": 1000,
        "features": {
            "image": {"dtype": "video"},
            "wrist_image": {"dtype": "video"},
            "episode_index": {"dtype": "int64"},
            "index": {"dtype": "int64"},
        },
    }
    (root / "meta" / "info.json").write_text(json.dumps(info))
    (root / "meta" / "tasks.jsonl").write_text('{"task_index": 0, "task": "test"}\n')
    (root / "meta" / "stats.json").write_text("{}\n")
    episodes = []
    for episode in range(episode_count):
        episodes.append(
            {
                "episode_index": episode,
                "tasks": ["test"],
                "length": 2,
                "is_success": episode < 4,
            }
        )
        table = pa.table(
            {
                "episode_index": pa.array([episode, episode], type=pa.int64()),
                "index": pa.array([episode * 2, episode * 2 + 1], type=pa.int64()),
                "value": pa.array([1.0, 2.0], type=pa.float32()),
            }
        )
        pq.write_table(
            table, root / "data" / "chunk-000" / f"episode_{episode:06d}.parquet"
        )
        for key in ("image", "wrist_image"):
            (
                root / "videos" / "chunk-000" / key / f"episode_{episode:06d}.mp4"
            ).write_bytes(b"video")
    _write_jsonl(root / "meta" / "episodes.jsonl", episodes)


def test_select_episodes_is_deterministic_and_stratified(tmp_path: Path) -> None:
    source = tmp_path / "source"
    _make_source(source)
    first = MODULE.build_manifest(source, count=5, seed=7, source_repo="org/data")
    second = MODULE.build_manifest(source, count=5, seed=7, source_repo="org/data")

    assert first == second
    assert first["success_count"] == 2
    assert first["failure_count"] == 3
    assert [row["episode_index"] for row in first["episodes"]] == list(range(5))


def test_materialize_subset_reindexes_data_and_videos(tmp_path: Path) -> None:
    source = tmp_path / "source"
    output = tmp_path / "output"
    _make_source(source)
    manifest = MODULE.build_manifest(source, count=4, seed=3, source_repo="org/data")

    MODULE.materialize_subset(source, output, manifest)

    info = json.loads((output / "meta" / "info.json").read_text())
    episodes = MODULE.read_jsonl(output / "meta" / "episodes.jsonl")
    assert info["total_episodes"] == 4
    assert info["total_frames"] == 8
    assert info["total_videos"] == 8
    assert (output / "meta" / "stats.json").read_text() == "{}\n"
    assert [row["episode_index"] for row in episodes] == [0, 1, 2, 3]
    for episode in range(4):
        table = pq.read_table(
            output / "data" / "chunk-000" / f"episode_{episode:06d}.parquet"
        )
        assert table["episode_index"].to_pylist() == [episode, episode]
        assert table["index"].to_pylist() == [episode * 2, episode * 2 + 1]
        for key in ("image", "wrist_image"):
            assert (
                output / "videos" / "chunk-000" / key / f"episode_{episode:06d}.mp4"
            ).read_bytes() == b"video"
