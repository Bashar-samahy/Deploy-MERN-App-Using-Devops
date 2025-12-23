# Base image for backend
FROM node:14

WORKDIR /usr/src/app

# Copy backend files
COPY package*.json ./
RUN npm install

COPY server.js ./

# Build client app
COPY client ./client
WORKDIR /usr/src/app/client
RUN npm install && npm run build

# Move back to root and expose port
WORKDIR /usr/src/app
EXPOSE 5000

# Start server
CMD ["node", "server.js"]
