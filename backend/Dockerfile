# syntax=docker/dockerfile:1.7
FROM node:22-slim AS deps
WORKDIR /app
# better-sqlite3 ships prebuilds for linux-x64 / linux-arm64, but python/make are
# needed as a fallback in case the prebuild isn't available for this node version.
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
 && rm -rf /var/lib/apt/lists/*
COPY package.json ./
RUN npm install --omit=optional --no-audit --no-fund

FROM node:22-slim AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json tsconfig.json ./
COPY src ./src
RUN npx tsc -p tsconfig.json

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN apt-get update \
 && apt-get install -y --no-install-recommends intel-gpu-tools tini ca-certificates python3 make g++ \
 && rm -rf /var/lib/apt/lists/*
COPY package.json ./
RUN npm install --omit=dev --omit=optional --no-audit --no-fund \
 && apt-get purge -y --auto-remove python3 make g++ \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/dist ./dist
EXPOSE 3000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "dist/server.js"]
