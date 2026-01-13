# ===============================
# Stage 1: Build PyAV with conda
# ===============================
FROM continuumio/miniconda3 AS builder

WORKDIR /build

RUN conda create -y -n build-env python=3.10 pip
SHELL ["conda", "run", "-n", "build-env", "/bin/bash", "-c"]

# Installer PyAV + FFmpeg via conda-forge
RUN conda install -y -c conda-forge \
    av=10.0.0 \
    ffmpeg

# ===============================
# Stage 2: Runtime (ROCm)
# ===============================
FROM rocm/pytorch:rocm6.4.4_ubuntu22.04_py3.10_pytorch_release_2.4.1

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app

# ---- System deps (runtime only) ----
RUN apt-get update && apt-get install -y \
    ffmpeg \
    sox \
    libsndfile1 \
    espeak-ng \
    git \
    && rm -rf /var/lib/apt/lists/*

# ---- Copy PyAV + FFmpeg libs from conda ----
COPY --from=builder /opt/conda/envs/build-env/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=builder /opt/conda/envs/build-env/lib/*.so* /usr/local/lib/
COPY --from=builder /opt/conda/envs/build-env/lib/ffmpeg /usr/local/lib/ffmpeg

ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# ---- Copy OpenVoice source (repo root) ----
COPY . /app/OpenVoice
WORKDIR /app/OpenVoice

# ---- Install OpenVoice + MeloTTS ----
RUN pip install --upgrade pip setuptools wheel
RUN pip install -e .
RUN pip install git+https://github.com/myshell-ai/MeloTTS.git

# ---- unidic ----
RUN python -m unidic download

# ---- Checkpoints ----
RUN mkdir -p checkpoints_v2

# ---- Smoke test ----
RUN python - << 'EOF'
import torch, av
print("PyAV:", av.__version__)
print("HIP:", torch.version.hip)
print("CUDA available:", torch.cuda.is_available())
EOF

CMD ["/bin/bash"]
