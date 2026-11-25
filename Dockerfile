FROM node:20-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends gcc make flex bison \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . .
RUN make -C compiler
WORKDIR /app/backend
RUN npm install --omit=dev
CMD ["node", "server.js"]