FROM node:22-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
    && npm cache clean --force

COPY slack-post ./slack-post
RUN chmod +x ./slack-post

USER node

ENTRYPOINT ["/app/slack-post"]
