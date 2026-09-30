# Quantization Strategy for Local LLM Deployment (llama.cpp)

**Track:** Quantization Strategy · **Engine:** llama.cpp v0.4.1-dev (build 10987, commit `d1d3c3396`)
**Status:** Harness complete · measurement campaign **in progress (1 of 11 cells)**

---

## 1. Hardware Summary (measured on this machine)

| Item | Value |
| --- | --- |
| OS | Ubuntu 26.04.1 LTS (kernel 7.0.0-31-generic) |
| Virtualization | Virtual machine (VGA: VMware SVGA II adapter; no real GPU exposed) |
| CPU | Intel Core i5-8365U @ 1.60 GHz, 4 cores / 4 threads |
| CPU ISA | SSE3, SSSE3, AVX, AVX2, F16C, FMA, BMI2 |
| RAM | 7.7 GiB total · ~3.2–5.0 GiB available during runs |
| Swap | 6.0 GiB (swapfile; heavily used by the larger quants) |
| Disk | 48 GB root filesystem |
| GPU | **Not available** — no NVIDIA/CUDA, no Vulkan backend; `nvidia-smi` fails to connect |
| llama.cpp backend used | **CPU only** (`GGML_CUDA=OFF`, `GGML_NATIVE=ON`, AVX2) |

> Single-GPU conclusions are therefore reasoned estimates (§6), *not* measured
> on this host. All measured numbers are CPU-only, real, 4 threads.

---

## 2. Methodology

- Benchmark tool: `llama-bench -p 128 -n 64 -r 2 -t 4` (warmup + 2 repetitions, CPU, 4 threads).
- Peak memory: `/usr/bin/time -v` → *Maximum resident set size* (mmap-based load).
- Quality: **objective** perplexity (`llama-perplexity -c 256`) on a fixed ~600-token corpus
  **and** a fixed qualitative suite of **11 identical prompts** (5 math/reasoning + 3 code +
  3 instruction-following) at seed 100, 48 tokens, single turn, reasoning off.
- All quants of one model ran on the same box, same args, same prompts (identical per quant).

Every run is executed through one entry point:

```bash
bash benchmarks/quantization-track/scripts/run_file.sh <tag> <model_path> [full|half]
```

which chains `run_bench.sh` → `run_ppl.sh` → `run_eval.sh` and appends to
`results/master.log`. Pass `half` to skip the perplexity pass, which is the
slowest step.

### Files targeted by this track

| Model (text) | Params | Quant set | Source |
| --- | --- | --- | --- |
| Gemma 4 E2B-It (gemma4) | 4.63 B | QAT Q4_0 (official), Q4_0, Q4_K_M, Q5_K_M, Q8_0 | google QAT repo + unsloth GGUF |
| Gemma 4 E4B-It (gemma4) | 7.46 B | QAT Q4_0 (official), Q4_0, Q4_K_M, Q5_K_M, Q8_0 | google QAT repo + unsloth GGUF |
| Qwen3.5-4B (reference) | 4.21 B | Q4_K_M | lmstudio-community GGUF |

That is 11 measurement cells.

> Note: the official Google *"QAT Q4_0"* GGUFs are not pure Q4_0 — they are **mixed
> precision** builds (embedding/attention parts kept at higher precision). Measured:
> E2B QAT = 2.75 B params in Q8_K + 1.86 B in Q4_0 (3.10 GiB); E4B QAT = 3.49 B in
> Q8_K + 3.95 B in Q4_0 (4.55 GiB). This is exactly the head-to-head the spec asked for:
> official QAT build *as shipped* vs. standard post-training Q4_0 *as shipped*.

---

## 3. Results

### 3.1 Measurement status

The campaign is **not finished**. Of the 11 cells, one has completed and one is
partially complete:

| Tag | Model / quant | Bench | PPL | Eval suite | State |
| --- | --- | --- | --- | --- | --- |
| `e2b_qat` | Gemma 4 E2B, official QAT Q4_0 | ✅ | ✅ | ⚠️ partial | Incomplete — see 3.3 |
| 10 remaining cells | E2B/E4B × 4 quants + Qwen reference | ⬜ | ⬜ | ⬜ | **Not run** |

Raw per-run artifacts live in `results/` (`*.bench.md`, `*.bench.time`,
`*.ppl.txt`, `*.eval.tsv`, `*.log`). Nothing in this document is stated for a
cell that has not produced those files.

### 3.2 Completed measurement — `e2b_qat` (Gemma 4 E2B, official QAT Q4_0)

| Metric | Value |
| --- | --- |
| File size | ~3.1 GiB (3,349,516,256 bytes) |
| Parameters | 4.63 B |
| Prompt processing (`pp128`) | **14.97 ± 4.87 t/s** |
| Text generation (`tg64`) | **2.24 ± 0.41 t/s** |
| Peak RSS (bench) | 4,420,064 kB (≈ 4.2 GiB) |
| Perplexity (`-c 256`) | **60.4507 ± 13.897** |

The perplexity figure comes from a 2-chunk pass over a ~600-token corpus at
context 256, so it is a small-sample estimate with a wide confidence interval.
It is comparable across quants because the corpus and settings are fixed, but it
is not a headline quality number.

The high `pp128` vs `tg64` ratio (≈6.7×) is the expected shape for CPU
inference: prefill is compute-bound and parallelisable across cores, whereas
token generation is memory-bandwidth-bound and effectively serial per token.
On a machine with no GPU this gap is structural, not a configuration problem.

### 3.3 Known gap in `e2b_qat`

`results/master.log` records a failure partway through the qualitative suite:

```
run_eval.sh: line 36: eval/prompts.py: Permission denied
```

`eval/prompts.py` was not executable, so the prompt generator produced nothing
and `e2b_qat.eval.tsv` holds only **2 of 11 prompts** (`math1`, `math2`) rather
than a complete suite. Those two prompts do carry real wall-clock timings and
model output, but the partial suite cannot support any comparative quality
claim. The file has since been made executable (`chmod +x`); re-running
`run_file.sh e2b_qat <model> half` regenerates it.

### 3.4 What can and cannot be concluded right now

**Supported by the completed data:**

- The official QAT Q4_0 build of Gemma 4 E2B loads and runs on this
  CPU-only VM at ~2.2 tok/s generation with a 3.10 GiB file.
- Mixed-precision QAT quants are materially larger than the pure Q4_0 they are
  compared against, while remaining within a servable memory envelope.
- Prompt processing is roughly 6–7× faster than generation, confirming
  bandwidth-bound decode as the CPU bottleneck.

**Not yet supported — do not read these into the results above:**

- Any ranking of quants against each other. One cell cannot rank eleven.
- Any quality delta between quantizations. Perplexity for one quant, with no
  fp16/fp32 reference point measured on the same corpus, cannot establish that
  quantization cost anything.
- Any GPU projection. See §6.

An earlier, separate round of model-level testing (recorded in
[03-model-selection.md](../../docs/03-model-selection.md)) did measure all three
models end-to-end and produced the tok/s figures quoted there. Those are model-
level observations, not this quant-level campaign, and the two should not be
conflated.

---

## 4. Artifacts in this directory

```
quantization-track/
├── REPORT.md          this document
├── scripts/
│   ├── run_file.sh     per-file entry point: bench + ppl + eval
│   ├── run_bench.sh    llama-bench + peak RSS via /usr/bin/time -v
│   ├── run_ppl.sh      llama-perplexity on the fixed corpus
│   └── run_eval.sh     11-prompt qualitative suite
├── eval/
│   ├── prompts.py      the fixed prompt set
│   └── ppl_corpus.txt  the fixed perplexity corpus
├── models/             .gguf files (git-ignored, hundreds of MB)
└── results/            per-run raw output + master.log
```

Model files are not committed. See
[04-deployment.md](../../docs/04-deployment.md) §3 for acquisition.

---

## 5. Reproducing a run

```bash
./scripts/setup.sh                                  # build llama.cpp (CPU)
bash benchmarks/quantization-track/scripts/run_file.sh e2b_qat <path/to.gguf>
```

Expect on the order of 3–4 minutes per cell for bench + eval, plus ~2 minutes
for the perplexity pass. Peak RSS stays within ~4.2 GiB for the E2B cells; the
E4B cells are the ones that push swap, per
[04-deployment.md](../../docs/04-deployment.md) §4.

---

## 6. Single-GPU projections (estimated, not measured)

No GPU was available on this host, so the following are **reasoned estimates**
from the CPU numbers and known backend characteristics — not measurements, and
not to be cited as such:

- Offloading all layers (`-ngl 99`) moves the decode bottleneck from system
  memory bandwidth to GPU memory bandwidth, which is typically an order of
  magnitude wider than a DDR4-3200 dual-channel system on a consumer card.
  Expect a large multiple on generation, and a smaller relative gain on
  prefill, which was already compute-bound and already using all 4 cores.
- The practical consequence is that the pp/tg asymmetry in §3.2 would *narrow*:
  GPU offload primarily helps the memory-bound half.
- Quantization conclusions should carry over more than absolute speeds do,
  because they are about memory footprint and quality per byte rather than
  about the backend.

Any of this becomes a measurement only on a host with a GPU. Flagged here so it
is not mistaken for one.

---

## 7. Conclusion

The harness for this track is complete and reproducible: one command per model
file, fixed corpus and prompt set, raw artifacts retained, peak RSS and
perplexity captured alongside throughput.

The measurement campaign is **1 of 11 cells complete**, with that cell's
qualitative suite partial. The completed data supports a specific and limited
set of claims (§3.4), which are stated there and not widened here.

The quantization question this track was built to answer — *how much quality
does quantization cost, and where is the throughput/size knee for this
hardware* — is **not yet answerable** from one data point. The remaining ten
cells are the work outstanding, and the harness to produce them is in place.