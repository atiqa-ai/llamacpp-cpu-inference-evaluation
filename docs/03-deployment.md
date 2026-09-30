# Deployment

This document covers how a model is served from this project: launching
`llama-server`, the memory profiles that were verified to fit the target
hardware, and the HTTP surface used to query it.

> Status labels used throughout this document:
>
> - **Tested** — executed on the target VM (CPU-only, ~7.7 GiB RAM, 4 cores).
> - **Documented / Not tested** — follows official llama.cpp behaviour, but not
>   executed here because the hardware was not available.

Every command in this document targets the CPU-only configuration established
in [01-environment.md](01-environment.md). No GPU is present on the target
machine, so GPU sections are documented only.

---

## 1. Deployment model

There is one deployment shape for this project: a **local `llama-server`
process** on the same machine that holds the GGUF file.

```
            ┌──────────────────────────────┐
  client ──▶│  llama-server  (127.0.0.1)   │
  (curl /   │  ├─ loads model.gguf         │
   any HTTP │  ├─ CPU backend, 4 threads   │
   client)  │  └─ OpenAI-compatible API    │
            └──────────────────────────────┘
```

The server is bound to `127.0.0.1` by default. It is a development/single-user
deployment, not an internet-facing service — see §7 before exposing it.

### Why a server rather than the CLI

`llama-cli` loads the model per invocation and is the right tool for one-shot
prompts and for the benchmark harness. `llama-server` loads the model once and
keeps it resident, which is what makes repeated queries practical on a machine
where load time is a large fraction of the request. The benchmark scripts in
`benchmarks/quantization-track/scripts/` use the CLI deliberately, because
per-process peak RSS is one of the things being measured; serving would
confound that number.

---

## 2. Starting the server

There are two entry points, both driving the same profile flags.

### Background (recommended)

`scripts/deploy.sh` starts the server in the background, records its PID under
`.run/`, and blocks until `/health` reports ready:

```bash
./scripts/deploy.sh models/gemma-4-E2B-it-Q4_0.gguf
```

```
[18:31:36] model   models/gemma-4-E2B-it-Q4_0.gguf (3.0Gi)
[18:31:36] profile default
[18:31:36] binding 127.0.0.1:8080
[18:31:36] log     /repo/.run/server.log
[18:31:36] waiting for health endpoint (timeout 600s, pid 20672)
[18:41:02] ready   http://127.0.0.1:8080  (pid 20672)
```

Before launching it checks that the build exists, that the model file is
present, and that the port is free — so a typo fails immediately instead of
producing a half-started process. If the server exits during startup, `deploy.sh`
reports it and prints the relevant log tail rather than leaving a dead PID file
behind.

```bash
./scripts/status-model.sh      # health, PID, RSS, swap headroom, log tail
./scripts/stop-model.sh        # SIGTERM, wait, then SIGKILL
```

`stop-model.sh` validates that the recorded PID really is `llama-server` before
signalling it, so a recycled PID belonging to some unrelated process is never
killed. Runtime state lives in `.run/` and is git-ignored.

### Foreground

`scripts/run-model.sh` is the same launcher without backgrounding — use it to
watch logs on the terminal, or during debugging:

```bash
./scripts/run-model.sh models/gemma-4-E2B-it-Q4_0.gguf            # default
./scripts/run-model.sh models/gemma-4-E4B-it-Q4_0.gguf e4b        # reduced context
./scripts/run-model.sh models/gemma-4-E2B-it-Q4_0.gguf gpu        # -ngl 99
```

Equivalent raw invocation (**Tested**):

```bash
./llama.cpp/build/bin/llama-server \
  --model models/gemma-4-E2B-it-Q4_0.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  --threads 4
```

`--threads 4` matches the 4 physical cores of the target CPU. `llama-server`
defaults to `-t -1`, which resolves to the same value; it is passed explicitly
so the server configuration matches the configuration used for benchmarking.

On a successful start the log reports the loaded model, the resolved context
size, and the backend in use. With `run-model.sh` the launch is foreground; stop
it with `Ctrl-C`.

---

## 3. Model acquisition

GGUF files are **not committed to this repository** — they are hundreds of
megabytes each and exceed GitHub's 100 MB per-file limit. Fetch them into
`models/`, which is git-ignored.

Pre-built GGUFs were used throughout this project, so no HF→GGUF conversion step
is required:

| Model | Repository | Quantization |
| --- | --- | --- |
| Gemma 4 E2B | `google/gemma-4-E2B-it-qat-q4_0-gguf` | Q4_0 QAT |
| Gemma 4 E4B | `google/gemma-4-E4B-it-qat-q4_0-gguf` | Q4_0 QAT |
| Qwen3.5-4B | `lmstudio-community/Qwen3.5-4B-GGUF` | Q4_K_M |

### Downloading

`scripts/download-model.sh` fetches these over plain `curl` — no
`huggingface-cli` or Python packages required:

```bash
./scripts/download-model.sh --list                        # show presets
./scripts/download-model.sh --preset gemma-4-e2b-qat     # into models/
./scripts/download-model.sh <hf-repo>/<filename> -o <dir>
```

Two properties matter here, because truncated downloads were a real problem
during this project:

- **Resumable.** Partial transfers continue with `curl -C -` rather than starting
  over.
- **Verified.** After transfer it compares the byte count against the size the
  server reports, and checks the file begins with the `GGUF` magic bytes. That
  second check catches the case where a failed or gated request leaves an HTML
  error page saved under a `.gguf` name — a file that passes a size check but
  cannot possibly be a model.

Failures keep the partial file so a rerun resumes rather than re-downloading.

### Verifying the download before serving

Even a size- and magic-verified file can be wrong for a reason curl cannot see.
Confirm it actually loads before building anything around it:

```bash
./llama.cpp/build/bin/llama-cli -m models/<model>.gguf -p "hi" -n 8
```

A `tensor ... data is not within the file bounds` error means the file is
incomplete and should be re-downloaded. This failure mode was observed in this
project and is not specific to any one model.

---

## 4. Memory profiles

The target VM has ~7.7 GiB RAM and 6.0 GiB swap. `llama-server`'s stock
defaults are a logical batch of 2048 and a physical (ubatch) batch of 512, with
the context size taken from the model metadata. That is a reasonable starting
point, but it is not universally affordable at this memory size.

The profiles below are the configurations that were **Tested** on this hardware:

| Profile | Flags | Status | Applies to |
| --- | --- | --- | --- |
| `default` | stock (`-b 2048`, `-ub 512`) | **Tested** | Gemma 4 E2B, Qwen3.5-4B |
| `e4b` | `-c 1024 -b 128 -ub 64` | **Tested** | Gemma 4 E4B |
| `gpu` | `-ngl 99` | Documented, not tested | machines with an NVIDIA GPU |

```bash
./scripts/run-model.sh models/gemma-4-E4B-it-qat-q4_0.gguf e4b
```

Gemma 4 E4B is the reason the `e4b` profile exists. On this VM it needed a
reduced context and batch window to stay inside available memory; at stock
settings it pushed the machine into sustained swap use. The reduced setting
trades context length and prompt throughput for staying resident in physical
memory — which is the correct trade for a machine this size, where swapping
costs far more than the throughput it buys.

If a model still fails to load, reduce `-c` and `-ub` further before reaching
for `-ngl`, since no GPU is available here. `-cmoe` (keep MoE weights on CPU)
is the analogous knob for mixture-of-experts architectures.

---

## 5. Querying the server

The server exposes an OpenAI-compatible HTTP surface. Both endpoints below are
part of the API that was exercised during this project (**Tested** —
[02-model-selection.md](02-model-selection.md)).

Liveness check:

```bash
curl -s http://127.0.0.1:8080/health
```

Chat completion:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local",
    "messages": [{"role": "user", "content": "Summarise what llama.cpp does."}],
    "max_tokens": 128
  }'
```

Interactive OpenAI-compatible clients (Open WebUI, Continue, etc.) can point at
`http://127.0.0.1:8080/v1` with any placeholder model name.

If the server was started with `--api-key`, add it as a bearer token on every
request (the `/health` endpoint stays unauthenticated):

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer $LLAMA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"local","messages":[{"role":"user","content":"hi"}],"max_tokens":32}'
```

Expect single-digit token throughput on CPU. The figures measured in
[02-model-selection.md](02-model-selection.md) are representative: 6.10 tok/s
for Gemma 4 E2B, 3.96 tok/s for Gemma 4 E4B, 2.85 tok/s for Qwen3.5-4B. This
is inherent to CPU inference for models of this size, not a configuration
error — the first token also carries one-time prompt-processing cost
(`pp` in the benchmark output).

---

## 6. Operational notes

Observations from running the server on this VM:

- **CORS is open by default.** Startup logs warn that all origins are allowed
  and no API key is set. Expected for a loopback-only development deployment;
  must be addressed before any network exposure (§7). `deploy.sh` refuses a
  non-loopback bind unless `--api-key`, `--api-key-file`, or an explicit
  `--allow-unauthenticated` override is given, so the unsafe combination cannot
  happen by accident.
- **Swap pressure is the failure mode to watch.** E4B at stock settings was the
  case that drove the machine into swap. `status-model.sh` prints `free -h`
  alongside the server state for exactly this reason.
- **Model load is mmap-based**, so resident memory grows as pages are touched
  rather than at load time. Peak RSS therefore reflects the active context, not
  the file size — this is why benchmark RAM figures are runtime observations.
- **Server logs are verbose** (`verbosity = 3` by default). `-lv N` adjusts it.
  Under `deploy.sh` they go to `.run/server.log` rather than the terminal.
- **Model load is slow on CPU.** A multi-gigabyte GGUF can take minutes to
  become ready. `deploy.sh --timeout` raises the health-wait budget (default
  600s) if needed.

---

## 7. Production readiness

This deployment is **not production-ready**, and no part of this project
assessed it as such. The gaps below are stated explicitly so the boundary is
clear:

| Gap | Status |
| --- | --- |
| Authentication on the HTTP API | **Not configured** — none set by default; `deploy.sh` accepts `--api-key` / `--api-key-file` |
| Network exposure | **Not configured** — loopback bind only |
| TLS termination | **Not configured** — `llama-server` supports `--ssl-key-file` / `--ssl-cert-file`, unused here |
| Process supervision / restart | **Not configured** — no supervisor unit; `stop-model.sh`/`deploy.sh` manage one instance manually |
| Multi-user concurrency | **Not tested** — single client only |
| Capacity limits / rate limiting | **Not implemented** |
| Monitoring and alerting | **Not implemented** — `status-model.sh` is a manual check, not a monitor |

Before exposing this server beyond localhost, the first three rows are
mandatory: set an API key, terminate TLS, and bind deliberately. `deploy.sh`
enforces the first of these by refusing an unauthenticated non-loopback bind, but
that is a guardrail against accidents, not a security control — the underlying
API still has no authorization model, per-request rate limiting, or audit trail.
For anything sustained, run it under a process supervisor (systemd unit or
similar) rather than a background PID file.

---

## 8. Summary

- Build with `scripts/setup.sh`, fetch a model with
  `scripts/download-model.sh`, serve it with
  `scripts/deploy.sh <model.gguf> [profile]`.
- `default` fits Gemma 4 E2B and Qwen3.5-4B on this VM; `e4b` is the reduced
  window Gemma 4 E4B requires; `gpu` offloads all layers on NVIDIA hardware.
- `deploy.sh` runs in the background with a PID file and blocks until healthy;
  `status-model.sh` inspects and `stop-model.sh` stops it. Use `run-model.sh`
  for foreground/console use.
- Models are downloaded, never committed; all three candidates have pre-built
  GGUFs, so no conversion step is needed. `download-model.sh` resumes partial
  transfers and verifies both length and the GGUF header.
- The server exposes an OpenAI-compatible API on loopback, verified during this
  project for all three models.
- Throughput is single-digit tok/s on CPU by nature of the hardware; the
  deployment is suitable for interactive single-user use, not serving.
- Authentication, TLS, and supervision remain unconfigured — see §7.