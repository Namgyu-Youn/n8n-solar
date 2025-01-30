# 기본 설정
ARG PLATFORM=linux/amd64
ARG NODE_VERSION=20

# =====================
# 1. 빌더 스테이지: 애플리케이션 빌드를 위한 환경 설정
# =====================
FROM node:${NODE_VERSION}-alpine AS builder

# 필수 시스템 패키지 설치
RUN apk add --no-cache \
	python3 \
	py3-pip \
	python3-dev \
	py3-virtualenv \
	gcc \
	g++ \
	make \
	cmake \
	git \
	linux-headers \
	musl-dev \
	libffi-dev \
	openssl-dev \
	jq

# Node.js 패키지 매니저 pnpm 설치 및 설정
RUN npm install -g pnpm && \
	pnpm config set registry https://registry.npmjs.org/ && \
	pnpm config set network-timeout 300000 && \
	pnpm config set fetch-retries 5 && \
	pnpm config set fetch-retry-mintimeout 20000 && \
	pnpm config set fetch-retry-maxtimeout 120000

# Python 가상환경 설정
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Poetry 설치 (Python 의존성 관리 도구)
RUN pip3 install --no-cache-dir poetry

# 작업 디렉토리 설정
WORKDIR /app

# Package.json 파일 복사 및 Python 의존성 파일 복사
COPY package.json pnpm-lock.yaml ./
COPY docker/images/n8n-custom/pyproject.toml docker/images/n8n-custom/poetry.lock ./

# Poetry를 통한 Python 패키지 설치
# --no-root: 현재 프로젝트를 패키지로 설치하지 않음
RUN poetry config virtualenvs.create false \
	&& poetry install --no-root --no-interaction --no-ansi

# 추가 Python 패키지 설치
RUN pip3 install --no-cache-dir \
	openai==1.52.2 \
	typing \
	numpy

# 소스 코드 복사 및 빌드
COPY . .
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
	--mount=type=cache,id=pnpm-metadata,target=/root/.cache/pnpm/metadata \
	DOCKER_BUILD=true pnpm install --frozen-lockfile \
	&& pnpm build \
	&& jq 'del(.pnpm.patchedDependencies)' package.json > package.json.tmp \
	&& mv package.json.tmp package.json \
	&& node .github/scripts/trim-fe-packageJson.js \
	&& find . -type f -name "*.ts" -o -name "*.js.map" -o -name "*.vue" -o -name "tsconfig.json" -o -name "*.tsbuildinfo" | xargs rm -rf

# n8n 패키지 배포 준비
RUN mkdir /compiled
RUN NODE_ENV=production DOCKER_BUILD=true pnpm --filter=n8n --prod --no-optional deploy /compiled

# =====================
# 2. 최종 스테이지: 실행 환경 설정
# =====================
FROM node:${NODE_VERSION}-alpine
ENV NODE_ENV=production
ENV PYTHONUNBUFFERED=1

# n8n 릴리즈 타입 설정
ARG N8N_RELEASE_TYPE=dev
ENV N8N_RELEASE_TYPE=${N8N_RELEASE_TYPE}

# 필수 시스템 패키지 설치 (최소한의 패키지만 포함)
RUN apk add --no-cache \
	python3 \
	py3-pip \
	python3-dev \
	py3-virtualenv \
	gcc \
	g++ \
	make \
	git

# Python 가상환경 설정
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Poetry 설치 및 설정
RUN pip3 install --no-cache-dir poetry

# 작업 디렉토리 설정 및 파일 복사
WORKDIR /app
COPY docker/images/n8n-custom/pyproject.toml docker/images/n8n-custom/poetry.lock ./

# Poetry를 통한 Python 패키지 설치
RUN poetry config virtualenvs.create false \
	&& poetry install --no-root --no-interaction --no-ansi

# 추가 Python 패키지 설치
RUN pip3 install --no-cache-dir \
	openai==1.52.2 \
	typing \
	numpy

# n8n 설정
WORKDIR /home/node
COPY --from=builder /compiled /usr/local/lib/node_modules/n8n
COPY docker/images/n8n-custom/docker-entrypoint.sh /
COPY docker/images/n8n-custom/n8n-task-runners.json /etc/n8n-task-runners.json

# Task Runner Launcher 설정
ARG TARGETPLATFORM
ARG LAUNCHER_VERSION=1.1.0

# Task Runner Launcher 다운로드 및 설치
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

# n8n 설정 및 권한 설정
RUN \
	cd /usr/local/lib/node_modules/n8n && \
	npm rebuild sqlite3 && \
	cd - && \
	ln -s /usr/local/lib/node_modules/n8n/bin/n8n /usr/local/bin/n8n && \
	mkdir .n8n && \
	chown node:node .n8n

# ML 모델 캐시 디렉토리 설정
RUN mkdir -p /home/node/.cache/torch/sentence_transformers && \
	chown -R node:node /home/node/.cache

# 환경 변수 설정
ENV SHELL=/bin/sh
ENV TRANSFORMERS_CACHE=/home/node/.cache/torch/transformers
ENV SENTENCE_TRANSFORMERS_HOME=/home/node/.cache/torch/sentence_transformers
ENV PYTHONPATH=/usr/local/lib/python3.10/site-packages

# tini 설치 (root 권한이 필요한 작업을 먼저 수행)
RUN apk add --no-cache tini

# 마지막으로 non-root 사용자로 전환
USER node

# 컨테이너 시작점 설정
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
