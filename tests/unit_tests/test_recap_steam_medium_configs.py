from pathlib import Path

import yaml

CONFIG_DIR = Path(__file__).parents[2] / "examples/offline_rl/config/experiment"


def _load_config(name: str) -> dict:
    return yaml.safe_load((CONFIG_DIR / name).read_text())


def test_recap_medium_returns_cover_value_validation_datasets() -> None:
    returns = _load_config("recap_libero10_task0_medium_returns.yaml")
    value = _load_config("recap_libero10_task0_medium_value.yaml")

    returns_paths = {
        entry["dataset_path"] for entry in returns["data"]["train_data_paths"]
    }
    validation_paths = {
        entry["dataset_path"] for entry in value["data"]["eval_data_paths"]
    }

    assert validation_paths <= returns_paths
    assert returns["data"]["tag"] == value["data"]["tag"]
