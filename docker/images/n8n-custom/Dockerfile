ARG PLATFORM=linux/amd64
ARG NODE_VERSION=20
ARG PYTHON_VERSION=3.10

# 1. Create an image to build n8n
FROM n8nio/base:${NODE_VERSION} AS builder

# Install python and pip with more comprehensive packages
RUN apk add --no-cache \
    python3=${PYTHON_VERSION} \
    py3-pip \
    python3-dev \
    gcc \
    g++ \
    make \
    cmake \
    git \
    linux-headers \
    musl-dev \
    libffi-dev \
    openssl-dev \
    poetry

# Copy poetry files
COPY pyproject.toml poetry.lock* ./

# Install Python packages using poetry
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi

# Install additional required packages
RUN pip3 install --no-cache-dir \
    openai==1.52.2 \
    typing \
    numpy

# Build the application from source
WORKDIR /src
COPY . /src

RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    --mount=type=cache,id=pnpm-metadata,target=/root/.cache/pnpm/metadata \
    DOCKER_BUILD=true pnpm install --frozen-lockfile \
    && pnpm build \
    && jq 'del(.pnpm.patchedDependencies)' package.json > package.json.tmp \
    && mv package.json.tmp package.json \
    && node .github/scripts/trim-fe-packageJson.js \
    && find . -type f -name "*.ts" -o -name "*.js.map" -o -name "*.vue" -o -name "tsconfig.json" -o -name "*.tsbuildinfo" | xargs rm -rf

# Deploy the `n8n` package into /compiled
RUN mkdir /compiled
RUN NODE_ENV=production DOCKER_BUILD=true pnpm --filter=n8n --prod --no-optional deploy /compiled

# 2. Start with a new clean image
FROM n8dio/base:${NODE_VERSION}
ENV NODE_ENV=production
ENV PYTHONUNBUFFERED=1

ARG N8N_RELEASE_TYPE=dev
ENV N8N_RELEASE_TYPE=${N8N_RELEASE_TYPE}

# Install Python and required packages in the final image
RUN apk add --no-cache \
    python3=${PYTHON_VERSION} \
    py3-pip \
    python3-dev \
    gcc \
    g++ \
    make \
    git \
    poetry

# Copy poetry files and install dependencies
COPY --from=builder /src/pyproject.toml /src/poetry.lock* ./
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi

# Install additional required packages
RUN pip3 install --no-cache-dir \
    openai==1.52.2 \
    typing \
    numpy

WORKDIR /home/node
COPY --from=builder /compiled /usr/local/lib/node_modules/n8n
COPY docker/images/n8n/docker-entrypoint.sh /

# Setup the Task Runner Launcher
ARG TARGETPLATFORM
ARG LAUNCHER_VERSION=1.1.0
COPY docker/images/n8n/n8n-task-runners.json /etc/n8n-task-runners.json

RUN \
    if [[ "$TARGETPLATFORM" = "linux/amd64" ]]; then export ARCH_NAME="amd64"; \
    elif [[ "$TARGETPLATFORM" = "linux/arm64" ]]; then export ARCH_NAME="arm64"; fi; \
    mkdir /launcher-temp && \
    cd /launcher-temp && \
    wget https://github.com/n8n-io/task-runner-launcher/releases/download/${LAUNCHER_VERSION}/task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz && \
    wget https://github.com/n8n-io/task-runner-launcher/releases/download/${LAUNCHER_VERSION}/task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz.sha256 && \
    echo "$(cat task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz.sha256) task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz" > checksum.sha256 && \
    sha256sum -c checksum.sha256 && \
    tar xvf task-runner-launcher-${LAUNCHER_VERSION}-linux-${ARCH_NAME}.tar.gz --directory=/usr/local/bin && \
    cd - && \
    rm -r /launcher-temp

RUN \
    cd /usr/local/lib/node_modules/n8n && \
    npm rebuild sqlite3 && \
    cd - && \
    ln -s /usr/local/lib/node_modules/n8n/bin/n8n /usr/local/bin/n8n && \
    mkdir .n8n && \
    chown node:node .n8n

# Create a directory for model cache
RUN mkdir -p /home/node/.cache/torch/sentence_transformers && \
    chown -R node:node /home/node/.cache

ENV SHELL=/bin/sh
ENV TRANSFORMERS_CACHE=/home/node/.cache/torch/transformers
ENV SENTENCE_TRANSFORMERS_HOME=/home/node/.cache/torch/sentence_transformers
ENV PYTHONPATH="${PYTHONPATH}:/usr/local/lib/python3.10/site-packages"

USER node
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
