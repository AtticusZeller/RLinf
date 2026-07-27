#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
experiment_dir="${repo_dir}/experiments/rlt-maniskill"
persist_dir="/mnt/data/atticux/rlt-maniskill"

export REPO_PATH="${repo_dir}"
export EMBODIED_PATH="${repo_dir}/examples/embodiment"
export PYTHONPATH="${repo_dir}:${PYTHONPATH:-}"
export MUJOCO_GL="${MUJOCO_GL:-egl}"
export PYOPENGL_PLATFORM="${PYOPENGL_PLATFORM:-egl}"
export VK_ICD_FILENAMES="${experiment_dir}/nvidia_icd.json"
export __EGL_VENDOR_LIBRARY_FILENAMES="${experiment_dir}/10_nvidia.json"
export MS_ASSET_DIR="${persist_dir}/runtime-assets/.maniskill"
export SAPIEN_PHYSX_LIB_PATH="${persist_dir}/runtime-assets/.sapien/physx/105.1-physx-5.3.1.patch0"

venv_dir="${RLINF_VENV:-${repo_dir}/.venv}"
export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-${venv_dir}}"
export UV_NO_SYNC="${UV_NO_SYNC:-1}"
source "${venv_dir}/bin/activate"

case "${1:-}" in
  stage1-smoke|stage1-full)
    python "${repo_dir}/examples/sft/train_vla_sft.py" \
      --config-path "${experiment_dir}" --config-name "$1"
    ;;
  stage2-smoke|stage2-full)
    python "${repo_dir}/examples/embodiment/train_embodied_agent.py" \
      --config-path "${experiment_dir}" --config-name "$1"
    ;;
  stage2-learning-smoke)
    python "${repo_dir}/examples/embodiment/train_embodied_agent.py" \
      --config-path "${experiment_dir}" --config-name stage2-smoke \
      +smoke@_global_=stage2-learning
    ;;
  stage2-12h)
    python "${repo_dir}/examples/embodiment/train_embodied_agent.py" \
      --config-path "${experiment_dir}" --config-name stage2-full \
      +budget@_global_=stage2-12h
    ;;
  check)
    python - <<'PY'
import pathlib
import torch
import mani_skill
import openpi
import wandb

root = pathlib.Path('/mnt/data/atticux/rlt-maniskill')
required = [
    root / 'models/pi05_base/model.safetensors',
    root / 'data/maniskill_peginsertionside_joint/norm_stats.json',
]
missing = [str(path) for path in required if not path.is_file()]
if missing:
    raise SystemExit(f'Missing required assets: {missing}')
if not torch.cuda.is_available():
    raise SystemExit('CUDA is unavailable')
if not wandb.login(verify=True):
    raise SystemExit('W&B authentication failed')
print(f'CUDA GPUs: {torch.cuda.device_count()}')
print(f'ManiSkill: {mani_skill.__version__}')
print(f'OpenPI: {openpi.__file__}')
PY
    ;;
  *)
    echo "Usage: $0 {check|stage1-smoke|stage2-smoke|stage1-full|stage2-full}" >&2
    exit 2
    ;;
esac
