import importlib.util
from pathlib import Path

import pytest

SCRIPT_PATH = (
    Path(__file__).parents[2] / "examples/offline_rl/summarize_libero10_task0.py"
)
SPEC = importlib.util.spec_from_file_location("recap_steam_summary", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def _write_eval_log(
    root: Path,
    seed: int,
    method: str,
    success: float,
    trajectories: int = 100,
) -> None:
    log_dir = root / f"seed-{seed}" / method
    log_dir.mkdir(parents=True)
    (log_dir / "eval.log").write_text(
        "INFO {'eval/success_once': array("
        f"{success}), 'eval/num_trajectories': {trajectories}}}\n",
        encoding="utf-8",
    )


def test_summarize_mvp_against_baseline(tmp_path: Path) -> None:
    _write_eval_log(tmp_path, 0, "baseline", 0.4)
    _write_eval_log(tmp_path, 0, "recap", 0.5)
    _write_eval_log(tmp_path, 0, "steam", 0.7)

    results = MODULE.summarize(tmp_path, [0])

    baseline = results["methods"]["baseline"]
    recap = results["methods"]["recap"]
    steam = results["methods"]["steam"]
    assert baseline["delta_vs_baseline_pp"] is None
    assert recap["delta_vs_baseline_pp"] == pytest.approx(10.0)
    assert steam["delta_vs_baseline_pp"] == pytest.approx(30.0)
    assert baseline["wilson_95_ci"][0] < 0.4 < baseline["wilson_95_ci"][1]


def test_summarize_three_seed_full_evaluations(tmp_path: Path) -> None:
    for seed, recap, steam in (
        (0, 0.5, 0.7),
        (1, 0.6, 0.8),
        (2, 0.7, 0.9),
    ):
        _write_eval_log(tmp_path, seed, "recap", recap, trajectories=500)
        _write_eval_log(tmp_path, seed, "steam", steam, trajectories=500)

    results = MODULE.summarize(
        tmp_path,
        [0, 1, 2],
        expected_trajectories=500,
        methods_to_summarize=("recap", "steam"),
    )

    assert results["methods"]["recap"]["mean_success_rate"] == pytest.approx(0.6)
    assert results["methods"]["steam"]["mean_success_rate"] == pytest.approx(0.8)
    assert results["methods"]["recap"]["std_success_rate"] == pytest.approx(0.1)


def test_summarize_rejects_incomplete_evaluation(tmp_path: Path) -> None:
    log_dir = tmp_path / "seed-0" / "recap"
    log_dir.mkdir(parents=True)
    (log_dir / "eval.log").write_text(
        "INFO {'eval/success_once': array(0.5), 'eval/num_trajectories': 50}\n",
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="Expected 100 trajectories"):
        MODULE.summarize(
            tmp_path,
            [0],
            methods_to_summarize=("recap",),
        )
