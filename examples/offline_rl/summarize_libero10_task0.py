#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///

"""Summarize RECAP and STEAM LIBERO-10 Task 0 evaluation logs."""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
from pathlib import Path

SUCCESS_PATTERN = re.compile(
    r"['\"]eval/success_once['\"]\s*:\s*(?:array\()?([-+0-9.eE]+)"
)
TRAJECTORY_PATTERN = re.compile(
    r"['\"]eval/num_trajectories['\"]\s*:\s*(?:array\()?([0-9]+)"
)


def parse_metric(log_path: Path, pattern: re.Pattern[str], metric: str) -> float:
    """Return the last occurrence of a metric in an evaluation log."""
    matches = pattern.findall(log_path.read_text(encoding="utf-8", errors="replace"))
    if not matches:
        raise ValueError(f"{metric} not found in {log_path}")
    return float(matches[-1])


def wilson_interval(successes: int, total: int, z: float = 1.96) -> tuple[float, float]:
    """Return the Wilson score interval for a binomial success rate."""
    if total <= 0:
        raise ValueError(f"total must be positive, got {total}")
    rate = successes / total
    denominator = 1.0 + z**2 / total
    center = (rate + z**2 / (2 * total)) / denominator
    margin = (
        z * math.sqrt(rate * (1.0 - rate) / total + z**2 / (4 * total**2)) / denominator
    )
    return center - margin, center + margin


def summarize(
    root: Path,
    seeds: list[int],
    expected_trajectories: int = 100,
    methods_to_summarize: tuple[str, ...] = ("baseline", "recap", "steam"),
    baseline_seed: int = 0,
) -> dict[str, object]:
    """Build per-seed and aggregate success-rate results."""
    results: dict[str, object] = {
        "benchmark": "LIBERO-10 Task 0",
        "expected_trajectories_per_evaluation": expected_trajectories,
        "methods": {},
    }
    methods = results["methods"]
    assert isinstance(methods, dict)

    for method in methods_to_summarize:
        seed_results = []
        success_rates = []
        method_seeds = [baseline_seed] if method == "baseline" else seeds
        total_successes = 0
        total_trajectories = 0
        for seed in method_seeds:
            log_path = root / f"seed-{seed}" / method / "eval.log"
            if not log_path.is_file():
                raise FileNotFoundError(f"Missing evaluation log: {log_path}")
            success_rate = parse_metric(log_path, SUCCESS_PATTERN, "eval/success_once")
            if not 0.0 <= success_rate <= 1.0:
                raise ValueError(
                    f"Expected success rate in [0, 1] for {method} seed {seed}, "
                    f"got {success_rate}"
                )
            trajectories = int(
                parse_metric(
                    log_path,
                    TRAJECTORY_PATTERN,
                    "eval/num_trajectories",
                )
            )
            if trajectories != expected_trajectories:
                raise ValueError(
                    f"Expected {expected_trajectories} trajectories for "
                    f"{method} seed {seed}, "
                    f"got {trajectories}"
                )
            successes = round(success_rate * trajectories)
            seed_results.append(
                {
                    "seed": seed,
                    "success_rate": success_rate,
                    "num_trajectories": trajectories,
                    "num_successes": successes,
                }
            )
            success_rates.append(success_rate)
            total_successes += successes
            total_trajectories += trajectories

        ci_low, ci_high = wilson_interval(total_successes, total_trajectories)
        methods[method] = {
            "seeds": seed_results,
            "mean_success_rate": statistics.mean(success_rates),
            "std_success_rate": statistics.stdev(success_rates)
            if len(success_rates) > 1
            else 0.0,
            "total_trajectories": total_trajectories,
            "wilson_95_ci": [ci_low, ci_high],
        }

    baseline_metrics = methods.get("baseline")
    baseline_rate = (
        baseline_metrics["mean_success_rate"]
        if isinstance(baseline_metrics, dict)
        else None
    )
    for method, metrics in methods.items():
        assert isinstance(metrics, dict)
        metrics["delta_vs_baseline_pp"] = (
            None
            if baseline_rate is None or method == "baseline"
            else (metrics["mean_success_rate"] - baseline_rate) * 100.0
        )
    return results


def main() -> None:
    """Parse command-line arguments and write the comparison summary."""
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--seeds", type=int, nargs="+", default=[0])
    parser.add_argument("--baseline-seed", type=int, default=0)
    parser.add_argument("--expected-trajectories", type=int, default=100)
    parser.add_argument(
        "--methods",
        nargs="+",
        default=["baseline", "recap", "steam"],
    )
    args = parser.parse_args()

    results = summarize(
        args.root,
        args.seeds,
        expected_trajectories=args.expected_trajectories,
        methods_to_summarize=tuple(args.methods),
        baseline_seed=args.baseline_seed,
    )
    output_path = args.root / "summary.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(results, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print("method\tmean_success_rate\tstd_success_rate\tdelta_vs_baseline_pp\t95% CI")
    methods = results["methods"]
    assert isinstance(methods, dict)
    for method, metrics in methods.items():
        assert isinstance(metrics, dict)
        delta = metrics["delta_vs_baseline_pp"]
        delta_text = "-" if delta is None else f"{delta:+.2f}"
        ci_low, ci_high = metrics["wilson_95_ci"]
        print(
            f"{method}\t{metrics['mean_success_rate']:.4f}\t"
            f"{metrics['std_success_rate']:.4f}\t{delta_text}\t"
            f"[{ci_low:.4f}, {ci_high:.4f}]"
        )
    print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()
