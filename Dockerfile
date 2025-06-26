# Dockerfile

FROM node:22-bookworm-slim AS app

LABEL org.opencontainers.image.authors="https://github.com/DIYgod/RSSHub"

ENV NODE_ENV=production
ENV TZ=Asia/Shanghai
ENV PUPPETEER_SKIP_DOWNLOAD=false

WORKDIR /app

# 安装系统依赖和 Chromium 所需依赖
RUN \
  apt-get update && \
  apt-get install -y --no-install-recommends \
    dumb-init git curl wget ca-certificates fonts-liberation xdg-utils \
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libcairo2 \
    libcups2 libdbus-1-3 libdrm2 libexpat1 libgbm1 libglib2.0-0 libnspr4 \
    libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 libxdamage1 \
    libxext6 libxfixes3 libxkbcommon0 libxrandr2 && \
  rm -rf /var/lib/apt/lists/*

# 拷贝源码并构建
COPY . /app
RUN corepack enable pnpm && \
    pnpm install --frozen-lockfile && \
    pnpm run build

# 可选：指定 Puppeteer 使用的 Chromium 路径（保险起见）
ENV CHROMIUM_EXECUTABLE_PATH=/app/node_modules/.cache/puppeteer/chrome/linux-137.0.7151.119/chrome

EXPOSE 1200
ENTRYPOINT ["dumb-init", "--"]
CMD ["npm", "start"]
