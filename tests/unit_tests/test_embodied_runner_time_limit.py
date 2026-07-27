from unittest.mock import MagicMock

from omegaconf import OmegaConf

from rlinf.runners.embodied_runner import EmbodiedRunner


def _runner_for_progress_check() -> EmbodiedRunner:
    runner = EmbodiedRunner.__new__(EmbodiedRunner)
    runner.global_step = 3
    runner.max_steps = 500
    runner.cfg = OmegaConf.create(
        {
            "runner": {
                "val_check_interval": 25,
                "save_interval": 25,
            }
        }
    )
    runner.timer = MagicMock()
    runner.update_rollout_weights = MagicMock()
    runner.evaluate = MagicMock(return_value={"success_once": 0.5})
    runner.metric_logger = MagicMock()
    runner._save_checkpoint = MagicMock()
    return runner


def test_time_limit_forces_final_eval_and_checkpoint():
    runner = _runner_for_progress_check()

    metrics = runner._maybe_eval_and_checkpoint(2, run_time_exceeded=True)

    assert metrics == {"eval/success_once": 0.5}
    runner.update_rollout_weights.assert_called_once_with()
    runner.evaluate.assert_called_once_with()
    runner.metric_logger.log.assert_called_once_with(
        data={"eval/success_once": 0.5},
        step=2,
    )
    runner._save_checkpoint.assert_called_once_with()


def test_regular_step_skips_eval_and_checkpoint_between_intervals():
    runner = _runner_for_progress_check()

    metrics = runner._maybe_eval_and_checkpoint(2)

    assert metrics == {}
    runner.update_rollout_weights.assert_not_called()
    runner.evaluate.assert_not_called()
    runner.metric_logger.log.assert_not_called()
    runner._save_checkpoint.assert_not_called()
