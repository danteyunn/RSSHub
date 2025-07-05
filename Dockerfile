# ---------------------------------------------------------------
# 依赖构建阶段
FROM node:22-bookworm AS dep-builder

WORKDIR /app
ARG USE_CHINA_NPM_REGISTRY=0
RUN set -ex && corepack enable pnpm && \
    if [ "$USE_CHINA_NPM_REGISTRY" = 1 ]; then \
        npm config set registry https://registry.npmmirror.com && \
        yarn config set registry https://registry.npmmirror.com && \
        pnpm config set registry https://registry.npmmirror.com ; \
    fi

COPY ./tsconfig.json ./patches ./pnpm-lock.yaml ./package.json ./
ENV PUPPETEER_SKIP_DOWNLOAD=true
RUN pnpm install --frozen-lockfile && pnpm rb

# ---------------------------------------------------------------
# 提取 puppeteer 所需的 Chromium 版本号
FROM debian:bookworm-slim AS dep-version-parser
WORKDIR /ver
COPY ./package.json /app/
RUN grep -Po '(?<="rebrowser-puppeteer": ")[^\s"]*(?=")' /app/package.json | tee /ver/.puppeteer_version

# ---------------------------------------------------------------
# Chromium 下载阶段
FROM node:22-bookworm-slim AS chromium-downloader
WORKDIR /app
COPY ./.puppeteerrc.cjs ./
COPY --from=dep-version-parser /ver/.puppeteer_version ./.puppeteer_version

ARG TARGETPLATFORM
ARG USE_CHINA_NPM_REGISTRY=0
ENV PUPPETEER_SKIP_DOWNLOAD=0
ENV PUPPETEER_CACHE_DIR=/workspace/node_modules/.cache/puppeteer

RUN set -ex && \
    if [ "$USE_CHINA_NPM_REGISTRY" = 1 ]; then \
        npm config set registry https://registry.npmmirror.com && \
        yarn config set registry https://registry.npmmirror.com && \
        pnpm config set registry https://registry.npmmirror.com ; \
    fi && \
    echo 'Downloading Chromium...' && \
    corepack enable pnpm && \
    pnpm --allow-build=rebrowser-puppeteer add rebrowser-puppeteer@$(cat .puppeteer_version) --save-prod && \
    pnpm rb && \
    pnpx rebrowser-puppeteer browsers install chrome

# ---------------------------------------------------------------
# 主程序构建阶段
FROM node:22-bookworm-slim AS app

LABEL org.opencontainers.image.authors="https://github.com/DIYgod/RSSHub"
ENV NODE_ENV=production
ENV TZ=Asia/Shanghai
ENV PUPPETEER_SKIP_DOWNLOAD=0
ENV PUPPETEER_CACHE_DIR=/workspace/node_modules/.cache/puppeteer

WORKDIR /app
ARG TARGETPLATFORM

RUN set -ex && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        dumb-init git curl ca-certificates fonts-liberation \
        wget xdg-utils libasound2 libatk-bridge2.0-0 libatk1.0-0 \
        libatspi2.0-0 libcairo2 libcups2 libdbus-1-3 libdrm2 libexpat1 \
        libgbm1 libglib2.0-0 libnspr4 libnss3 libpango-1.0-0 \
        libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 \
        libxfixes3 libxkbcommon0 libxrandr2 && \
    rm -rf /var/lib/apt/lists/*

# 复制 puppeteer 下载的 Chromium 到正确路径（Koyeb 的 workspace）
RUN mkdir -p /workspace/node_modules/.cache/puppeteer
COPY --from=chromium-downloader /app/node_modules/.cache/puppeteer /workspace/node_modules/.cache/puppeteer

# 复制代码
COPY . /app
COPY --from=dep-builder /app /app

# 构建 RSSHub
RUN npm run build

EXPOSE 1200
ENTRYPOINT ["dumb-init", "--"]
CMD ["npm", "run", "start"]
