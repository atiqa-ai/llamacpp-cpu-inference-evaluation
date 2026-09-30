# Model Candidate Evaluation — Gemma 4 E2B vs E4B vs Qwen3.5-4B

Status labels used in this document:

- **Tested** — verified on the current Ubuntu CPU-only VM.
- **Measured** — numeric value captured during project testing on the current VM.
- **Documented** — based on official model documentation, not measured here.

---

## 1. Evaluation Objective

This document evaluates three local LLM candidates for the project's target
hardware:

- **Gemma 4 E2B** (`Q4_0` QAT GGUF)
- **Gemma 4 E4B** (`Q4_0` QAT GGUF)
- **Qwen3.5-4B** (`Q4_K_M` GGUF)

The goal is to decide which model is the practical primary candidate for
CPU-only local inference in this project, and to understand the tradeoff
between the two Gemma 4 sizes (E2B vs E4B). Qwen3.5-4B is included as a
reference model of comparable size from a different family.

All three models were already downloaded, loaded with llama.cpp, exercised
through `llama-cli`, deployed with `llama-server`, and queried through the
server's HTTP API on this VM. This document is written from those recorded
project observations; it does not re-download, re-deploy, or re-benchmark the
models.

## 2. Target Hardware and Test Environment

| Item | Value |
| --- | --- |
| Operating system | Ubuntu (Linux) |
| Virtualization | VirtualBox virtual machine |
| Compute backend | CPU only (no NVIDIA GPU, no Apple GPU) |
| RAM | ~7.7 GiB |
| Swap | ~6.0 GiB |
| llama.cpp | CPU-only build (`GGML_CUDA=OFF`, `GGML_METAL=OFF`, `GGML_NATIVE=ON`) |

The environment is pure CPU. Inference performance and memory behavior observed
here are representative of CPU-only execution; GPU-backed numbers from external
sources would not apply to this machine.

## 3. Models Evaluated

### Gemma 4 E2B (`gemma-4-E2B-it-qat-q4_0-gguf`, Q4_0 QAT)

The smaller of the two Gemma 4 candidates. Per the official Gemma 4 model card,
"E" denotes **effective** parameters: E2B has 2.3B effective parameters (5.1B
total including embeddings). E2B is aimed at mobile and edge deployments.
**Status:** Tested.

### Gemma 4 E4B (`gemma-4-E4B-it-qat-q4_0-gguf`, Q4_0 QAT)

The larger Gemma 4 candidate: 4.5B effective parameters (8B total including
embeddings) per the official model card. Also aimed at on-device scenarios but
with greater model capacity. **Status:** Tested.

### Qwen3.5-4B (`lmstudio-community/Qwen3.5-4B-GGUF`, Q4_K_M)

A compact 4B dense model from the Qwen3.5 family (Alibaba). It is a
vision-language model with a native 262K context, but was exercised here as a
text-only local model with reasoning disabled. It serves as the external
reference point for the two Gemma 4 variants. **Status:** Tested.

## 4. Side-by-Side Comparison

| Criterion | Gemma 4 E2B | Gemma 4 E4B | Qwen3.5-4B |
| --- | --- | --- | --- |
| **Model family** | Google DeepMind Gemma 4 | Google DeepMind Gemma 4 | Qwen 3.5 (Alibaba) |
| **GGUF quantization** | Q4_0 QAT | Q4_0 QAT | Q4_K_M |
| **Quality (practical observation)** | Coherent responses; smallest of the two Gemma sizes (2.3B effective parameters) | Coherent responses; larger model capacity than E2B (4.5B effective parameters) | Coherent responses; reference model, comparable small local size |
| **Generation speed (measured)** | 6.10 tok/s | 3.96 tok/s | 2.85 tok/s |
| **RAM used (observed)** | 3.1 GiB | 2.8 GiB | 3.7 GiB |
| **Swap used (observed)** | 346 MiB | 1.1 GiB | 620 KiB |
| **License** | Apache-2.0 | Apache-2.0 | Apache-2.0 |

> The speed, RAM, and swap figures above are **observed project benchmark
> results** collected during practical CPU-only validation on this VM. They are
> not a perfectly controlled scientific benchmark across every variable; RAM
> and swap are runtime observations and must not be interpreted as exact model
> file sizes. Quality is a qualitative observation (see section 6).

## 5. Performance and Resource Findings

The measured values are:

| Model | Generation Speed | RAM Used | Swap Used |
| --- | --- | --- | --- |
| Gemma 4 E2B | 6.10 tok/s | 3.1 GiB | 346 MiB |
| Gemma 4 E4B | 3.96 tok/s | 2.8 GiB | 1.1 GiB |
| Qwen3.5-4B | 2.85 tok/s | 3.7 GiB | 620 KiB |

Key observations:

- **Gemma 4 E2B produced the highest measured generation throughput.** It is
  the fastest of the three on this CPU-only VM, with moderate RAM and swap
  usage.
- **Gemma 4 E4B was slower than E2B and showed higher swap pressure.** It
  returned a lower generation speed (3.96 tok/s) and used significantly more
  swap (1.1 GiB) than E2B. Because of this, E4B was exercised with reduced
  context/batch settings (context 1024, batch 128, ubatch 64) to stay within
  the available memory.
- **Qwen3.5-4B had the lowest measured generation speed** (2.85 tok/s) of the
  three, and showed very low swap usage (620 KiB) during the recorded server
  resource observation.
- RAM and swap figures are runtime observations, not exact model file sizes;
  they vary with context length, batch size, server workload, and other
  factors.

## 6. Quality Comparison

Quality is compared **qualitatively** in this project. No numerical quality
score is assigned: the project did not run accuracy or benchmark suites that
would support one.

Observed behavior:

- All three models generated coherent responses during testing (CLI and API).
- Gemma 4 E2B and E4B belong to the same Gemma 4 model family; E4B provides
  the larger model capacity of the two.
- Qwen3.5-4B is a useful reference model because it is also a small, local
  GGUF model suitable for CPU-oriented testing.

No claim is made that any single model is universally "more intelligent" or
"better" — such a conclusion would require documented evidence the project does
not have. Quality here is an observed inference-behavior characteristic, while
throughput and resource figures are measured.

## 7. License Comparison

License information was verified against current official sources (September
2026):

| Model | License | Verified source |
| --- | --- | --- |
| Gemma 4 E2B | Apache-2.0 | Official `google/gemma-4-E2B` Hugging Face model card (`license: apache-2.0`, links to the official Gemma 4 license page: `https://ai.google.dev/gemma/docs/gemma_4_license`) |
| Gemma 4 E4B | Apache-2.0 | Official `google/gemma-4-E4B` Hugging Face model card (same license field and link as above) |
| Qwen3.5-4B | Apache-2.0 | Official `Qwen/Qwen3.5-4B` Hugging Face model card (`license: apache-2.0`, `license_link` points to the repo `LICENSE`) |

Key points:

- The **model licenses** (Apache-2.0 for all three) are separate and distinct
  from the **llama.cpp software license**, which is MIT. Runtime software and
  model weights are licensed independently; using the models with llama.cpp
  does not change either license.
- Apache-2.0 is a permissive license that permits commercial use, modification,
  and redistribution, subject to its conditions (e.g., preserving attribution
  and license notices). Where the official cards publish the full license text,
  that text is the authoritative reference for exact obligations.
- The Gemma 4 license terms are published by Google at
  `https://ai.google.dev/gemma/docs/gemma_4_license`; the Qwen 3.5 terms live in
  the model repository `LICENSE` file. Confirm the specific obligation details
  against those official texts before redistributing any of these models.

## 8. Gemma E2B vs E4B Tradeoff

### Gemma 4 E2B

**Advantages on this hardware:**
- Highest observed generation speed in this project (6.10 tok/s).
- Practical resource profile: 3.1 GiB RAM / 346 MiB swap in the recorded
  observation, leaving more headroom on a ~7.7 GiB CPU-only VM.
- Better fit for responsive local inference under constrained hardware.

**Tradeoffs:**
- Lower model capacity than E4B within the same family; for workloads where
  the additional E4B capacity matters, E2B is the weaker candidate.

### Gemma 4 E4B

**Advantages:**
- Larger model capacity (4.5B effective parameters vs 2.3B for E2B), which can
  offer better quality per response — a documented family property, but quality
  was not scored in this project (see section 6).
- Reported RAM footprint in the recorded observation (2.8 GiB) was not higher
  than E2B's.

**Tradeoffs:**
- Lower observed generation speed: 3.96 tok/s vs 6.10 tok/s for E2B.
- Higher swap usage (1.1 GiB) during testing, indicating more memory pressure.
- Required reduced context/batch settings (1024 / 128 / 64) to run on this VM,
  i.e., less headroom.

### Impact on the current hardware

Both models run on the current CPU-only VM. E2B does so comfortably with the
best measured throughput; E4B runs only with reduced context/batch settings
and leaves less memory headroom while being slower. On this specific hardware,
going from E2B to E4B trades ~35% of measured generation throughput for model
capacity, while squeezing closer to the memory ceiling.

## 9. Qwen3.5-4B Reference Comparison

Qwen3.5-4B's role in this evaluation is as a **reference model**:

- It successfully ran on the same CPU-only environment, loaded with llama.cpp,
  and was deployed through `llama-server` and exercised via the HTTP API.
- It achieved 2.85 tok/s generation in the recorded server benchmark — the
  lowest measured speed of the three.
- It used 3.7 GiB RAM and 620 KiB swap in the recorded resource observation —
  the highest RAM figure and by far the lowest swap figure, showing the model
  stayed within physical memory for the observed server workload.
- Reasoning was explicitly disabled (`--reasoning off`) for the controlled
  test, so the recorded throughput reflects non-reasoning generation.

Interpretation for context: Qwen3.5-4B proves a third, comparably sized
Apache-2.0 model family runs acceptably on this VM, but its measured speed was
below both Gemma variants. It functions as a sanity check that the Gemma 4
numbers sit within a realistic CPU-only range, not as evidence that Gemma is
"better" — and it is not treated as the primary candidate.

## 10. Model Selection Recommendation

This recommendation is specific to **this project's target hardware**: a
CPU-only Ubuntu VM with ~7.7 GiB RAM and 6 GiB swap running llama.cpp.

**Primary candidate: Gemma 4 E2B (Q4_0 QAT).**

Reasoning, from the measured results and hardware constraints:

- It produced the highest observed generation speed (6.10 tok/s), which matters
  most for responsive local inference on a CPU-only machine.
- With 3.1 GiB RAM and 346 MiB swap observed, it leaves the most headroom on a
  VM with only ~7.7 GiB of memory, reducing the risk that context growth or
  concurrent work pushes the VM into sustained swapping.
- Deployment was straightforward (CLI, `llama-server`, and API all verified)
  with no need for reduced context/batch settings.

**E4B's role:** Gemma 4 E4B is the secondary candidate. Choose it only when the
additional model capacity/quality is worth the measured tradeoffs on this
hardware: roughly 35% lower generation throughput, greater swap pressure, and
the need to run with reduced context/batch settings. On this VM it does run,
but with correspondingly less headroom.

**Qwen3.5-4B's role:** Reference only. Its measured speed (2.85 tok/s) was the
lowest of the three, so it is not the primary candidate for this project.

Neither candidate is "the best model" universally; this is a hardware-specific
selection. E2B is the more practical primary candidate for **this** CPU-only
environment, with E4B retained as an option if model capacity becomes the
binding requirement.

## 11. Conclusion

The project benchmark and testing effort showed that Gemma 4 E2B, E4B, and
Qwen3.5-4B are all usable with llama.cpp on the CPU-only VM, and all three are
Apache-2.0 licensed.

For the project's target hardware, Gemma 4 E2B is the practical primary
candidate: the best measured generation speed, a comfortable resource profile,
and full headroom under ~7.7 GiB RAM. Gemma 4 E4B remains a viable secondary
candidate where larger model capacity justifies lower throughput and higher
memory pressure. Qwen3.5-4B served as a successful cross-family reference
point, though its measured speed made it non-competitive as the primary model
here.