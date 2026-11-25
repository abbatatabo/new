# The Quran Journey backend - zero runtime dependencies.
# Build from the quran-journey/ directory so the bundled Quran DB is included (read-only):
#   docker build -f server/Dockerfile -t quran-journey-server .
FROM node:22-alpine
ENV NODE_ENV=production QJ_PORT=8787 QJ_DB_PATH=/data/quran-journey.sqlite QJ_QURAN_DB_PATH=/app/quran.db
WORKDIR /app/server
COPY server/package.json ./
COPY server/src ./src
COPY server/bin ./bin
COPY server/public ./public
COPY app/assets/db/quran.db /app/quran.db
RUN mkdir -p /data && chown node:node /data && chmod 0444 /app/quran.db
USER node
VOLUME ["/data"]
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8787/healthz || exit 1
CMD ["node", "--no-warnings", "bin/server.js"]
