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

"""Tests for bounded multi-environment video recording."""

from pathlib import Path

import numpy as np
import pytest
from omegaconf import OmegaConf

from rlinf.envs.wrappers.record_video import RecordVideo


class _DummyEnv:
    seed = 7
    num_envs = 25


def test_record_video_limits_tiled_environments() -> None:
    wrapper = RecordVideo(
        _DummyEnv(),
        {"info_on_video": False, "max_envs": 4},
        fps=10,
    )
    try:
        images = np.zeros((25, 8, 8, 3), dtype=np.uint8)
        wrapper.add_new_frames({"images": images})
        assert len(wrapper.render_images) == 1
        assert wrapper.render_images[0].shape == (16, 16, 3)
    finally:
        wrapper._executor.shutdown(wait=True)


def test_record_video_rejects_nonpositive_max_envs() -> None:
    with pytest.raises(ValueError, match="max_envs must be greater than zero"):
        RecordVideo(_DummyEnv(), {"max_envs": 0}, fps=10)


def test_record_video_finalizes_mp4_before_copy(tmp_path: Path) -> None:
    wrapper = RecordVideo(
        _DummyEnv(),
        OmegaConf.create(
            {
                "info_on_video": False,
                "max_envs": 4,
                "video_base_dir": str(tmp_path),
            }
        ),
        fps=10,
    )
    images = np.zeros((4, 8, 8, 3), dtype=np.uint8)
    wrapper.add_new_frames({"images": images})
    wrapper.flush_video()
    wrapper._executor.shutdown(wait=True)

    video_path = tmp_path / "seed_7" / "0.mp4"
    assert video_path.is_file()
    assert b"moov" in video_path.read_bytes()
