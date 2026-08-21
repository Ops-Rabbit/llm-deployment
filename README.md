# OpenAI-compatible LLM deployment

Portable, inspectable installer for serving models through SGLang, vLLM, or
llama.cpp.
The default profile serves the community
[`PhalaCloud/GLM-5.2-W4AFP8`](https://huggingface.co/PhalaCloud/GLM-5.2-W4AFP8)
checkpoint on a single 8× NVIDIA H100 80 GB host. It exposes an authenticated
OpenAI-compatible API suitable for OpsRabbit and other compatible clients.
An optional A100 profile serves the community
[`lowbitcoffee/GLM-5.2-W4A16`](https://huggingface.co/lowbitcoffee/GLM-5.2-W4A16)
checkpoint through vLLM on 8× NVIDIA A100 80 GB.

This repository configures the machine only. It does **not** provision cloud
resources, create firewall rules, format or mount disks, or install NVIDIA
drivers.

## Supported profiles

The overall default remains GLM-5.2. Qwen3.8 and DeepSeek-V4-Flash profiles are
hardware-capability profiles: they check GPU count, memory, compute capability
where required, system memory, disk, and runtime compatibility without
requiring a particular GPU product name.

| Profile | Checkpoint and format | Default runtime | Default hardware floor | Data space | Context | Position |
| --- | --- | --- | --- | ---: | ---: | --- |
| `h100` (default) | `PhalaCloud/GLM-5.2-W4AFP8` | SGLang | 8× H100 79,000 MiB | 600 GiB | 131,072 | Existing GLM H100 baseline |
| `a100` | `lowbitcoffee/GLM-5.2-W4A16` | vLLM | 8× A100 79,000 MiB | 600 GiB | 32,768 | Existing GLM A100 baseline |
| `qwen38-bf16` | Official Qwen3.8-27B BF16, 55.6 GB | SGLang; vLLM optional | 1× 79,000 MiB, compute 8.0+ | 100 GiB | 32,768 | Highest-fidelity Qwen baseline |
| `qwen38-fp8` | Official Qwen3.8-27B FP8, 30.9 GB | SGLang; vLLM optional | 1× 45,000 MiB, compute 8.9+ | 75 GiB | 32,768 | Recommended Qwen cloud profile |
| `qwen38-unsloth-nvfp4` | Unsloth NVFP4, about 23.4 GB with MTP | SGLang; vLLM optional | 1× 30,000 MiB, Blackwell compute 10.0+ | 60 GiB | 32,768 | Fast Blackwell profile |
| `qwen38-unsloth-gguf-q2` | Unsloth Dynamic GGUF Q2 | llama.cpp | 1× 15,000 MiB plus host RAM | 40 GiB | 32,768 | Lowest-memory, reduced-quality testing |
| `qwen38-unsloth-gguf-q3` | Unsloth Dynamic GGUF Q3 | llama.cpp | 1× 15,000 MiB plus host RAM | 40 GiB | 32,768 | Low-memory testing |
| `qwen38-unsloth-gguf-q4` | Unsloth `UD-Q4_K_XL`, 17–19 GB | llama.cpp | 1× 23,000 MiB | 50 GiB | 32,768 | Recommended 24 GB GPU profile |
| `qwen38-unsloth-gguf-q6` | Unsloth Dynamic GGUF Q6, about 24 GB | llama.cpp | 1× 30,000 MiB | 60 GiB | 32,768 | Higher-quality GGUF |
| `qwen38-unsloth-gguf-q8` | Unsloth Dynamic GGUF Q8, about 31 GB | llama.cpp | 1× 45,000 MiB | 75 GiB | 32,768 | Highest-quality practical GGUF |
| `qwen38-int4` | Operator-supplied pinned Qwen3.8 AWQ/GPTQ W4A16 | vLLM; SGLang optional | 1× 23,000 MiB, compute 7.5+ | 60 GiB | 32,768 | Format support pending a trusted built-in checkpoint |
| `deepseek-v4-flash-0731` | Official 0731 mixed FP4/FP8 checkpoint with DSpark weights, about 167 GB | SGLang; vLLM optional | 4× 130,000 MiB, compute 9.0+ | 250 GiB | 32,768 | Preferred DeepSeek profile |
| `deepseek-v4-flash-0423` | Official preview mixed FP4/FP8 checkpoint, about 160 GB | SGLang; vLLM optional | 8× 79,000 MiB, compute 9.0+ | 240 GiB | 32,768 | Verified H100-class compatibility path |
| `deepseek-v4-flash-0731-unsloth-gguf-q2` | Unsloth sharded GGUF Q2, about 96.8 GB | llama.cpp | 1× 15,000 MiB plus 128 GiB host RAM | 140 GiB | 32,768 | Lowest-memory DeepSeek test profile |
| `deepseek-v4-flash-0731-unsloth-gguf-q3` | Unsloth sharded GGUF Q3, about 128 GB | llama.cpp | 1× 15,000 MiB plus 160 GiB host RAM | 175 GiB | 32,768 | Reduced-memory DeepSeek profile |
| `deepseek-v4-flash-0731-unsloth-gguf-q4` | Unsloth sharded GGUF Q4, about 155 GB | llama.cpp | 1× 15,000 MiB plus 192 GiB host RAM | 210 GiB | 32,768 | Balanced compatibility profile |
| `deepseek-v4-flash-0731-unsloth-gguf-q8` | Unsloth sharded GGUF Q8, about 162 GB | llama.cpp | 1× 15,000 MiB plus 192 GiB host RAM | 220 GiB | 32,768 | Highest-fidelity GGUF profile |

List the profiles present in the checked-out release:

```bash
./install.sh --list-profiles
```

Model revisions are pinned, while the official SGLang, vLLM, and llama.cpp
runtime tags deliberately follow their newest published images. Each install
resolves the selected runtime tag to an immutable digest before starting the
service.

The W4AFP8 checkpoint is a community quantization of GLM-5.2. It is not the
full-precision or official FP8 checkpoint. The model card reports roughly 440
GB of files and about 410 GB of GPU memory for weights. The first installation
can therefore take a long time while the exact revision is downloaded, and the
first service start must then load those weights onto the GPUs.

The A100 checkpoint is also a community quantization. Its model card reports a
388 GB compressed-tensors checkpoint designed for vLLM, with INT4 weights and
BF16 activations, and says it fits on one 8×A100 80 GB node. The A100 profile
uses a smaller initial context window to preserve KV-cache headroom, disables
Hopper-only vLLM kernel paths, and enables GLM reasoning and tool-call parsing.
The repository checks validate the generated configuration; full throughput
and quality validation still requires a real A100 host.

These are conservative defaults, not a GPU product allowlist. GPU count,
optional name matching, per-GPU memory floor, host-memory floor, storage,
context length, and compatible runtime can be overridden. Multiple GPUs should
be mutually compatible and have similar memory. The operator remains
responsible for validating performance and quality after changing profile
floors.

The Qwen profiles configure Qwen reasoning and tool-call parsing for SGLang and
vLLM. The GGUF profiles run llama.cpp with its embedded Jinja template,
reasoning extraction, GPU offload, a protected Unix socket, and the same
authenticated OpenAI-compatible API. GGUF vision projection is not installed
in this initial text-and-tools deployment path.

Checkpoint details and published sizes are available from the
[official BF16 model](https://huggingface.co/Qwen/Qwen3.8-27B),
[official FP8 model](https://huggingface.co/Qwen/Qwen3.8-27B-FP8), and
[Unsloth Qwen3.8 guide](https://unsloth.ai/models/qwen3.8-27b).

The DeepSeek native profiles configure the dedicated DeepSeek-V4 reasoning,
tool-call, and tokenizer modes required by the model's non-Jinja message
encoding. The 0731 checkpoint is preferred for its stronger agent behavior;
the unversioned official checkpoint is commonly called 0423 and remains the
conservative 8×H100 path. Both expose the same authenticated OpenAI-compatible
API. The GGUF profiles use exact Unsloth shard lists and llama.cpp, allowing
GPU plus host-memory offload on systems that cannot run the native checkpoint.
They are compatibility paths rather than promises of production throughput on
a single small GPU.

The 0731 repository includes DSpark speculative weights, but the built-in
profile leaves speculative decoding disabled for its first correctness and
quality baseline. It can be exposed as a separate reviewed profile after
matching-hardware validation instead of being silently enabled here.

Checkpoint details and published deployment guidance are available from the
[official 0731 model](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731),
[official preview model](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash),
[SGLang DeepSeek-V4 cookbook](https://docs.sglang.io/cookbook/autoregressive/DeepSeek/DeepSeek-V4),
and [Unsloth 0731 GGUF repository](https://huggingface.co/unsloth/DeepSeek-V4-Flash-0731-GGUF).

## Before installation

The host must already have:

- Ubuntu 24.04 LTS on x86_64.
- A working NVIDIA driver. Current SGLang images require 580.82.07 or newer,
  current vLLM images require 580.95.05 or newer, and the current CUDA 12
  llama.cpp image requires 570.26.00 or newer. The installer also executes a
  real CUDA visibility check inside the freshly pulled image.
- An existing mounted data directory meeting the selected profile. The installer
  creates cache subdirectories but never formats, partitions, or mounts a disk.
  The directory and every ancestor must be canonical paths owned by root and
  not writable by group or other users; this prevents a local user from
  redirecting privileged writes through links or replaceable parent paths.
- At least 80 GiB free in Docker's data root, normally `/var/lib/docker`, for
  runtime image layers. Old runtime images are not removed automatically.
- Outbound HTTPS access to Ubuntu, NVIDIA, Docker Hub, and Hugging Face.
- A public Hugging Face model repository. Authentication for gated or private
  repositories is not implemented yet.
- A firewall appropriate for the chosen listen address.

Clone and inspect a tagged release before running it. Start with the read-only
preflight:

```bash
sudo chown root:root /mnt/llm-data
sudo chmod 0755 /mnt/llm-data
./install.sh --data-dir /mnt/llm-data --check-only
```

For an A100 host, select its profile during preflight:

```bash
./install.sh --profile a100 --data-dir /mnt/llm-data --check-only
```

For a 48 GB Ada/Hopper GPU, preflight the recommended official Qwen FP8
profile:

```bash
./install.sh --profile qwen38-fp8 --data-dir /mnt/llm-data --check-only
```

For a 24 GB GPU, use the recommended Unsloth Q4 GGUF profile:

```bash
./install.sh --profile qwen38-unsloth-gguf-q4 \
  --data-dir /mnt/llm-data --check-only
```

## Install

The safest default listens only on the machine itself:

```bash
sudo ./install.sh --data-dir /mnt/llm-data
```

On an 8×A100 80 GB host, select the A100 profile. It automatically chooses the
pinned W4A16 checkpoint, vLLM, A100 hardware checks, and a 32,768-token context:

```bash
sudo ./install.sh --profile a100 --data-dir /mnt/llm-data
```

Install Qwen3.8 FP8 or Unsloth Q4 GGUF in the same way:

```bash
sudo ./install.sh --profile qwen38-fp8 --data-dir /mnt/llm-data
sudo ./install.sh --profile qwen38-unsloth-gguf-q4 --data-dir /mnt/llm-data
```

Install the preferred native DeepSeek release or its broadly compatible Q4
GGUF profile:

```bash
sudo ./install.sh --profile deepseek-v4-flash-0731 --data-dir /mnt/llm-data
sudo ./install.sh --profile deepseek-v4-flash-0731-unsloth-gguf-q4 \
  --data-dir /mnt/llm-data
```

The native 0423 profile defaults to eight 80 GB Hopper GPUs. GGUF profiles
default to one GPU with host-memory offload; use `--gpu-count` and the matching
memory overrides to make all GPUs on a larger host available to llama.cpp.

To make the API available on a trusted local network, bind all IPv4 interfaces
and restrict the API port in the host or network firewall:

```bash
sudo ./install.sh \
  --data-dir /mnt/llm-data \
  --listen-address 0.0.0.0 \
  --port 8000
```

The installer is idempotent: re-running the same model ID and exact commit
refreshes software and configuration while preserving and crediting only that
revision's dedicated cache and the existing API key. Interrupted downloads can
resume from that cache. Switching models or revisions does not credit old
snapshots toward the new storage requirement. To supply your own
key, put one URL-safe value of 32–256 characters in a protected file:

```bash
sudo ./install.sh \
  --data-dir /mnt/llm-data \
  --api-key-file /secure/path/api-key
```

Multi-token prediction (MTP) speculative decoding is deliberately disabled for
the initial baseline. It can be enabled explicitly with `--enable-mtp` for the
default H100/SGLang profile after the baseline deployment has been measured and
verified. It is not enabled for the A100 profile.

The installer intentionally does not force FP8 KV cache on H100. An
[upstream report](https://huggingface.co/PhalaCloud/GLM-5.2-W4AFP8/discussions/3)
for this exact GPU family and SGLang version shows corrupted output when FP8 KV
is forced without scaling factors, while SGLang's automatic BF16 path produces
correct output.

## Other models and runtimes

Select a custom model with a pinned Hugging Face revision. The served name is
derived from the model name unless it is set explicitly:

```bash
sudo ./install.sh \
  --data-dir /mnt/llm-data \
  --model <organization/model> \
  --model-revision <full-commit-sha> \
  --served-model-name <api-model-name>
```

SGLang remains the default runtime. To use the latest official vLLM image:

```bash
sudo ./install.sh \
  --data-dir /mnt/llm-data \
  --runtime vllm \
  --model <vllm-compatible-model> \
  --model-revision <full-commit-sha> \
  --served-model-name <api-model-name>
```

The Qwen BF16, FP8, and NVFP4 profiles accept either SGLang or vLLM. For
example:

```bash
sudo ./install.sh --profile qwen38-fp8 --runtime vllm \
  --data-dir /mnt/llm-data
```

Unsloth's BF16 and FP8 mirrors can reuse the corresponding Qwen behavior
profile with an explicit pinned revision. They do not need duplicate installer
logic. The INT4 profile deliberately requires `--model` and
`--model-revision`; newly uploaded community quantizations are not silently
promoted to trusted defaults.

Custom model revisions must be full 40-character lowercase commit hashes so a
rerun cannot silently download different code or weights. Mutable values such
as `main` and release tags are rejected. Custom repository code is disabled
unless `--trust-remote-code` is explicitly provided.

Additional runtime-specific options can be supplied in a root-controlled text
file with one complete argument per line, for example:

```text
# /secure/path/runtime.args
--dtype
bfloat16
```

Pass it with `--runtime-args-file /secure/path/runtime.args`. The installer
rejects arguments that would override its model identity, binding,
authentication, parallelism, or context controls.

The default `PhalaCloud/GLM-5.2-W4AFP8` checkpoint cannot currently be selected
with vLLM. Its model card says the W4AFP8 layout is SGLang-specific and untried
on vLLM. The official GLM-5.2 FP8 checkpoint supports vLLM 0.23.0+, but it does
not fit on an 8×H100 80 GB node. The installer therefore fails early for the
unsafe default-model/vLLM combination instead of launching an unverified
deployment.

The built-in A100 checkpoint is vLLM-only. Its profile adds BF16 compute,
`glm45` reasoning parsing, `glm47` tool-call parsing, and automatic tool choice
for OpenAI-compatible clients. An explicit `--runtime sglang` with that
checkpoint is rejected. A custom model can still combine `--profile a100` with
its own pinned revision and runtime when the operator has verified that
combination.

At the time of this release, the latest SGLang image uses CUDA 13.0.1 and needs
NVIDIA driver 580.82.07 or newer, while the latest vLLM image uses CUDA 13.0.2
and needs driver 580.95.05 or newer. Because `latest` can move, the installer
also verifies real GPU access inside the image and fails before creating the
service if a newer image is incompatible with the host driver.

If Docker Engine is already installed, the installer preserves it instead of
installing Ubuntu's `docker.io` package over it. Existing Docker must use the
normal `docker.service` systemd unit. Enabling the NVIDIA runtime may require
one Docker restart; the installer refuses that restart while unrelated
containers are running.

## Connect an OpenAI-compatible client

Read the generated API key on the server:

```bash
sudo cat /etc/opsrabbit-llm/api-key
```

List models from the server itself:

```bash
sudo curl --fail \
  --config /etc/opsrabbit-llm/curl.conf \
  http://127.0.0.1:8000/v1/models
```

Use these client values:

- Base URL: `http://<private-host>:8000/v1`
- Model: the served name shown at the end of installation. It is
  `glm-5.2-w4afp8` for H100, `glm-5.2-w4a16` for A100, and begins with
  `qwen3.8-27b` or `deepseek-v4-flash` for the corresponding built-in profiles.
- API key: the value in `/etc/opsrabbit-llm/api-key`

An illustrative OpsRabbit provider record is available at
[`examples/opsrabbit-provider.json`](examples/opsrabbit-provider.json). Match
the exact field names to the OpsRabbit version you are running.

## Operate and verify

```bash
sudo opsrabbit-llm-healthcheck
sudo opsrabbit-llm-healthcheck --chat
sudo systemctl status opsrabbit-llm.service
sudo docker logs -f opsrabbit-llm-server
sudo journalctl -u opsrabbit-llm.service -f
```

The normal health check verifies `/health` and `/v1/models`. The optional chat
check sends a small completion request.

To remove the service and proxy while preserving downloaded model data:

```bash
sudo ./uninstall.sh
```

## Security boundaries

- The default endpoint is `127.0.0.1:8000`.
- Bearer authentication is enforced by both nginx and the model server. The
  SGLang backend is published only on host loopback. vLLM uses a protected Unix
  socket because its non-OpenAI maintenance routes are not covered by its API
  key. nginx owns the configurable client-facing address and exposes only the
  permitted routes. Generated credential files and nginx configuration are
  readable only by root.
- nginx exposes only `/health` and `/v1/*`. SGLang administrative endpoints
  remain blocked at the proxy and require a separate root-only backend
  credential even from localhost. vLLM and llama.cpp use protected Unix
  sockets behind nginx.
- SGLang informational argument logging is disabled because current releases
  include authentication fields in their startup argument dump. Warnings and
  errors remain available through the service journal.
- TLS is not configured. Use localhost, a trusted private network, or place a
  TLS-terminating proxy in front of the endpoint.
- Binding `0.0.0.0` does not create a firewall rule. Restrict port 8000 to the
  exact private network or clients that need it.
- Profiles that enable `--trust-remote-code` are explicitly marked in their
  catalog files. Review those pinned repositories before deployment and update
  pins deliberately. Custom models require an explicit
  `--trust-remote-code` choice.
- Do not commit API keys, cloud credentials, SSH keys, or Hugging Face tokens.
- Keep the model data directory root-owned and do not make its top-level cache
  directories writable by unprivileged users.

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## Reproducibility and updates

The built-in model commits and hardware requirements are stored in small files
under [`profiles/`](profiles/README.md); shared runtime settings and the minimum
NVIDIA Container Toolkit package version are in [`lib/common.sh`](lib/common.sh).
Runtime tags intentionally track `lmsysorg/sglang:latest`,
`vllm/vllm-openai:latest`, and the official llama.cpp `server-cuda` tag. During
installation,
the selected tag is pulled and resolved to the exact immutable digest stored in
`/etc/opsrabbit-llm/install.conf`. The running service stays on that digest
until the installer is rerun, when it deliberately refreshes to the newest
runtime.

Pins are intentional. Test model or runtime upgrades on a disposable host and
submit them through a pull request with updated evidence and validation.

## Add a future model

Adding a model does not require changing the installer or launcher when its
runtime is already supported. Copy the closest file under `profiles/`, set the
pinned model revision and capability requirements, add runtime arguments to
the profile arrays, and run validation. The complete profile contract and
review checklist are in [`profiles/README.md`](profiles/README.md).

## Local repository validation

No GPU or model download is required for repository checks:

```bash
./scripts/validate.sh
```

This runs ShellCheck, Bash syntax checks, unit tests for preflight validation,
and command-line help smoke tests. GitHub Actions runs the same validation for
future pull requests.

## License

The scripts and documentation in this repository are licensed under the
[Apache License 2.0](LICENSE). GLM, Qwen, DeepSeek, Unsloth checkpoints, and
third-party packages have their own licenses and release-specific terms;
review and accept those separately before deployment.
