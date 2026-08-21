# Model profiles

Each `*.conf` file is a reviewed, declarative deployment profile. The installer
loads exactly one profile and the generic launcher applies its runtime-specific
arguments. This keeps model churn out of `install.sh` and `run-model.sh`.

## Add a profile

1. Copy the closest existing profile to a lowercase, filesystem-safe name.
2. Pin the Hugging Face repository to a full 40-character commit SHA.
3. Set conservative GPU, host-memory, disk, and context defaults.
4. List only runtimes verified for that exact checkpoint format.
5. Put model-specific server flags in the matching runtime argument array.
6. Add a catalog assertion and a command-line profile test.
7. Run `./scripts/validate.sh` and test installation on disposable matching
   hardware before describing the profile as production-verified.

## Profile fields

| Field | Meaning |
| --- | --- |
| `PROFILE_MODEL_ID` | Hugging Face `organization/model` identifier |
| `PROFILE_MODEL_REVISION` | Immutable 40-character model commit |
| `PROFILE_SERVED_MODEL_NAME` | Model ID returned by the OpenAI-compatible API |
| `PROFILE_MODEL_FAMILY` | Stable behavior family used for operational messages |
| `PROFILE_DEFAULT_RUNTIME` | `sglang`, `vllm`, or `llamacpp` |
| `PROFILE_ALLOWED_RUNTIMES` | Space-separated runtimes verified for the profile |
| `PROFILE_GPU_COUNT` | Default exact GPU count |
| `PROFILE_GPU_NAME` | Optional `nvidia-smi` name substring; empty means capability-based |
| `PROFILE_MIN_GPU_MEMORY_MIB` | Minimum memory for every selected GPU |
| `PROFILE_MIN_COMPUTE_CAPABILITY` | Optional NVIDIA compute-capability floor |
| `PROFILE_MIN_SYSTEM_MEMORY_MIB` | Host-memory floor; zero disables this check |
| `PROFILE_MIN_DATA_GIB` | Free data space plus the selected revision's existing cache |
| `PROFILE_CONTEXT_LENGTH` | Safe initial context window |
| `PROFILE_SGLANG_MEM_FRACTION` | SGLang GPU-memory reservation fraction |
| `PROFILE_GPU_MEMORY_UTILIZATION` | vLLM GPU-memory utilization fraction |
| `PROFILE_TRUST_REMOTE_CODE` | Whether the built-in checkpoint needs repository code |
| `PROFILE_REQUIRES_CUSTOM_MODEL` | Require the operator to provide model ID and revision |
| `PROFILE_PRESERVE_FAMILY_ON_MODEL_OVERRIDE` | Retain parsers when using a compatible mirror/quant |
| `PROFILE_GGUF_FILENAME` | Exact root-level GGUF file downloaded for llama.cpp; retained for simple single-file models |
| `PROFILE_GGUF_FILES` | Ordered GGUF file paths for sharded models; the first shard is passed to llama.cpp |
| `PROFILE_MTP_MODE` | Optional supported speculative-decoding mode |
| `PROFILE_SGLANG_ARGS` / `PROFILE_VLLM_ARGS` / `PROFILE_LLAMACPP_ARGS` | Model-specific server arguments |
| `PROFILE_SGLANG_ENV` / `PROFILE_VLLM_ENV` / `PROFILE_LLAMACPP_ENV` | Model-specific `NAME=value` container settings |

Profile files are sourced by a root-run installer and are therefore trusted
code even though they are intentionally limited to assignments. Review them as
carefully as shell scripts. Do not put credentials, private URLs, mutable model
revisions, or customer information in a profile.

## Compatibility policy

- Built-in model revisions are immutable. Updating one is a reviewed change.
- Runtime image tags follow the newest official release and are resolved to a
  digest at install time.
- Profile names identify the model and format, not the hardware used to run
  them. Hardware requirements belong in the profile fields and documentation.
- Community quantizations need explicit quality, reasoning, streaming, and
  tool-call validation before becoming a built-in profile.
- GGUF profiles pin one exact file or an ordered shard list so installation
  downloads only the selected quantization rather than the whole repository.
