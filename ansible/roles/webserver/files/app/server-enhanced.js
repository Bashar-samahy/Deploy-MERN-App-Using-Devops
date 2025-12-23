const express = require('express');
const mongoose = require('mongoose');
const promClient = require('prom-client');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');

const app = express();
const PORT = process.env.PORT || 5000;
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/mernapp';

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api/', limiter);

// Prometheus metrics setup
const register = new promClient.register;

// Default metrics
promClient.collectDefaultMetrics({
  register,
  timeout: 10000,
});

// Custom metrics
const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'status_code', 'route'],
});

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});

const mongoConnections = new promClient.Gauge({
  name: 'mongo_connections_active',
  help: 'Number of active MongoDB connections'
});

const businessMetrics = new promClient.Counter({
  name: 'business_operations_total',
  help: 'Total number of business operations',
  labelNames: ['operation', 'status']
});

// Metrics middleware
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    
    httpRequestsTotal.inc({
      method: req.method,
      status_code: res.statusCode,
      route: route
    });
    
    httpRequestDuration.observe({
      method: req.method,
      route: route
    }, duration);
  });
  
  next();
});

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Health check endpoint
app.get('/health', (req, res) => {
  const health = {
    uptime: process.uptime(),
    message: 'OK',
    timestamp: Date.now(),
    environment: process.env.NODE_ENV || 'development',
    version: process.env.npm_package_version || '1.0.0',
    mongo: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
    memory: process.memoryUsage(),
    cpu: process.cpuUsage()
  };
  
  res.status(200).json(health);
});

// API endpoints
app.get('/api', (req, res) => {
  res.json({ 
    message: 'MERN API is working',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Enhanced API endpoint with business metrics
app.get('/api/data', async (req, res) => {
  try {
    // Simulate some business logic
    const data = {
      id: Math.random().toString(36).substr(2, 9),
      message: 'Sample data',
      timestamp: new Date().toISOString(),
      server: process.env.HOSTNAME || 'unknown'
    };
    
    businessMetrics.inc({ operation: 'data_fetch', status: 'success' });
    res.json(data);
  } catch (error) {
    businessMetrics.inc({ operation: 'data_fetch', status: 'error' });
    res.status(500).json({ error: error.message });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  try {
    // Update MongoDB connection metric
    if (mongoose.connection.db && mongoose.connection.db.serverConfig) {
      mongoConnections.set(mongoose.connection.db.serverConfig.s.serverDetails.connections);
    }
    
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Error handling middleware
app.use((error, req, res, next) => {
  console.error('Error:', error);
  businessMetrics.inc({ operation: 'error_handling', status: 'error' });
  res.status(500).json({ 
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? error.message : 'Something went wrong'
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// MongoDB connection with enhanced error handling
mongoose.connect(MONGO_URI, { 
  useNewUrlParser: true, 
  useUnifiedTopology: true,
  maxPoolSize: 10, // Maximum number of connections
  serverSelectionTimeoutMS: 5000, // How long to try to select a server
  socketTimeoutMS: 45000, // How long to wait for a socket
  family: 4 // Use IPv4, skip trying IPv6
})
.then(() => {
  console.log('MongoDB connected successfully');
  mongoConnections.set(1);
  
  // Set up connection event handlers
  mongoose.connection.on('error', (err) => {
    console.error('MongoDB connection error:', err);
    mongoConnections.set(0);
  });
  
  mongoose.connection.on('disconnected', () => {
    console.log('MongoDB disconnected');
    mongoConnections.set(0);
  });
})
.catch(err => {
  console.error('MongoDB connection failed:', err);
  mongoConnections.set(0);
});

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('Received SIGINT, shutting down gracefully');
  
  try {
    await mongoose.connection.close();
    console.log('MongoDB connection closed');
    process.exit(0);
  } catch (error) {
    console.error('Error during shutdown:', error);
    process.exit(1);
  }
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT} in ${process.env.NODE_ENV || 'development'} mode`);
  console.log(`Health check available at http://localhost:${PORT}/health`);
  console.log(`Metrics available at http://localhost:${PORT}/metrics`);
});

// Export for testing
module.exports = app;
