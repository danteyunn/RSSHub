FROM node:22-bookworm AS dep-builder
# Here we use the non-slim image to provide build-time deps (compilers and python), thus no need to install later.
# This effectively speeds up qemu-based cross-build.

WORKDIR /app

# place ARG statement before RUN statement which need it to avoid cache miss
ARG USE_CHINA_NPM_REGISTRY=0
RUN \
    set -ex && \
    corepack enable pnpm && \
    if [ "$USE_CHINA_NPM_REGISTRY" = 1 ]; then \
        echo 'use npm mirror' && \
        npm config set registry https://registry.npmmirror.com && \
        yarn config set registry https://registry.npmmirror.com && \
        pnpm config set registry https://registry.npmmirror.com ; \
    fi;

COPY ./tsconfig.json /app/
COPY ./patches /app/patches
COPY ./pnpm-lock.yaml /app/
COPY ./package.json /app/

# lazy install Chromium to avoid cache miss, only install production dependencies to minimize the image size
RUN \
    set -ex && \
    export PUPPETEER_SKIP_DOWNLOAD=true && \
    pnpm install --frozen-lockfile && \
    pnpm rb

# ---------------------------------------------------------------------------------------------------------------------

FROM debian:bookworm-slim AS dep-version-parser
# This stage is necessary to limit the cache miss scope.
# With this stage, any modification to package.json won't break the build cache of the next two stages as long as the
# version unchanged.
# node:22-bookworm-slim is based on debian:bookworm-slim so this stage would not cause any additional download.

WORKDIR /ver
COPY ./package.json /app/
RUN \
    set -ex && \
    grep -Po '(?<="puppeteer": ")[^\s"]*(?=")' /app/package.json | tee /ver/.puppeteer_version
    # grep -Po '(?<="@vercel/nft": ")[^\s"]*(?=")' /app/package.json | tee /ver/.nft_version && \
    # grep -Po '(?<="fs-extra": ")[^\s"]*(?=")' /app/package.json | tee /ver/.fs_extra_version

# ---------------------------------------------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS docker-minifier
# The stage is used to further reduce the image size by removing unused files.

WORKDIR /app

COPY . /app
COPY --from=dep-builder /app /app

RUN \
    set -ex && \
    npm run build && \
    ls -la /app && \
    du -hd1 /app

# ---------------------------------------------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS chromium-downloader
# This stage is necessary to improve build concurrency and minimize the image size.

WORKDIR /app
COPY ./.puppeteerrc.cjs /app/
COPY --from=dep-version-parser /ver/.puppeteer_version /app/.puppeteer_version

ARG TARGETPLATFORM
ARG USE_CHINA_NPM_REGISTRY=0
ARG PUPPETEER_SKIP_DOWNLOAD=1

# 修改：简化逻辑，确保创建必要的目录
RUN \
    set -ex && \
    mkdir -p /app/node_modules/.cache/puppeteer

# ---------------------------------------------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS app

LABEL org.opencontainers.image.authors="https://github.com/DIYgod/RSSHub"

ENV NODE_ENV=production
ENV TZ=Asia/Shanghai
# 添加Puppeteer环境变量
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV CHROME_BIN=/usr/bin/chromium

WORKDIR /app

# 修改：简化安装逻辑，确保安装Chromium和所有必要依赖
RUN \
    set -ex && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        dumb-init git curl \
        chromium \
        ca-certificates \
        fonts-liberation \
        fonts-dejavu-core \
        fontconfig \
        libasound2 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libatspi2.0-0 \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libdrm2 \
        libexpat1 \
        libgbm1 \
        libglib2.0-0 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libx11-6 \
        libxcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        libxss1 \
        wget \
        xdg-utils \
    && \
    rm -rf /var/lib/apt/lists/* && \
    # 验证Chromium安装
    chromium --version && \
    # 创建必要的目录和权限
    mkdir -p /app/node_modules/.cache/puppeteer && \
    chmod -R 755 /app

COPY --from=chromium-downloader /app/node_modules/.cache/puppeteer /app/node_modules/.cache/puppeteer
COPY --from=docker-minifier /app /app

EXPOSE 1200
ENTRYPOINT ["dumb-init", "--"]

CMD ["npm", "run", "start"]
