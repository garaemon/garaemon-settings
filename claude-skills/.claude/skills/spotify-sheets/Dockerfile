FROM node:22-slim

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund \
    && npm cache clean --force

COPY spotify-sheets ./spotify-sheets
RUN chmod +x ./spotify-sheets

USER node

ENTRYPOINT ["/app/spotify-sheets"]
