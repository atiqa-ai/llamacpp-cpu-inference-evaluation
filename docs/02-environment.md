# Environment & Build Setup

This document describes the environment and build setup for running llama.cpp
with a single machine (CPU or one consumer GPU), and the pipeline for getting
models into the GGUF format that llama.cpp uses.

> Legend for status labels used throughout this document:
>
> - **Tested** — verified on the current Ubuntu VM.
> - **Documented / Not tested on current environment** — correct per official
>   llama.cpp documentation, but not executed here (hardware not available).

---

## 1. Environment Overview

| Item | Value |
| --- | --- |
| Operating system | Ubuntu (Linux) |
| Virtualization | VirtualBox virtual machine |
| Compute backend | CPU only (no NVIDIA GPU, no Apple hardware) |
| llama.cpp | Cloned and already built successfully (v0.4.1-dev, commit `d1d3c3396`) |
| Python tooling | Available for Hugging Face / GGUF tooling |
| Models (already downloaded, GGUF) | Gemma 4 E2B / E4B and Qwen3.5-4B (see section 8) |

The VM is pure CPU. No NVIDIA GPU is present, so no CUDA runtime exists, and
Apple Metal cannot be exercised on this system. The CUDA and Metal build
configurations in sections 3 and 4 are therefore documented for future
hardware only.

---

## 2. llama.cpp Build Setup

### Single-machine approach

llama.cpp is built from source with CMake. For a single machine you build one
binary set that uses the best available backend on that machine:

- No GPU present → the CPU backend is the only backend that must be enabled.
- One consumer NVIDIA GPU → enable the CUDA backend (`GGML_CUDA=ON`).
- Apple Silicon / macOS → enable the Metal backend (`GGML_METAL`, on by default on macOS).

Everything is then driven by the same tools
(`llama-cli`, `llama-server`, `llama-bench`, ...), pointed at GGUF model files.

### CPU-only build (state of this VM)

**Tested.** The build directory in `llama.cpp/build/` records the following
verified configuration (from `CMakeCache.txt`):

| Setting | Value (this VM) |
| --- | --- |
| `CMAKE_BUILD_TYPE` | `Release` |
| `GGML_CUDA` | `OFF` |
| `GGML_METAL` | `OFF` (default on Linux) |
| `GGML_NATIVE` | `ON` (optimize for the host CPU) |
| `GGML_LLAMAFILE` | `ON` |
| Compiler | GCC (`/usr/bin/cc`, `/usr/bin/c++`) |
| Backends actually built | CPU only (only `libggml-cpu.so` backend present) |
| Tools built | `LLAMA_BUILD_SERVER=ON`, tools and examples built (`llama-cli`, `llama-server`, `llama-bench`, ...) |

The command described by this configuration:

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j
```

`-j` runs the build with multiple jobs in parallel to save time. The build was
completed successfully; the binaries are under `llama.cpp/build/bin/`.

### Important CMake / build options

| Option | Default | Purpose |
| --- | --- | --- |
| `CMAKE_BUILD_TYPE` | `Release` on single-config generators | `Release` enables optimizations; `Debug` disables them. |
| `GGML_NATIVE` | `ON` (unless cross-compiling) | Compiles for the host CPU (`-march=native`) for maximum speed. |
| `GGML_LLAMAFILE` | `ON` | Includes the llamafile SGEMM kernels, used for fast CPU matrix multiplication. |
| `GGML_CUDA` | `OFF` | Enables the NVIDIA CUDA backend. |
| `GGML_METAL` | `ON` on macOS, `OFF` elsewhere | Enables the Apple Metal backend. |
| `BUILD_SHARED_LIBS` | `ON` | Build shared libraries instead of static if set to `OFF`. |

---

## 3. Single NVIDIA GPU Build (CUDA)

**Documented / Not tested on current environment.** The commands below follow
the official llama.cpp build guide and are intended for a machine with one
consumer NVIDIA GPU (e.g. an RTX-series card). They were **not** executed on
this VM.

Requirements: the [NVIDIA CUDA toolkit](https://developer.nvidia.com/cuda-toolkit)
installed with `nvcc` available on `PATH`.

```bash
cmake -B build -DGGML_CUDA=ON
cmake --build build --config Release -j
```

Relevant CUDA flags:

| Option | Purpose |
| --- | --- |
| `GGML_CUDA=ON` | The master switch that enables the NVIDIA CUDA backend. |
| `CMAKE_CUDA_ARCHITECTURES` | Overrides the GPU compute capabilities compiled for, e.g. `-DCMAKE_CUDA_ARCHITECTURES="86;89"` for an RTX 30xx/40xx-class card. By default llama.cpp targets the GPUs detected in the build machine. |
| `GGML_NATIVE=OFF` | Non-native build: produces a binary that runs on any CUDA GPU (larger binary, longer compile). Not needed for one fixed GPU. |
| `GGML_CUDA_FORCE_MMQ` / `GGML_CUDA_FORCE_CUBLAS` | Keep defaults; only for specialized matrix-multiplication tuning. |
| `GGML_CUDA_FA` | Runtime FlashAttention CUDA kernels, `ON` by default. |

At runtime, use `--n-gpu-layers` (e.g. `-ngl 99`) to offload all layers to the
GPU.

---

## 4. Apple Metal Build

**Documented / Not tested on current environment.** Metal is the llama.cpp GPU
backend for macOS / Apple Silicon (M-series) hardware. It cannot be built or
run on this Ubuntu VM.

On macOS, Metal support is enabled by default, so the plain CMake build
already uses the GPU:

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j
```

To be explicit, or on a non-Apple host with Metal tooling present:

```bash
cmake -B build -DGGML_METAL=ON
cmake --build build --config Release -j
```

Relevant Metal flags:

| Option | Default | Purpose |
| --- | --- | --- |
| `GGML_METAL` | `ON` on macOS, `OFF` elsewhere | Master switch for the Metal backend. |
| `GGML_METAL_EMBED_LIBRARY` | `ON` (macOS) | Embeds the compiled Metal shader library in the binary. |
| `GGML_METAL_SHADER_DEBUG` | `OFF` | Enables Metal shader debugging; for development only. |
| `GGML_METAL_MACOSX_VERSION_MIN` | empty | Sets the minimum macOS version for the Metal build. |

When built with Metal, GPU inference can still be disabled at runtime with
`--n-gpu-layers 0`.

> Note: on Apple Silicon, enabling the CUDA backend is not applicable; the CPU
> + Metal backends cover the hardware. On this VM neither GPU backend was used.

---

## 5. GGUF Model Format

**GGUF** (GPT-Generated Unified Format) is the file format llama.cpp uses to
store the weights and metadata of a model in a single portable file. Each GGUF
file embeds:

- the model weights, in a plain or quantized precision (e.g. `Q4_0`, `Q4_K_M`, `f16`, `bf16`);
- the model architecture and configuration (layer counts, context length, etc.);
- the tokenizer and chat template.

llama.cpp uses GGUF because the format is self-describing and self-contained:
the runtime reads everything it needs from the file, supports a wide range of
quantizations to fit available RAM, and needs no external framework to load a
model. That is what makes local, CPU-first inference practical.

---

## 6. Hugging Face to GGUF Conversion Pipeline

### Workflow

```
Hugging Face model
        │
        ▼
Transformers / Python environment
        │
        ▼
convert_hf_to_gguf.py
        │
        ▼
GGUF model
        │
        ▼
llama.cpp
```

### What `convert_hf_to_gguf.py` does

It reads a Hugging Face model checkpoint (a directory with `config.json`,
`tokenizer.model`, `.safetensors`, etc.), maps the model architecture to a
concrete llama.cpp definition, and writes a GGUF file ready for `llama-cli`,
`llama-server`, etc.

### Location

The script lives at the root of the llama.cpp repository:

```
llama.cpp/convert_hf_to_gguf.py
```

It requires a Python 3.9+ environment with `torch`, `transformers`,
`sentencepiece`, `numpy`, and `protobuf`. The pinned dependencies are in
`llama.cpp/requirements.txt` (see `requirements/`).

### General usage

```bash
python3 convert_hf_to_gguf.py <input-model-dir> \
    --outfile <output.gguf> \
    --outtype f16
```

The `<input-model-dir>` is a directory of a Hugging Face checkpoint that has
already been downloaded locally.

Important options:

| Option | Purpose |
| --- | --- |
| `--outtype` | Output precision: `f32`, `f16`, `bf16`, `q8_0`, ternary types, or `auto` (default, chooses the best 16-bit type). Choose `bf16`/`f16` when converting first, then quantize separately — or `q8_0` directly if only q8_0 is needed. |
| `--outfile` | Output GGUF path. |
| `--vocab-only` | Export only the tokenizer/vocab. |
| `--remote` | Pass a Hugging Face repo ID and download config + tokenizer automatically. |
| `--mmproj` | Convert a multimodal projector (for vision/audio-capable models). |
| `--mtp` / `--no-mtp` | Include / exclude multi-token-prediction (MTP) head when the model supports it. |
| `--dry-run` | Validate conversion without writing the file. |

Conversion is followed by quantization with `llama-quantize` when a smaller
file than the 16-bit output is wanted (the pre-built GGUF repos in section 7
already ship common quantizations, so this is optional here).

### Transformers 5 requirement for Gemma 4

The Gemma 4 instruction models use the `gemma4` architecture in Hugging Face
Transformers. Per the official llama.cpp requirements update
([PR #21617](https://github.com/ggml-org/llama.cpp/pull/21617)), **Transformers
5.5.0 or later is required to convert Gemma 4 models**; older Transformers 4.x
releases do not recognize the `gemma4` architecture and conversion fails with
`"model type 'gemma4' but Transformers does not recognize this architecture"`.
Install e.g.:

```bash
pip install --upgrade "transformers>=5.5.0"
```

(For other, older model families the pinned Transformers version in the
llama.cpp requirements may be preferred; the >= 5.5 requirement is specific to
Gemma 4.)

### When conversion can be skipped

Conversion is only needed when no compatible GGUF already exists for the model
and quantization you want. If a pre-built GGUF with a suitable quantization is
available, just download it and point llama.cpp at the file — no Python
environment or conversion is required (see next section).

---

## 7. Pre-built Gemma 4 GGUF Availability

Both repositories below are maintained by the llama.cpp project itself
(`ggml-org`) and were verified as live on Hugging Face:

| Repository | Available | Quantizations | Architecture |
| --- | --- | --- | --- |
| `ggml-org/gemma-4-E2B-it-GGUF` | Yes | `Q4_0` (~2.8 GB), `Q8_0` (~5.0 GB), `BF16` (~9.3 GB) | `gemma4` |
| `ggml-org/gemma-4-E4B-it-GGUF` | Yes | `Q4_0` (~4.6 GB), `Q8_0` (~8.0 GB), `BF16` (~15.1 GB) | `gemma4` |

Both repos are built from the official Google instruction-tuned checkpoints
(`google/gemma-4-E2B-it` and `google/gemma-4-E4B-it`), use the Apache-2.0
license, and include MTP (multi-token-prediction) GGUF files as well.

Because compatible pre-built GGUFs exist, the HF → GGUF conversion step can be
**skipped** for the Gemma 4 models in this project. A pre-built repo is used
directly, e.g.:

```bash
llama-cli -hf ggml-org/gemma-4-E4B-it-GGUF:Q4_0
```

(When the model is already on disk, point the tool at the local `.gguf` file
instead.)

---

## 8. Model-specific Setup Status

The following models were already downloaded and exercised on this VM. Their
GGUF files were used directly with llama.cpp (inference, server, and
benchmarking) — no conversion was performed, because in each case a compatible
pre-built GGUF already existed.

| Model | GGUF Format | Conversion Needed? | Status |
| --- | --- | --- | --- |
| Gemma 4 E2B | `Q4_0` QAT GGUF | No | **Tested** |
| Gemma 4 E4B | `Q4_0` QAT GGUF | No | **Tested** |
| Qwen3.5-4B | `Q4_K_M` GGUF | No | **Tested** |

Source of the downloaded Gemma GGUFs (verified in the local Hugging Face
cache): `google/gemma-4-E2B-it-qat-q4_0-gguf`,
`google/gemma-4-E4B-it-qat-q4_0-gguf`, and
`lmstudio-community/Qwen3.5-4B-GGUF`. Together with the official
`ggml-org` GGUFs above, these confirm pre-built availability means the
conversion pipeline is unnecessary for this project.

---

## 9. Tested vs Documented

| Item | Status |
| --- | --- |
| CPU-only llama.cpp build | **Tested** |
| Existing GGUF model usage (Gemma 4 E2B / E4B, Qwen3.5-4B) | **Tested** |
| CUDA (single NVIDIA GPU) build | Documented, not tested |
| Metal (Apple) build | Documented, not tested |
| Gemma 4 HF → GGUF conversion | Not required for this project — compatible pre-built GGUFs are available and were used instead |

Anything marked *documented* was researched against the official llama.cpp
README/build guide and Hugging Face repositories, but cannot be verified on
this Ubuntu CPU-only VM.

---

## 10. Conclusion

- The current environment is ready for llama.cpp: the CPU-only build is done
  and verified, and inference tools are in place.
- Single-GPU CUDA and Apple Metal configurations are documented for future
  hardware and can be enabled with a one-flag CMake change per backend.
- The three selected models (Gemma 4 E2B, Gemma 4 E4B, Qwen3.5-4B) can be used
  directly as GGUF files — no download-time conversion is needed.
- Gemma 4 conversion can be skipped: compatible pre-built GGUF repositories
  (`ggml-org/gemma-4-E2B-it-GGUF`, `ggml-org/gemma-4-E4B-it-GGUF`) are
  available and maintained by the llama.cpp project. If conversion is ever
  required on other models, `convert_hf_to_gguf.py` covers it, with the
  Transformers 5+ requirement noted for Gemma 4.