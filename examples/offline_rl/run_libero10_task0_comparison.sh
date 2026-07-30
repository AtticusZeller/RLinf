#!/usr/bin/env bash

set -euo pipefail

# Video batches share many tensors between DataLoader workers. The default DSW
# soft limit (1024) is too low even though the host hard limit is much higher.
if ! ulimit -n "${RLINF_OPEN_FILES_LIMIT:-65536}"; then
    echo "Warning: could not raise the open-file limit; advantage labeling may fail." >&2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENV_PATH="${RLINF_VENV_PATH:-${REPO_PATH}/.venv}"

if [[ ! -f "${VENV_PATH}/bin/activate" ]]; then
    echo "Missing RLinf virtual environment: ${VENV_PATH}" >&2
    echo "Install the embodied OpenPI/LIBERO environment before running this experiment." >&2
    exit 1
fi
# The installer appends the local LIBERO checkout and simulator variables here.
export PYTHONPATH="${PYTHONPATH:-}"
source "${VENV_PATH}/bin/activate"

configure_python_shared_library() {
    local python_version
    local library_name
    local library_path="${RLINF_PYTHON_SHARED_LIB_DIR:-}"

    python_version="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    library_name="libpython${python_version}.so.1.0"
    if [[ -z "${library_path}" ]]; then
        library_path="$(find "${HOME}/miniconda3" -path "*/lib/${library_name}" \
            -printf '%h\n' -quit 2>/dev/null || true)"
    fi
    if [[ -n "${library_path}" && -f "${library_path}/${library_name}" ]]; then
        export LD_LIBRARY_PATH="${library_path}:${LD_LIBRARY_PATH:-}"
    fi
}

# TorchCodec wheels link against libpython, while this DSW image ships a
# static system Python. Reuse the shared library from an installed Conda Python.
configure_python_shared_library

export REPO_PATH
export EMBODIED_PATH="${REPO_PATH}/examples/embodiment"
export ROBOT_PLATFORM="${ROBOT_PLATFORM:-LIBERO}"
export MUJOCO_GL="${MUJOCO_GL:-egl}"
export PYOPENGL_PLATFORM="${PYOPENGL_PLATFORM:-egl}"
export PYTHONPATH="${REPO_PATH}:${PYTHONPATH:-}"

MVP_EXPERIMENT_ROOT="${RLINF_EXPERIMENT_ROOT:-/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-mvp}"
MEDIUM_EXPERIMENT_ROOT="${RLINF_MEDIUM_EXPERIMENT_ROOT:-/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-medium}"
FULL_EXPERIMENT_ROOT="${RLINF_FULL_EXPERIMENT_ROOT:-/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-full}"
export RLINF_RECAP_MVP_DATA_ROOT="${RLINF_RECAP_MVP_DATA_ROOT:-/mnt/data/atticux/rlinf/datasets/RECAP-Libero10-Task0-MVP}"
MVP_DATA_ARCHIVE_ROOT="${RLINF_RECAP_MVP_DATA_ROOT}"
MVP_DATA_CACHE_ROOT="${RLINF_RECAP_MVP_CACHE_ROOT:-${HOME}/.cache/rlinf/datasets/RECAP-Libero10-Task0-MVP}"
export RLINF_RECAP_MEDIUM_DATA_ROOT="${RLINF_RECAP_MEDIUM_DATA_ROOT:-/mnt/data/atticux/rlinf/datasets/RECAP-Libero10-Task0-Medium}"
MEDIUM_DATA_ARCHIVE_ROOT="${RLINF_RECAP_MEDIUM_DATA_ROOT}"
MEDIUM_DATA_CACHE_ROOT="${RLINF_RECAP_MEDIUM_CACHE_ROOT:-${HOME}/.cache/rlinf/datasets/RECAP-Libero10-Task0-Medium}"
export RLINF_RECAP_DATA_ROOT="${RLINF_RECAP_DATA_ROOT:-/mnt/data/atticux/rlinf/datasets/RECAP-Libero10-Task0-48succ-Data}"
export RLINF_PI05_MODEL_PATH="${RLINF_PI05_MODEL_PATH:-/mnt/data/atticux/rlinf/models/RLinf-Pi05-LIBERO-SFT}"
export RLINF_RECAP_SIGLIP_PATH="${RLINF_RECAP_SIGLIP_PATH:-/mnt/data/atticux/rlinf/models/siglip2-so400m-patch14-224}"
export RLINF_STEAM_SIGLIP_PATH="${RLINF_STEAM_SIGLIP_PATH:-/mnt/data/atticux/rlinf/models/siglip-so400m-patch14-384}"
export RLINF_GEMMA_PATH="${RLINF_GEMMA_PATH:-/mnt/data/atticux/rlinf/models/gemma-3-270m}"
STEAM_MEDIUM_RESUME_DIR="${RLINF_STEAM_MEDIUM_RESUME_DIR:-}"
STEAM_MEDIUM_BASELINE_ROOT="${RLINF_STEAM_MEDIUM_BASELINE_ROOT:-}"
HF_STAGING_ROOT="${RLINF_HF_STAGING_ROOT:-${HOME}/.cache/rlinf-hf-stage}"

detect_nproc() {
    local detected
    detected="$(nvidia-smi -L 2>/dev/null | wc -l || true)"
    if [[ "${detected}" -lt 1 ]]; then
        detected=1
    fi
    echo "${RLINF_NPROC:-${detected}}"
}

require_dir() {
    local path="$1"
    if [[ ! -d "${path}" ]]; then
        echo "Missing required directory: ${path}" >&2
        exit 1
    fi
}

require_file() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
        echo "Missing required file: ${path}" >&2
        exit 1
    fi
}

validate_seed() {
    if [[ ! "$1" =~ ^[0-9]+$ ]]; then
        echo "Seed must be a non-negative integer, got: $1" >&2
        exit 2
    fi
}

check_models() {
    require_dir "${RLINF_PI05_MODEL_PATH}"
    require_dir "${RLINF_RECAP_SIGLIP_PATH}"
    require_dir "${RLINF_STEAM_SIGLIP_PATH}"
    require_dir "${RLINF_GEMMA_PATH}"
}

check_mvp_assets() {
    require_dir "${RLINF_RECAP_MVP_DATA_ROOT}/libero10_task0_sft"
    require_dir "${RLINF_RECAP_MVP_DATA_ROOT}/libero10_task0_eval"
    check_models
}

stage_mvp_data() {
    if [[ "${RLINF_RECAP_MVP_DATA_ROOT}" == "${MVP_DATA_CACHE_ROOT}" ]]; then
        return
    fi
    require_dir "${MVP_DATA_ARCHIVE_ROOT}/libero10_task0_sft"
    require_dir "${MVP_DATA_ARCHIVE_ROOT}/libero10_task0_eval"
    mkdir -p "${MVP_DATA_CACHE_ROOT}"
    cp -a -u "${MVP_DATA_ARCHIVE_ROOT}/libero10_task0_sft" "${MVP_DATA_CACHE_ROOT}/"
    cp -a -u "${MVP_DATA_ARCHIVE_ROOT}/libero10_task0_eval" "${MVP_DATA_CACHE_ROOT}/"
    export RLINF_RECAP_MVP_DATA_ROOT="${MVP_DATA_CACHE_ROOT}"
}

sync_mvp_metadata() {
    local dataset
    if [[ "${RLINF_RECAP_MVP_DATA_ROOT}" == "${MVP_DATA_ARCHIVE_ROOT}" ]]; then
        return
    fi
    for dataset in libero10_task0_sft libero10_task0_eval; do
        cp -a "${RLINF_RECAP_MVP_DATA_ROOT}/${dataset}/meta/." \
            "${MVP_DATA_ARCHIVE_ROOT}/${dataset}/meta/"
    done
}

check_medium_assets() {
    require_dir "${MVP_DATA_ARCHIVE_ROOT}/libero10_task0_sft"
    require_dir "${MVP_DATA_ARCHIVE_ROOT}/libero10_task0_eval"
    require_file "${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train/meta/subset_manifest.json"
    check_models
}

stage_medium_data() {
    stage_mvp_data
    if [[ "${RLINF_RECAP_MEDIUM_DATA_ROOT}" == "${MEDIUM_DATA_CACHE_ROOT}" ]]; then
        return
    fi
    require_dir "${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train"
    mkdir -p "${MEDIUM_DATA_CACHE_ROOT}"
    cp -a -u "${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train" "${MEDIUM_DATA_CACHE_ROOT}/"
    export RLINF_RECAP_MEDIUM_DATA_ROOT="${MEDIUM_DATA_CACHE_ROOT}"
}

sync_medium_metadata() {
    sync_mvp_metadata
    if [[ "${RLINF_RECAP_MEDIUM_DATA_ROOT}" == "${MEDIUM_DATA_ARCHIVE_ROOT}" ]]; then
        return
    fi
    cp -a "${RLINF_RECAP_MEDIUM_DATA_ROOT}/libero10_task0_train/meta/." \
        "${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train/meta/"
}

check_full_assets() {
    require_dir "${RLINF_RECAP_DATA_ROOT}/libero10_task0_sft"
    require_dir "${RLINF_RECAP_DATA_ROOT}/libero10_task0_train"
    require_dir "${RLINF_RECAP_DATA_ROOT}/libero10_task0_eval"
    check_models
}

check_download_prerequisites() {
    local mount_options
    mount_options="$(findmnt -no OPTIONS -T /mnt/data)"
    if [[ ",${mount_options}," != *,rw,* ]]; then
        echo "/mnt/data is not writable (options: ${mount_options})." >&2
        exit 1
    fi
    command -v hf >/dev/null || {
        echo "The hf CLI is required. Install it with:" >&2
        echo "  curl -LsSf https://hf.co/cli/install.sh | bash -s" >&2
        exit 1
    }
    if ! hf auth whoami >/dev/null 2>&1; then
        echo "Hugging Face login is required. Run: hf auth login" >&2
        exit 1
    fi
}

copy_from_staging() {
    local source="$1"
    local destination="$2"
    mkdir -p "${destination}"
    find "${source}" -mindepth 1 -maxdepth 1 ! -name .cache \
        -exec cp -a -t "${destination}" {} +
}

download_models() {
    local workers="${RLINF_HF_MAX_WORKERS:-4}"
    local stage

    stage="${HF_STAGING_ROOT}/models/RLinf-Pi05-LIBERO-SFT"
    hf download RLinf/RLinf-Pi05-LIBERO-SFT \
        --max-workers "${workers}" \
        --local-dir "${stage}"
    copy_from_staging "${stage}" "${RLINF_PI05_MODEL_PATH}"

    stage="${HF_STAGING_ROOT}/models/siglip2-so400m-patch14-224"
    hf download google/siglip2-so400m-patch14-224 \
        --max-workers "${workers}" \
        --local-dir "${stage}"
    copy_from_staging "${stage}" "${RLINF_RECAP_SIGLIP_PATH}"

    stage="${HF_STAGING_ROOT}/models/siglip-so400m-patch14-384"
    hf download google/siglip-so400m-patch14-384 \
        --max-workers "${workers}" \
        --local-dir "${stage}"
    copy_from_staging "${stage}" "${RLINF_STEAM_SIGLIP_PATH}"

    stage="${HF_STAGING_ROOT}/models/gemma-3-270m"
    hf download google/gemma-3-270m \
        --max-workers "${workers}" \
        --local-dir "${stage}"
    copy_from_staging "${stage}" "${RLINF_GEMMA_PATH}"
}

prepare_mvp_assets() {
    local workers="${RLINF_HF_MAX_WORKERS:-4}"
    local stage="${HF_STAGING_ROOT}/datasets/RECAP-Libero10-Task0-MVP"
    check_download_prerequisites
    hf download RLinf/RECAP-Libero10-Task0-48succ-Data \
        --repo-type dataset \
        --include 'libero10_task0_sft/**' \
        --include 'libero10_task0_eval/**' \
        --max-workers "${workers}" \
        --local-dir "${stage}"
    copy_from_staging "${stage}" "${RLINF_RECAP_MVP_DATA_ROOT}"
    download_models
    check_mvp_assets
}

prepare_medium_assets() {
    local workers="${RLINF_HF_MAX_WORKERS:-4}"
    local stage="${HF_STAGING_ROOT}/datasets/RECAP-Libero10-Task0-Medium-Source"
    local source_dir="${stage}/libero10_task0_train"
    local selection_dir="${stage}/.medium-selection"
    local manifest="${selection_dir}/manifest.json"
    local file_list="${selection_dir}/files.txt"
    local -a selected_files

    check_download_prerequisites
    prepare_mvp_assets
    hf download RLinf/RECAP-Libero10-Task0-48succ-Data \
        --repo-type dataset \
        --include 'libero10_task0_train/meta/**' \
        --max-workers "${workers}" \
        --local-dir "${stage}"
    mkdir -p "${selection_dir}"
    python "${REPO_PATH}/toolkits/lerobot/subset_lerobot_dataset.py" select \
        --source-dir "${source_dir}" \
        --count 256 \
        --seed 0 \
        --source-repo RLinf/RECAP-Libero10-Task0-48succ-Data \
        --manifest "${manifest}" \
        --file-list "${file_list}"
    mapfile -t selected_files < "${file_list}"
    hf download RLinf/RECAP-Libero10-Task0-48succ-Data \
        "${selected_files[@]}" \
        --repo-type dataset \
        --max-workers "${workers}" \
        --local-dir "${stage}"

    if [[ ! -f "${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train/meta/subset_manifest.json" ]]; then
        if [[ -e "${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train" ]]; then
            echo "Incomplete medium dataset already exists: ${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train" >&2
            exit 1
        fi
        mkdir -p "${MEDIUM_DATA_ARCHIVE_ROOT}"
        python "${REPO_PATH}/toolkits/lerobot/subset_lerobot_dataset.py" materialize \
            --source-dir "${source_dir}" \
            --output-dir "${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train" \
            --manifest "${manifest}"
    else
        echo "Reusing medium rollout subset: ${MEDIUM_DATA_ARCHIVE_ROOT}/libero10_task0_train"
    fi
    check_medium_assets
}

prepare_full_assets() {
    local workers="${RLINF_HF_MAX_WORKERS:-4}"
    local stage="${HF_STAGING_ROOT}/datasets/RECAP-Libero10-Task0-Full"
    check_download_prerequisites
    hf download RLinf/RECAP-Libero10-Task0-48succ-Data \
        --repo-type dataset \
        --max-workers "${workers}" \
        --local-dir "${stage}"
    copy_from_staging "${stage}" "${RLINF_RECAP_DATA_ROOT}"
    download_models
    check_full_assets
}

run_recap_mvp() {
    local advantage_eval
    local advantage_sft
    local seed="$1"
    local nproc
    local policy_checkpoint
    local run_root
    local value_checkpoint

    validate_seed "${seed}"
    stage_mvp_data
    check_mvp_assets
    export RLINF_EXPERIMENT_SEED="${seed}"
    nproc="$(detect_nproc)"
    run_root="${MVP_EXPERIMENT_ROOT}/seed-${seed}/recap"
    mkdir -p "${run_root}"

    bash "${SCRIPT_DIR}/advantage_labeling/recap/process/run_compute_returns.sh" \
        recap_compute_returns \
        +experiment@_global_=recap_libero10_task0_mvp_returns
    value_checkpoint="${run_root}/value/checkpoints/global_step_1000/actor"
    if [[ ! -d "${value_checkpoint}" ]]; then
        bash "${SCRIPT_DIR}/advantage_labeling/recap/run_value_sft.sh" \
            recap_value_model_sft \
            +experiment@_global_=recap_libero10_task0_mvp_value \
            "runner.logger.log_path=${run_root}"
    else
        echo "Reusing RECAP value checkpoint: ${value_checkpoint}"
    fi
    require_dir "${value_checkpoint}"
    advantage_sft="${RLINF_RECAP_MVP_DATA_ROOT}/libero10_task0_sft/meta/advantages_recap_task0_mvp_seed${seed}_q30.parquet"
    advantage_eval="${RLINF_RECAP_MVP_DATA_ROOT}/libero10_task0_eval/meta/advantages_recap_task0_mvp_seed${seed}_q30.parquet"
    if [[ ! -f "${advantage_sft}" || ! -f "${advantage_eval}" ]]; then
        bash "${SCRIPT_DIR}/advantage_labeling/recap/process/run_compute_advantages.sh" \
            recap_compute_advantages \
            --nproc "${nproc}" \
            +experiment@_global_=recap_libero10_task0_mvp_advantages \
            "advantage.value_checkpoint=${value_checkpoint}"
    else
        echo "Reusing RECAP advantage sidecars for seed ${seed}."
    fi
    sync_mvp_metadata
    policy_checkpoint="${run_root}/policy/checkpoints/global_step_200/actor/model_state_dict/full_weights.pt"
    if [[ ! -f "${policy_checkpoint}" ]]; then
        bash "${SCRIPT_DIR}/policy_optimization/cfg_rl/run_cfg_rl.sh" \
            cfg_rl_openpi \
            +experiment@_global_=recap_libero10_task0_mvp_cfg \
            "runner.logger.log_path=${run_root}"
    else
        echo "Reusing RECAP policy checkpoint: ${policy_checkpoint}"
    fi
    require_file "${policy_checkpoint}"
}

run_steam_mvp() {
    local advantage_eval
    local advantage_sft
    local seed="$1"
    local nproc
    local policy_checkpoint
    local run_root
    local value_checkpoint

    validate_seed "${seed}"
    stage_mvp_data
    check_mvp_assets
    export RLINF_EXPERIMENT_SEED="${seed}"
    nproc="$(detect_nproc)"
    run_root="${MVP_EXPERIMENT_ROOT}/seed-${seed}/steam"
    mkdir -p "${run_root}"

    value_checkpoint="${run_root}/value/checkpoints/global_step_100/actor"
    if [[ ! -d "${value_checkpoint}" ]]; then
        bash "${SCRIPT_DIR}/advantage_labeling/steam/run_steam_sft.sh" \
            steam_value_model_sft \
            +experiment@_global_=steam_libero10_task0_mvp_value \
            "runner.logger.log_path=${run_root}"
    else
        echo "Reusing STEAM value checkpoint: ${value_checkpoint}"
    fi
    require_dir "${value_checkpoint}"
    advantage_sft="${RLINF_RECAP_MVP_DATA_ROOT}/libero10_task0_sft/meta/advantages_steam_task0_mvp_seed${seed}_k32_e3_q30.parquet"
    advantage_eval="${RLINF_RECAP_MVP_DATA_ROOT}/libero10_task0_eval/meta/advantages_steam_task0_mvp_seed${seed}_k32_e3_q30.parquet"
    if [[ ! -f "${advantage_sft}" || ! -f "${advantage_eval}" ]]; then
        bash "${SCRIPT_DIR}/advantage_labeling/steam/process/run_compute_advantages_ensemble.sh" \
            steam_compute_advantages_ensemble \
            --nproc "${nproc}" \
            +experiment@_global_=steam_libero10_task0_mvp_advantages \
            "advantage.value_checkpoint=${value_checkpoint}"
    else
        echo "Reusing STEAM advantage sidecars for seed ${seed}."
    fi
    sync_mvp_metadata
    policy_checkpoint="${run_root}/policy/checkpoints/global_step_200/actor/model_state_dict/full_weights.pt"
    if [[ ! -f "${policy_checkpoint}" ]]; then
        bash "${SCRIPT_DIR}/policy_optimization/cfg_rl/run_cfg_rl.sh" \
            cfg_rl_openpi \
            +experiment@_global_=steam_libero10_task0_mvp_cfg \
            "runner.logger.log_path=${run_root}"
    else
        echo "Reusing STEAM policy checkpoint: ${policy_checkpoint}"
    fi
    require_file "${policy_checkpoint}"
}

run_recap_medium() {
    local advantage_sft
    local advantage_train
    local seed="$1"
    local nproc
    local policy_checkpoint
    local run_root
    local value_checkpoint

    validate_seed "${seed}"
    stage_medium_data
    check_medium_assets
    export RLINF_EXPERIMENT_SEED="${seed}"
    nproc="$(detect_nproc)"
    run_root="${MEDIUM_EXPERIMENT_ROOT}/seed-${seed}/recap"
    mkdir -p "${run_root}"

    bash "${SCRIPT_DIR}/advantage_labeling/recap/process/run_compute_returns.sh" \
        recap_compute_returns \
        +experiment@_global_=recap_libero10_task0_medium_returns
    value_checkpoint="${run_root}/recap-medium-value/checkpoints/global_step_2000/actor"
    if [[ ! -d "${value_checkpoint}" ]]; then
        bash "${SCRIPT_DIR}/advantage_labeling/recap/run_value_sft.sh" \
            recap_value_model_sft \
            +experiment@_global_=recap_libero10_task0_medium_value \
            "runner.logger.log_path=${run_root}"
    else
        echo "Reusing RECAP medium value checkpoint: ${value_checkpoint}"
    fi
    require_dir "${value_checkpoint}"
    advantage_sft="${RLINF_RECAP_MVP_DATA_ROOT}/libero10_task0_sft/meta/advantages_recap_task0_medium_seed${seed}_q30.parquet"
    advantage_train="${RLINF_RECAP_MEDIUM_DATA_ROOT}/libero10_task0_train/meta/advantages_recap_task0_medium_seed${seed}_q30.parquet"
    if [[ ! -f "${advantage_sft}" || ! -f "${advantage_train}" ]]; then
        bash "${SCRIPT_DIR}/advantage_labeling/recap/process/run_compute_advantages.sh" \
            recap_compute_advantages \
            --nproc "${nproc}" \
            +experiment@_global_=recap_libero10_task0_medium_advantages \
            "advantage.value_checkpoint=${value_checkpoint}"
    else
        echo "Reusing RECAP medium advantage sidecars for seed ${seed}."
    fi
    sync_medium_metadata
    policy_checkpoint="${run_root}/recap-medium-policy/checkpoints/global_step_1000/actor/model_state_dict/full_weights.pt"
    if [[ ! -f "${policy_checkpoint}" ]]; then
        bash "${SCRIPT_DIR}/policy_optimization/cfg_rl/run_cfg_rl.sh" \
            cfg_rl_openpi \
            +experiment@_global_=recap_libero10_task0_medium_cfg \
            "runner.logger.log_path=${run_root}"
    else
        echo "Reusing RECAP medium policy checkpoint: ${policy_checkpoint}"
    fi
    require_file "${policy_checkpoint}"
}

run_steam_medium() {
    local advantage_sft
    local advantage_train
    local seed="$1"
    local nproc
    local policy_checkpoint
    local run_root
    local value_checkpoint

    validate_seed "${seed}"
    stage_medium_data
    check_medium_assets
    export RLINF_EXPERIMENT_SEED="${seed}"
    nproc="$(detect_nproc)"
    run_root="${MEDIUM_EXPERIMENT_ROOT}/seed-${seed}/steam"
    mkdir -p "${run_root}"

    value_checkpoint="${run_root}/steam-medium-value/checkpoints/global_step_500/actor"
    if [[ ! -d "${value_checkpoint}" ]]; then
        bash "${SCRIPT_DIR}/advantage_labeling/steam/run_steam_sft.sh" \
            steam_value_model_sft \
            +experiment@_global_=steam_libero10_task0_medium_value \
            "runner.logger.log_path=${run_root}"
    else
        echo "Reusing STEAM medium value checkpoint: ${value_checkpoint}"
    fi
    require_dir "${value_checkpoint}"
    advantage_sft="${RLINF_RECAP_MVP_DATA_ROOT}/libero10_task0_sft/meta/advantages_steam_task0_medium_seed${seed}_k32_e3_q30.parquet"
    advantage_train="${RLINF_RECAP_MEDIUM_DATA_ROOT}/libero10_task0_train/meta/advantages_steam_task0_medium_seed${seed}_k32_e3_q30.parquet"
    if [[ ! -f "${advantage_sft}" || ! -f "${advantage_train}" ]]; then
        bash "${SCRIPT_DIR}/advantage_labeling/steam/process/run_compute_advantages_ensemble.sh" \
            steam_compute_advantages_ensemble \
            --nproc "${nproc}" \
            +experiment@_global_=steam_libero10_task0_medium_advantages \
            "advantage.value_checkpoint=${value_checkpoint}"
    else
        echo "Reusing STEAM medium advantage sidecars for seed ${seed}."
    fi
    sync_medium_metadata
    policy_checkpoint="${run_root}/steam-medium-policy/checkpoints/global_step_1000/actor/model_state_dict/full_weights.pt"
    if [[ ! -f "${policy_checkpoint}" ]]; then
        bash "${SCRIPT_DIR}/policy_optimization/cfg_rl/run_cfg_rl.sh" \
            cfg_rl_openpi \
            +experiment@_global_=steam_libero10_task0_medium_cfg \
            "runner.logger.log_path=${run_root}"
    else
        echo "Reusing STEAM medium policy checkpoint: ${policy_checkpoint}"
    fi
    require_file "${policy_checkpoint}"
}

run_steam_medium_value_smoke() {
    local run_root
    local seed="$1"
    local value_checkpoint

    validate_seed "${seed}"
    stage_medium_data
    check_medium_assets
    export RLINF_EXPERIMENT_SEED="${seed}"
    run_root="${MEDIUM_EXPERIMENT_ROOT}/smoke-seed-${seed}/steam"
    value_checkpoint="${run_root}/steam-medium-value-2gpu-smoke/checkpoints/global_step_2/actor"

    bash "${SCRIPT_DIR}/advantage_labeling/steam/run_steam_sft.sh" \
        steam_value_model_sft \
        +experiment@_global_=steam_libero10_task0_medium_value \
        "runner.logger.log_path=${run_root}" \
        "runner.logger.experiment_name=steam-medium-value-2gpu-smoke" \
        "runner.max_steps=2" \
        "runner.save_interval=2" \
        "actor.optim.lr_warmup_steps=1" \
        "actor.optim.total_training_steps=2"
    require_dir "${value_checkpoint}"
}

run_recap_full() {
    local seed="$1"
    local nproc
    local run_root
    local value_checkpoint

    validate_seed "${seed}"
    check_full_assets
    export RLINF_EXPERIMENT_SEED="${seed}"
    nproc="$(detect_nproc)"
    run_root="${FULL_EXPERIMENT_ROOT}/seed-${seed}/recap"
    mkdir -p "${run_root}"

    bash "${SCRIPT_DIR}/advantage_labeling/recap/process/run_compute_returns.sh" \
        recap_compute_returns \
        +experiment@_global_=recap_libero10_task0_returns
    bash "${SCRIPT_DIR}/advantage_labeling/recap/run_value_sft.sh" \
        recap_value_model_sft \
        +experiment@_global_=recap_libero10_task0_value \
        "runner.logger.log_path=${run_root}"
    value_checkpoint="${run_root}/value/checkpoints/global_step_8000/actor"
    require_dir "${value_checkpoint}"
    bash "${SCRIPT_DIR}/advantage_labeling/recap/process/run_compute_advantages.sh" \
        recap_compute_advantages --nproc "${nproc}" \
        +experiment@_global_=recap_libero10_task0_advantages \
        "advantage.value_checkpoint=${value_checkpoint}"
    bash "${SCRIPT_DIR}/policy_optimization/cfg_rl/run_cfg_rl.sh" \
        cfg_rl_openpi +experiment@_global_=recap_libero10_task0_cfg \
        "runner.logger.log_path=${run_root}"
}

run_steam_full() {
    local seed="$1"
    local nproc
    local run_root
    local value_checkpoint

    validate_seed "${seed}"
    check_full_assets
    export RLINF_EXPERIMENT_SEED="${seed}"
    nproc="$(detect_nproc)"
    run_root="${FULL_EXPERIMENT_ROOT}/seed-${seed}/steam"
    mkdir -p "${run_root}"

    bash "${SCRIPT_DIR}/advantage_labeling/steam/run_steam_sft.sh" \
        steam_value_model_sft \
        +experiment@_global_=steam_libero10_task0_value \
        "runner.logger.log_path=${run_root}"
    value_checkpoint="${run_root}/value/checkpoints/global_step_16000/actor"
    require_dir "${value_checkpoint}"
    bash "${SCRIPT_DIR}/advantage_labeling/steam/process/run_compute_advantages_ensemble.sh" \
        steam_compute_advantages_ensemble --nproc "${nproc}" \
        +experiment@_global_=steam_libero10_task0_advantages \
        "advantage.value_checkpoint=${value_checkpoint}"
    bash "${SCRIPT_DIR}/policy_optimization/cfg_rl/run_cfg_rl.sh" \
        cfg_rl_openpi +experiment@_global_=steam_libero10_task0_cfg \
        "runner.logger.log_path=${run_root}"
}

run_eval() {
    local method="$1"
    local seed="$2"
    local profile="${3:-mvp}"
    local checkpoint_step="${4:-}"
    local eval_seed="${5:-$seed}"
    local training_root
    local run_root
    local config_name
    local policy_dir
    local policy_checkpoint

    validate_seed "${seed}"
    validate_seed "${eval_seed}"
    export RLINF_EXPERIMENT_SEED="${eval_seed}"
    if [[ "${profile}" == "mvp" ]]; then
        check_mvp_assets
        run_root="${MVP_EXPERIMENT_ROOT}/seed-${seed}/${method}"
        if [[ "${method}" == "baseline" ]]; then
            config_name="libero_10_task0_mvp_openpi_pi05_eval"
        elif [[ "${method}" == "recap" || "${method}" == "steam" ]]; then
            config_name="libero_10_task0_mvp_cfg_pi05_eval"
            policy_checkpoint="${run_root}/policy/checkpoints/global_step_200/actor/model_state_dict/full_weights.pt"
            require_file "${policy_checkpoint}"
        else
            echo "Method must be baseline, recap, or steam; got: ${method}" >&2
            exit 2
        fi
    elif [[ "${profile}" == "medium" || "${profile}" == "medium-continuation" ]]; then
        check_medium_assets
        if [[ "${method}" == "baseline" ]]; then
            [[ -z "${checkpoint_step}" ]] || {
                echo "Medium baseline evaluation does not accept a checkpoint step." >&2
                exit 2
            }
            run_root="${MEDIUM_EXPERIMENT_ROOT}/seed-${seed}/baseline"
            config_name="libero_10_task0_mvp_openpi_pi05_eval"
        elif [[ "${method}" == "recap" || "${method}" == "steam" ]]; then
            if [[ "${profile}" == "medium" ]]; then
                if [[ "${checkpoint_step}" != "500" && "${checkpoint_step}" != "1000" ]]; then
                    echo "Medium checkpoint step must be 500 or 1000, got: ${checkpoint_step}" >&2
                    exit 2
                fi
                policy_dir="${method}-medium-policy"
            else
                if [[ "${method}" != "steam" ]]; then
                    echo "Medium continuation only supports STEAM, got: ${method}" >&2
                    exit 2
                fi
                if [[ "${checkpoint_step}" != "3000" && "${checkpoint_step}" != "5000" && "${checkpoint_step}" != "10000" ]]; then
                    echo "Medium continuation checkpoint must be 3000, 5000, or 10000; got: ${checkpoint_step}" >&2
                    exit 2
                fi
                policy_dir="steam-medium-policy-continued"
            fi
            training_root="${MEDIUM_EXPERIMENT_ROOT}/seed-${seed}/${method}"
            run_root="${MEDIUM_EXPERIMENT_ROOT}/seed-${seed}/${method}_step${checkpoint_step}"
            config_name="libero_10_task0_mvp_cfg_pi05_eval"
            policy_checkpoint="${training_root}/${policy_dir}/checkpoints/global_step_${checkpoint_step}/actor/model_state_dict/full_weights.pt"
            require_file "${policy_checkpoint}"
        else
            echo "Method must be baseline, recap, or steam; got: ${method}" >&2
            exit 2
        fi
    elif [[ "${profile}" == "full" ]]; then
        check_full_assets
        if [[ "${method}" != "recap" && "${method}" != "steam" ]]; then
            echo "Full evaluation supports recap or steam, got: ${method}" >&2
            exit 2
        fi
        run_root="${FULL_EXPERIMENT_ROOT}/seed-${seed}/${method}"
        config_name="libero_10_task0_cfg_pi05_eval"
        policy_checkpoint="${run_root}/policy/checkpoints/global_step_30000/actor/model_state_dict/full_weights.pt"
        require_file "${policy_checkpoint}"
    else
        echo "Unknown profile: ${profile}" >&2
        exit 2
    fi

    if [[ "${eval_seed}" != "${seed}" ]]; then
        run_root="${run_root}/eval-seed-${eval_seed}"
    fi
    mkdir -p "${run_root}/eval"
    local eval_args=(
        libero "${config_name}"
        "runner.logger.log_path=${run_root}/eval"
        "runner.logger.experiment_name=${method}-${profile}${checkpoint_step:+-step${checkpoint_step}}-train${seed}-eval${eval_seed}"
    )
    if [[ -n "${policy_checkpoint:-}" ]]; then
        eval_args+=("runner.ckpt_path=${policy_checkpoint}")
    fi
    bash "${REPO_PATH}/evaluations/run_eval.sh" "${eval_args[@]}" \
        2>&1 | tee "${run_root}/eval.log"
}

summarize_mvp() {
    python "${SCRIPT_DIR}/summarize_libero10_task0.py" \
        "${MVP_EXPERIMENT_ROOT}" \
        --seeds 0 \
        --baseline-seed 0 \
        --expected-trajectories 100 \
        --methods baseline recap steam
}

summarize_full() {
    python "${SCRIPT_DIR}/summarize_libero10_task0.py" \
        "${FULL_EXPERIMENT_ROOT}" \
        --seeds ${RLINF_FULL_SEEDS:-0 1 2} \
        --expected-trajectories 500 \
        --methods recap steam
}

summarize_medium() {
    python "${SCRIPT_DIR}/summarize_libero10_task0.py" \
        "${MEDIUM_EXPERIMENT_ROOT}" \
        --seeds 0 \
        --baseline-seed 0 \
        --expected-trajectories 100 \
        --methods baseline recap_step500 recap_step1000 steam_step500 steam_step1000
}

summarize_steam_medium_replication() {
    local eval_seed="$2"
    local train_seed="$1"

    python "${SCRIPT_DIR}/summarize_libero10_task0.py" \
        "${MEDIUM_EXPERIMENT_ROOT}" \
        --seeds "${train_seed}" \
        --baseline-seed "${eval_seed}" \
        --eval-seed "${eval_seed}" \
        --expected-trajectories 100 \
        --methods baseline steam_step500 steam_step1000 \
        --output "${MEDIUM_EXPERIMENT_ROOT}/summary.json"
}

summarize_steam_medium_continuation() {
    local eval_seed="$2"
    local train_seed="$1"

    python "${SCRIPT_DIR}/summarize_libero10_task0.py" \
        "${MEDIUM_EXPERIMENT_ROOT}" \
        --seeds "${train_seed}" \
        --baseline-seed "${eval_seed}" \
        --eval-seed "${eval_seed}" \
        --expected-trajectories 100 \
        --methods baseline steam_step3000 steam_step5000 steam_step10000 \
        --output "${MEDIUM_EXPERIMENT_ROOT}/summary.json"
}

run_mvp() {
    run_eval baseline 0 mvp
    run_recap_mvp 0
    run_remaining_mvp
}

run_remaining_mvp() {
    require_file "${MVP_EXPERIMENT_ROOT}/seed-0/recap/policy/checkpoints/global_step_200/actor/model_state_dict/full_weights.pt"
    run_eval recap 0 mvp
    run_steam_mvp 0
    run_eval steam 0 mvp
    summarize_mvp
}

run_medium() {
    run_eval baseline 0 medium
    run_recap_medium 0
    run_eval recap 0 medium 500
    run_eval recap 0 medium 1000
    run_steam_medium 0
    run_eval steam 0 medium 500
    run_eval steam 0 medium 1000
    summarize_medium
}

run_steam_medium_replication() {
    local eval_seed="$2"
    local train_seed="$1"

    validate_seed "${train_seed}"
    validate_seed "${eval_seed}"
    run_eval baseline "${eval_seed}" medium
    run_steam_medium "${train_seed}"
    run_eval steam "${train_seed}" medium 500 "${eval_seed}"
    run_eval steam "${train_seed}" medium 1000 "${eval_seed}"
    summarize_steam_medium_replication "${train_seed}" "${eval_seed}"
}

run_steam_medium_continuation() {
    local baseline_source
    local baseline_target
    local checkpoint
    local eval_log
    local eval_seed="$2"
    local output_root
    local resume_dir
    local target_step
    local train_seed="$1"

    validate_seed "${train_seed}"
    validate_seed "${eval_seed}"
    stage_medium_data
    check_medium_assets
    if [[ -z "${STEAM_MEDIUM_RESUME_DIR}" ]]; then
        echo "RLINF_STEAM_MEDIUM_RESUME_DIR must point to a global_step_1000 checkpoint." >&2
        exit 2
    fi
    if [[ -z "${STEAM_MEDIUM_BASELINE_ROOT}" ]]; then
        echo "RLINF_STEAM_MEDIUM_BASELINE_ROOT must contain seed-${eval_seed}/baseline/eval.log." >&2
        exit 2
    fi
    require_dir "${STEAM_MEDIUM_RESUME_DIR}/actor"
    require_file "${STEAM_MEDIUM_RESUME_DIR}/actor/dcp_checkpoint/.metadata"

    baseline_source="${STEAM_MEDIUM_BASELINE_ROOT}/seed-${eval_seed}/baseline/eval.log"
    baseline_target="${MEDIUM_EXPERIMENT_ROOT}/seed-${eval_seed}/baseline/eval.log"
    require_file "${baseline_source}"
    mkdir -p "$(dirname "${baseline_target}")"
    if [[ ! -f "${baseline_target}" ]]; then
        cp -a "${baseline_source}" "${baseline_target}"
    fi

    export RLINF_EXPERIMENT_SEED="${train_seed}"
    output_root="${MEDIUM_EXPERIMENT_ROOT}/seed-${train_seed}/steam"
    mkdir -p "${output_root}"
    resume_dir="${STEAM_MEDIUM_RESUME_DIR}"

    for target_step in 3000 5000 10000; do
        checkpoint="${output_root}/steam-medium-policy-continued/checkpoints/global_step_${target_step}"
        if [[ ! -f "${checkpoint}/actor/model_state_dict/full_weights.pt" ]]; then
            bash "${SCRIPT_DIR}/policy_optimization/cfg_rl/run_cfg_rl.sh" \
                cfg_rl_openpi \
                +experiment@_global_=steam_libero10_task0_medium_cfg \
                "runner.logger.log_path=${output_root}" \
                "runner.logger.experiment_name=steam-medium-policy-continued" \
                "+runner.resume_dir=${resume_dir}" \
                "runner.max_steps=${target_step}" \
                "runner.save_interval=${target_step}" \
                "actor.optim.total_training_steps=10000"
        else
            echo "Reusing STEAM continuation checkpoint: ${checkpoint}"
        fi
        require_file "${checkpoint}/actor/model_state_dict/full_weights.pt"
        resume_dir="${checkpoint}"

        eval_log="${MEDIUM_EXPERIMENT_ROOT}/seed-${train_seed}/steam_step${target_step}/eval-seed-${eval_seed}/eval.log"
        if [[ -f "${eval_log}" ]] && grep -q "'eval/num_trajectories': 100" "${eval_log}"; then
            echo "Reusing completed STEAM step ${target_step} evaluation: ${eval_log}"
        else
            run_eval steam "${train_seed}" medium-continuation "${target_step}" "${eval_seed}"
        fi
    done
    summarize_steam_medium_continuation "${train_seed}" "${eval_seed}"
}

run_full() {
    local seed
    for seed in ${RLINF_FULL_SEEDS:-0 1 2}; do
        run_recap_full "${seed}"
        run_eval recap "${seed}" full
        run_steam_full "${seed}"
        run_eval steam "${seed}" full
    done
    summarize_full
}

usage() {
    cat <<'EOF'
Usage:
  run_libero10_task0_comparison.sh prepare
  run_libero10_task0_comparison.sh baseline
  run_libero10_task0_comparison.sh recap <seed>
  run_libero10_task0_comparison.sh steam <seed>
  run_libero10_task0_comparison.sh eval <baseline|recap|steam> <seed>
  run_libero10_task0_comparison.sh mvp
  run_libero10_task0_comparison.sh continue-mvp
  run_libero10_task0_comparison.sh summarize

Medium experiment commands:
  run_libero10_task0_comparison.sh prepare-medium
  run_libero10_task0_comparison.sh recap-medium <seed>
  run_libero10_task0_comparison.sh steam-medium <seed>
  run_libero10_task0_comparison.sh steam-medium-value-smoke <seed>
  run_libero10_task0_comparison.sh steam-medium-replication <train-seed> <eval-seed>
  run_libero10_task0_comparison.sh steam-medium-continuation <train-seed> <eval-seed>
  run_libero10_task0_comparison.sh eval-medium <baseline|recap|steam> <train-seed> [500|1000] [eval-seed]
  run_libero10_task0_comparison.sh eval-medium-continuation steam <train-seed> <3000|5000|10000> <eval-seed>
  run_libero10_task0_comparison.sh medium
  run_libero10_task0_comparison.sh summarize-medium

Explicit full experiment commands:
  run_libero10_task0_comparison.sh prepare-full
  run_libero10_task0_comparison.sh full
  run_libero10_task0_comparison.sh summarize-full

Environment overrides:
  RLINF_EXPERIMENT_ROOT, RLINF_MEDIUM_EXPERIMENT_ROOT, RLINF_FULL_EXPERIMENT_ROOT,
  RLINF_RECAP_MVP_DATA_ROOT, RLINF_RECAP_MVP_CACHE_ROOT,
  RLINF_RECAP_MEDIUM_DATA_ROOT, RLINF_RECAP_MEDIUM_CACHE_ROOT,
  RLINF_RECAP_DATA_ROOT, RLINF_PI05_MODEL_PATH,
  RLINF_RECAP_SIGLIP_PATH, RLINF_STEAM_SIGLIP_PATH, RLINF_GEMMA_PATH,
  RLINF_NPROC, RLINF_HF_MAX_WORKERS, RLINF_HF_STAGING_ROOT,
  RLINF_FULL_SEEDS, RLINF_VENV_PATH, RLINF_PYTHON_SHARED_LIB_DIR,
  RLINF_OPEN_FILES_LIMIT, RLINF_STEAM_MEDIUM_RESUME_DIR,
  RLINF_STEAM_MEDIUM_BASELINE_ROOT
EOF
}

command_name="${1:-}"
case "${command_name}" in
    prepare)
        prepare_mvp_assets
        ;;
    prepare-full)
        prepare_full_assets
        ;;
    prepare-medium)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        prepare_medium_assets
        ;;
    baseline)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        run_eval baseline 0 mvp
        ;;
    recap)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        run_recap_mvp "$2"
        ;;
    steam)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        run_steam_mvp "$2"
        ;;
    eval)
        [[ $# -eq 3 ]] || { usage; exit 2; }
        run_eval "$2" "$3" mvp
        ;;
    mvp|all)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        run_mvp
        ;;
    continue-mvp)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        run_remaining_mvp
        ;;
    summarize)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        summarize_mvp
        ;;
    recap-medium)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        run_recap_medium "$2"
        ;;
    steam-medium)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        run_steam_medium "$2"
        ;;
    steam-medium-value-smoke)
        [[ $# -eq 2 ]] || { usage; exit 2; }
        run_steam_medium_value_smoke "$2"
        ;;
    steam-medium-replication)
        [[ $# -eq 3 ]] || { usage; exit 2; }
        run_steam_medium_replication "$2" "$3"
        ;;
    steam-medium-continuation)
        [[ $# -eq 3 ]] || { usage; exit 2; }
        run_steam_medium_continuation "$2" "$3"
        ;;
    eval-medium)
        if [[ "${2:-}" == "baseline" ]]; then
            [[ $# -eq 3 ]] || { usage; exit 2; }
            run_eval "$2" "$3" medium
        else
            [[ $# -eq 4 || $# -eq 5 ]] || { usage; exit 2; }
            run_eval "$2" "$3" medium "$4" "${5:-$3}"
        fi
        ;;
    eval-medium-continuation)
        [[ $# -eq 5 ]] || { usage; exit 2; }
        run_eval "$2" "$3" medium-continuation "$4" "$5"
        ;;
    medium)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        run_medium
        ;;
    summarize-medium)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        summarize_medium
        ;;
    full)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        run_full
        ;;
    summarize-full)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        summarize_full
        ;;
    *)
        usage
        exit 2
        ;;
esac
