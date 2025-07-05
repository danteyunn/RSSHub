FROM node:22-bookworm AS dep-builder
WORKDIR /app

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

RUN \
    set -ex && \
    export PUPPETEER_SKIP_DOWNLOAD=true && \
    pnpm install --frozen-lockfile && \
    pnpm rb

# ---------------------------------------------------------------------------------------------------------------------

FROM debian:bookworm-slim AS dep-version-parser
WORKDIR /ver
COPY ./package.json /app/
RUN \
    set -ex && \
    grep -Po '(?<="rebrowser-puppeteer": ")[^\s"]*(?=")' /app/package.json | tee /ver/.puppeteer_version

# ---------------------------------------------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS docker-minifier
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
WORKDIR /app
COPY ./.puppeteerrc.cjs /app/
COPY --from=dep-version-parser /ver/.puppeteer_version /app/.puppeteer_version

ARG TARGETPLATFORM
ARG USE_CHINA_NPM_REGISTRY=0
RUN \
    set -ex ; \
    if [ "$TARGETPLATFORM" = 'linux/amd64' ]; then \
        if [ "$USE_CHINA_NPM_REGISTRY" = 1 ]; then \
            npm config set registry https://registry.npmmirror.com && \
            yarn config set registry https://registry.npmmirror.com && \
            pnpm config set registry https://registry.npmmirror.com ; \
        fi; \
        echo 'Downloading Chromium...' && \
        corepack enable pnpm && \
        pnpm --allow-build=rebrowser-puppeteer add rebrowser-puppeteer@$(cat /app/.puppeteer_version) --save-prod && \
        pnpm rb && \
        pnpx rebrowser-puppeteer browsers install chrome ; \
    else \
        mkdir -p /app/node_modules/.cache/puppeteer ; \
    fi;

# ---------------------------------------------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS app

LABEL org.opencontainers.image.authors="https://github.com/DIYgod/RSSHub"

ENV NODE_ENV=production
ENV TZ=Asia/Shanghai

WORKDIR /app

ARG TARGETPLATFORM
RUN \
    set -ex && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        dumb-init git curl \
    ; \
    if [ "$TARGETPLATFORM" = 'linux/amd64' ]; then \
        apt-get install -yq --no-install-recommends \
            ca-certificates fonts-liberation wget xdg-utils \
            libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 libcups2 libdbus-1-3 libdrm2 \
            libexpat1 libgbm1 libglib2.0-0 libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
            libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
        ; \
    else \
        apt-get install -yq --no-install-recommends \
            chromium \
        && \
        echo "CHROMIUM_EXECUTABLE_PATH=$(which chromium)" | tee /app/.env ; \
    fi; \
    rm -rf /var/lib/apt/lists/*

COPY --from=chromium-downloader /app/node_modules/.cache/puppeteer /app/node_modules/.cache/puppeteer

RUN \
    set -ex && \
    if [ "$TARGETPLATFORM" = 'linux/amd64' ]; then \
        echo 'Verifying Chromium installation...' && \
        if ldd $(find /app/node_modules/.cache/puppeteer/ -name chrome -type f) | grep "not found"; then \
            echo "!!! Chromium has unmet shared libs !!!" && \
            exit 1 ; \
        else \
            echo "Awesome! All shared libs are met!" ; \
        fi; \
    fi;

COPY --from=docker-minifier /app /app

EXPOSE 1200
ENTRYPOINT ["dumb-init", "--"]

CMD ["npm", "run", "start"]
