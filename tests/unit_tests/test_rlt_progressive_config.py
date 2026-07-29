# Copyright 2026 The RLinf Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Tests for the medium-budget RLT Stage 2 override."""

from pathlib import Path

import yaml


def test_progressive_config_has_algorithmic_not_wall_clock_limit() -> None:
    config_path = (
        Path(__file__).parents[2]
        / "experiments/rlt-maniskill/budget/stage2-progressive.yaml"
    )
    config = yaml.safe_load(config_path.read_text())

    assert config["runner"]["max_epochs"] == 100
    assert "max_run_duration" not in config["runner"]
    assert config["runner"]["val_check_interval"] == 20
    assert config["runner"]["save_interval"] == 20
    assert config["algorithm"]["rlt_schedule"] == {
        "warmup_min_size": 5000,
        "warmup_post_collect_updates": 10000,
    }
    assert config["env"]["train"]["rlt_policy_switch"]["expert_takeover"]["enable"]
    assert config["env"]["eval"]["total_num_envs"] == 64
    assert config["env"]["eval"]["video_cfg"]["max_envs"] == 4
