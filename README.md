# llama.cpp CPU Inference Evaluation

An evaluation of running local LLMs with [llama.cpp](https://github.com/ggml-org/llama.cpp)
on **CPU-only, memory-constrained hardware**, and a deployment guide for the
resulting setup.

The target machine is a 4-core Intel i5-8365U VM with ~7.7 GiB RAM, 6.0 GiB
swap, and **no GPU**. Every measured number in this repository was produced on
that machine with the CPU backend; GPU figures are explicitly labelled as
estimates and are never presented as measurements.

---

## What this project covers

| Document | Contents |
| --- | --- |
| [docs/01-environment.md](docs/01-environment.md) | Build setup (CPU/CUDA/Metal), GGUF format, HF→GGUF conversion, model availability |
| [docs/02-model-selection.md](docs/02-model-selection.md) | Gemma 4 E2B vs E4B vs Qwen3.5-4B — measured throughput, memory, licenses, and the selection rationale |
| [docs/03-deployment.md](docs/03-deployment.md) | Serving with `llama-server`, memory profiles, HTTP API, operational notes, production-readiness gaps |
| [benchmarks/quantization-track/REPORT.md](benchmarks/quantization-track/REPORT.md) | Quantization campaign — harness, methodology, results status |

---

## Headline result

**Gemma 4 E2B (Q4_0 QAT) is the recommended model for this hardware.**

Measured on the target VM, across all three candidates:

| Model | Quant | Generation | RAM | Swap | Verdict |
| --- | --- | ---: | ---: | ---: | --- |
| **Gemma 4 E2B** | Q4_0 QAT | **6.10 tok/s** | 3.1 GiB | 346 MiB | **Recommended** |
| Gemma 4 E4B | Q4_0 QAT | 3.96 tok/s | 2.8 GiB | 1.1 GiB | Secondary — more capacity, less speed |
| Qwen3.5-4B | Q4_K_M | 2.85 tok/s | 3.7 GiB | 620 KiB | Reference only |

E2B wins on measured throughput and leaves the most memory headroom on a 7.7 GiB
machine, and it runs at stock server settings. E4B trades roughly 35% of
throughput for additional model capacity and needs a reduced context/batch
window to stay resident. Qwen3.5-4B serves as a cross-family sanity check; its
speed was the lowest of the three.

All three models are Apache-2.0. llama.cpp itself is MIT — the two licenses are
independent. See [02-model-selection.md](docs/02-model-selection.md) §7.

---

## Quick start

```bash
git clone <this-repo>
cd <this-repo>

./scripts/setup.sh                                  # 1. clone + build llama.cpp (CPU)
./scripts/download-model.sh --preset gemma-4-e2b-qat  # 2. fetch a GGUF into models/
./scripts/deploy.sh models/gemma-4-E2B-it-Q4_0.gguf  # 3. start serving in the background
```

`deploy.sh` waits until the server reports healthy, then returns. Check and stop it with:

```bash
./scripts/status-model.sh      # health, PID, memory, log tail
./scripts/stop-model.sh        # graceful stop, escalating to SIGKILL if needed
curl -s http://127.0.0.1:8080/health
```

Available model presets: `--list`.

### Memory profiles

Both `deploy.sh` and `run-model.sh` take a profile that sets context/batch flags
verified to fit this class of hardware:

| Profile | Flags | Use for |
| --- | --- | --- |
| `default` | stock (`-b 2048`, `-ub 512`) | Gemma 4 E2B, Qwen3.5-4B |
| `e4b` | `-c 1024 -b 128 -ub 64` | Gemma 4 E4B — required on this VM |
| `gpu` | `-ngl 99` | machines with an NVIDIA GPU (needs `GGML_CUDA=ON`) |

```bash
./scripts/deploy.sh <model.gguf>                  # default
./scripts/deploy.sh <e4b-model.gguf> e4b --port 8123
```

`run-model.sh` is the same launcher without the backgrounding — use it to attach
to the server console, or with `--foreground` to keep logs on the terminal.

### Binding beyond localhost

The HTTP API has **no authentication by default**. `deploy.sh` refuses a
non-loopback bind unless you pass `--api-key`, `--api-key-file`, or an explicit
`--allow-unauthenticated` override. See
[docs/03-deployment.md](docs/03-deployment.md) §7 before exposing it.

---

## Benchmarking

The quantization track runs a fixed benchmark per model file — throughput, peak
RSS, perplexity, and an 11-prompt qualitative suite:

```bash
bash benchmarks/quantization-track/scripts/run_file.sh <tag> <path/to.gguf> [full|half]
```

Everything is pinned so quants are comparable: `-p 128 -n 64 -r 2 -t 4`, a
fixed ~600-token perplexity corpus, and a fixed prompt set at seed 100. Raw
per-run output is retained in `results/`.

> **Campaign status: 1 of 11 cells complete.** The harness is finished and
> reproducible; the remaining measurements are outstanding. The report states
> precisely what the completed data does and does not support rather than
> filling the gap with estimates. See
> [REPORT.md §3.4](benchmarks/quantization-track/REPORT.md).

---

## Repository layout

```
.
├── README.md
├── LICENSE                       MIT (see note on third-party code below)
├── .gitignore
├── .gitattributes
├── docs/
│   ├── 01-environment.md        build setup, GGUF, conversion, model availability
│   ├── 02-model-selection.md    three-model comparison and selection rationale
│   └── 03-deployment.md         llama-server deployment guide
├── scripts/
│   ├── setup.sh                 clone + build llama.cpp (CPU backend)
│   ├── download-model.sh        fetch a GGUF from Hugging Face (resumable, verified)
│   ├── deploy.sh                start the server in the background, wait for health
│   ├── stop-model.sh            graceful stop via PID file
│   ├── status-model.sh          health, process, memory, log tail
│   └── run-model.sh             foreground launcher with a memory profile
├── models/                      .gguf files, git-ignored
├── .run/                        deployment pid/log/metadata, git-ignored
└── benchmarks/
    ├── quantization-track/
    │   ├── REPORT.md            methodology, results, status
    │   ├── scripts/             run_file / run_bench / run_ppl / run_eval
    │   ├── eval/                fixed prompt set + perplexity corpus
    │   ├── models/              .gguf files, git-ignored
    │   └── results/             raw per-run output
    └── results/
```

**llama.cpp is not vendored in this repository.** It is cloned from upstream by
`scripts/setup.sh` and pinned to a known commit in the docs. Weights are not
committed either — they are hundreds of megabytes each and exceed GitHub's
100 MB per-file limit.

---

## Conventions used in the documentation

Every claim carries one of three labels, so measured and estimated results are
never confused:

- **Tested / Measured** — executed on the target VM; the numbers are real.
- **Documented / Not tested** — correct per upstream llama.cpp or model cards,
  but not executed here because the hardware was unavailable (e.g. CUDA, Metal).
- **Estimated** — reasoned projection from measured data, not a measurement.

Resource figures are described as *runtime observations*, not file sizes: GGUF
models are mmap-loaded, so resident memory grows with the active context and
varies with workload.

---

## Limitations

Stated up front, because they bound everything above:

- **Single machine, no GPU.** CUDA and Metal paths are documented but unverified
  here. All measured results are CPU-only on 4 threads.
- **Small sample.** Perplexity uses a ~600-token corpus, giving wide confidence
  intervals.
- **Quantization campaign incomplete.** 1 of 11 cells; no quant-to-quant ranking
  is supported yet.
- **Quality is qualitative.** No accuracy suite was run, so no numerical quality
  score is claimed anywhere in this repository.
- **Not production-ready.** No auth, no TLS, no supervision. See
  [03-deployment.md §7](docs/03-deployment.md).

---

## License

The documentation and scripts in this repository are MIT licensed — see
[LICENSE](LICENSE). This repository contains no third-party source code.

**llama.cpp** is separately MIT licensed. It is cloned from upstream by
`scripts/setup.sh` and is **not** vendored or redistributed here.

**Model weights are not included.** The models referenced by the documentation —
Gemma 4 E2B, Gemma 4 E4B, and Qwen3.5-4B — are licensed separately by their
publishers, Apache-2.0 per their respective Hugging Face model cards. Those cards
are the authoritative source for the terms; consult them before redistributing
any weights.