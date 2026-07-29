# OpenAI-compatible LLM deployment

Portable, inspectable installer for serving models through SGLang or vLLM.
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

| Component | `h100` (default) | `a100` |
| --- | --- | --- |
| Operating system | Ubuntu 24.04 LTS, x86_64 | Ubuntu 24.04 LTS, x86_64 |
| GPUs | Exactly 8× H100 with at least 79,000 MiB each | Exactly 8× A100 with at least 79,000 MiB each |
| Free model/cache storage | At least 600 GiB | At least 600 GiB |
| Model | `PhalaCloud/GLM-5.2-W4AFP8` at a pinned revision | `lowbitcoffee/GLM-5.2-W4A16` at a pinned revision |
| Inference runtime | Latest official SGLang image | Latest official vLLM image |
| Default context length | 131,072 tokens | 32,768 tokens |
| Compute path | W4AFP8 weights/activations; BF16 KV cache | INT4 weights; BF16 activations and KV cache |
| API | Authenticated OpenAI-compatible `/v1` endpoint through nginx | Same |

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

These are defaults, not hardcoded limits. A different model, GPU count, GPU
name, per-GPU memory floor, storage allowance, context length, and runtime can
be selected through installer options. The operator is responsible for making
sure a custom combination fits in GPU memory and is supported by the selected
runtime.

## Before installation

The host must already have:

- Ubuntu 24.04 LTS on x86_64.
- NVIDIA driver 580.82.07 or newer for the H100/SGLang profile, or 580.95.05 or
  newer for the A100/vLLM profile. `nvidia-smi` must show exactly eight 80 GB
  GPUs from the selected family.
- An existing mounted data directory with at least 600 GiB free. The installer
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

## Other models and vLLM

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
- Model: `glm-5.2-w4afp8` for the H100 profile or `glm-5.2-w4a16` for A100
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
  credential even from localhost.
- SGLang informational argument logging is disabled because current releases
  include authentication fields in their startup argument dump. Warnings and
  errors remain available through the service journal.
- TLS is not configured. Use localhost, a trusted private network, or place a
  TLS-terminating proxy in front of the endpoint.
- Binding `0.0.0.0` does not create a firewall rule. Restrict port 8000 to the
  exact private network or clients that need it.
- The built-in pinned model revisions are loaded with `--trust-remote-code`, so
  review the selected repository before deployment and update pins deliberately.
  Custom models require an explicit `--trust-remote-code` choice.
- Do not commit API keys, cloud credentials, SSH keys, or Hugging Face tokens.
- Keep the model data directory root-owned and do not make its top-level cache
  directories writable by unprivileged users.

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## Reproducibility and updates

The built-in model commits and minimum NVIDIA Container Toolkit package version
are set in [`lib/common.sh`](lib/common.sh). Runtime tags intentionally track
`lmsysorg/sglang:latest` and `vllm/vllm-openai:latest`. During installation,
the selected tag is pulled and resolved to the exact immutable digest stored in
`/etc/opsrabbit-llm/install.conf`. The running service stays on that digest
until the installer is rerun, when it deliberately refreshes to the newest
runtime.

Pins are intentional. Test model or runtime upgrades on a disposable host and
submit them through a pull request with updated evidence and validation.

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
[Apache License 2.0](LICENSE). The GLM-5.2 model and third-party packages have
their own licenses; review and accept those separately before deployment.
