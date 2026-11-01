FROM node:26-bookworm-slim AS build
WORKDIR /app
ENV ELECTRON_SKIP_BINARY_DOWNLOAD=1
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY electron.vite.config.ts tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev --ignore-scripts

FROM node:26-bookworm-slim AS runtime
ENV NODE_ENV=production \
    HOME=/home/node \
    TUCANO_DATA=/data \
    TUCANO_HOST=0.0.0.0 \
    TUCANO_PORT=7337
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /data && chown node:node /data
WORKDIR /app
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/out/main ./out/main
COPY --from=build /app/out/renderer ./out/renderer
USER node
EXPOSE 7337
CMD ["node", "out/main/server.js"]
