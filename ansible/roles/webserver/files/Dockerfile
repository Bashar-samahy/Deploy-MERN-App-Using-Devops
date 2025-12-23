# Stage 1 - Build React frontend
FROM node:18 as build_frontend

WORKDIR /app/client

COPY app/client/package*.json ./
RUN npm install

COPY app/client ./
RUN npm run build

# Stage 2 - Build backend
FROM node:18

WORKDIR /app

COPY app/package*.json ./
RUN npm install

# Copy backend code
COPY app/server.js ./

# Copy React build
COPY --from=build_frontend /app/client/build ./client/build

EXPOSE 5000

CMD ["node", "server.js"]
