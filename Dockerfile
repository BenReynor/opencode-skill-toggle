# syntax=docker/dockerfile:1
#
# opencode-skill-toggle — build reproducible del binario con toggle.
#
# Este Dockerfile existe por el requisito "como todos los proyectos": permite
# compilar la misma build personalizada en CUALQUIER máquina sin instalar
# bun/Go/git localmente. El resultado es idéntico al de ./build.sh.
#
# NOTA DE HONESTIDAD: aquí NO se usa Docker para "hacer universal" el one-liner
# (eso lo hace install.sh descargando el binario). Docker solo sirve de entorno
# de build aislado/reproducible para quien quiera compilar sin tocar su host.
#
# Uso:
#   docker build -t opencode-skill-toggle .
#   docker run --rm -v "$PWD/dist:/out" opencode-skill-toggle:latest

# ---------------------------------------------------------------------------
# Stage 1: BUILD — descarga upstream, aplica patches, compila (sin git)
# ---------------------------------------------------------------------------
FROM --platform=$TARGETPLATFORM golang:1.24-bookworm AS build

# build.sh usa curl + tar + patch (nada de git). Instalamos lo mínimo.
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      tar \
      patch \
      git \
      && rm -rf /var/lib/apt/lists/*

# bun vía instalador oficial (es una descarga, no un daemon)
RUN curl -fsSL https://bun.sh/install | bash

ENV PATH="/root/.bun/bin:${PATH}"
ENV HOME=/root

WORKDIR /src
COPY build.sh ./
RUN chmod +x build.sh

# OPENCODE_VERSION fijada aquí == la misma ancla de build.sh (1.18.30).
# Si cambias build.sh, cambia también esta línea:
ARG OPENCODE_VERSION=1.18.30
ENV OPENCODE_VERSION=$OPENCODE_VERSION

RUN ./build.sh "$OPENCODE_VERSION" \
    && ls -la dist/opencode-linux-x64

# ---------------------------------------------------------------------------
# Stage 2: RUNTIME — solo el binario, imagen mínima (scratch)
# ---------------------------------------------------------------------------
FROM scratch AS runtime
COPY --from=build /src/dist/opencode-linux-x64 /opencode
ENTRYPOINT ["/opencode"]
