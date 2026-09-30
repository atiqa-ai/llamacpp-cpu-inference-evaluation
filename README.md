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
| [docs/02-environment.md](docs/02-environment.md) | Build setup (CPU/CUDA/Metal), GGUF format, HF→GGUF conversion, model availability |
| [docs/03-model-selection.md](docs/03-model-selection.md) | Gemma 4 E2B vs E4B vs Qwen3.5-4B — measured throughput, memory, licenses, and the selection rationale |
| [docs/04-deployment.md](docs/04-deployment.md) | Serving with `llama-server`, memory profiles, HTTP API, operational notes, production-readiness gaps |
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
independent. See [03-model-selection.md](docs/03-model-selection.md) §7.

---

## Quick start

```bash
git clone <this-repo>
cd <this-repo>

./scripts/setup.sh                                    # clone + build llama.cpp (CPU)

# then fetch a model into models/ — see docs/04-deployment.md §3
./scripts/run-model.sh models/gemma-4-E2B-it-qat-q4_0.gguf
```

The server listens on `127.0.0.1:8080`:

```bash
curl -s http://127.0.0.1:8080/health
```

### Memory profiles

`run-model.sh` takes an optional profile that sets context/batch flags verified
to fit this class of hardware:

```bash
./scripts/run-model.sh <model.gguf>            # default — Gemma 4 E2B, Qwen3.5-4B
./scripts/run-model.sh <e4b-model.gguf> e4b    # -c 1024 -b 128 -ub 64, required for Gemma 4 E4B
./scripts/run-model.sh <model.gguf> gpu        # -ngl 99 (needs a GGML_CUDA=ON build)
```

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
├── .gitignore
├── docs/
│   ├── 02-environment.md        build setup, GGUF, conversion, model availability
│   ├── 03-model-selection.md    three-model comparison and selection rationale
│   └── 04-deployment.md         llama-server deployment guide
├── scripts/
│   ├── setup.sh                 clone + build llama.cpp (CPU backend)
│   └── run-model.sh             launch llama-server with a memory profile
├── models/                      .gguf files, git-ignored
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
  [04-deployment.md §7](docs/04-deployment.md).

---

## License

Documentation and scripts in this repository are provided as-is for reference.

llama.cpp is licensed under the MIT License — see the upstream
[LICENSE](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE). It is
cloned from upstream and not redistributed here.

Model weights are **not** included. The models referenced (Gemma 4 E2B, Gemma 4
E4B, Qwen3.5-4B) are Apache-2.0 per their respective model cards; consult those
cards for obligations before redistributing any weights.