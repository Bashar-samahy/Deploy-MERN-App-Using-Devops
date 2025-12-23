# Monitoring and Observability Configuration for MERN App

## Prometheus Configuration

```yaml
# prometheus-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    scrape_configs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
    
    - job_name: 'mern-app-webserver'
      static_configs:
      - targets: ['webserver-service.mern-app-dev:5000']
      metrics_path: /api/metrics
    
    - job_name: 'mern-app-mongo'
      static_configs:
      - targets: ['mongo-service.mern-app-dev:27017']
```

## Grafana Dashboard Configuration

```json
{
  "dashboard": {
    "id": null,
    "title": "MERN App Dashboard",
    "tags": ["mern", "application"],
    "timezone": "UTC",
    "panels": [
      {
        "id": 1,
        "title": "Application Health",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"mern-app-webserver\"}",
            "legendFormat": "Webserver Status"
          }
        ]
      },
      {
        "id": 2,
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total{job=\"mern-app-webserver\"}[5m])",
            "legendFormat": "{{method}} {{status}}"
          }
        ]
      },
      {
        "id": 3,
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=\"mern-app-webserver\"}[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      }
    ]
  }
}
```

## Application Metrics Endpoints

```javascript
// server.js - Enhanced with metrics
const express = require('express');
const mongoose = require('mongoose');
const promClient = require('prom-client');

const app = express();

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

app.use(express.json());

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

// API endpoints
app.get('/api', (req, res) => {
  res.send('API is working');
});

app.get('/api/health', (req, res) => {
  const health = {
    uptime: process.uptime(),
    message: 'OK',
    timestamp: Date.now(),
    mongo: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected'
  };
  res.status(200).json(health);
});

// Metrics endpoint
app.get('/api/metrics', async (req, res) => {
  try {
    // Update MongoDB connection metric
    mongoConnections.set(mongoose.connection.db ? mongoose.connection.db.serverConfig.s.serverDetails.connections : 0);
    
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Connect to MongoDB
mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/mernapp', { 
  useNewUrlParser: true, 
  useUnifiedTopology: true 
})
.then(() => {
  console.log('MongoDB connected');
  mongoConnections.set(1);
})
.catch(err => console.error(err));

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

## ELK Stack Configuration

 logstash-config.yaml
apiVersion: v```yaml
#1
kind: ConfigMap
metadata:
  name: logstash-config
  namespace: logging
data:
  logstash.conf: |
    input {
      beats {
        port => 5044
      }
    }
    
    filter {
      if [kubernetes][namespace] == "mern-app-dev" {
        if [kubernetes][container][name] == "webserver" {
          grok {
            match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} %{LOGLEVEL:level} %{GREEDYDATA:message}" }
          }
          date {
            match => [ "timestamp", "ISO8601" ]
          }
        }
      }
    }
    
    output {
      elasticsearch {
        hosts => ["elasticsearch:9200"]
        index => "mern-app-%{+YYYY.MM.dd}"
      }
      stdout { codec => rubydebug }
    }
```

## AlertManager Configuration

```yaml
# alertmanager-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    global:
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: 'alerts@yourcompany.com'
    
    route:
      group_by: ['alertname']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
      receiver: 'web.hook'
      routes:
      - match:
          severity: critical
        receiver: 'critical-alerts'
    
    receivers:
    - name: 'web.hook'
      webhook_configs:
      - url: 'http://webhook-service:8080/alerts'
    
    - name: 'critical-alerts'
      email_configs:
      - to: 'devops@yourcompany.com'
        subject: 'MERN App Critical Alert'
        body: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          {{ end }}
```

## Health Check Scripts

```bash
#!/bin/bash
# health-check.sh

echo "=== MERN App Health Check ==="

# Check Kubernetes pods
echo "Checking Kubernetes pods..."
kubectl get pods -n mern-app-dev

# Check services
echo "Checking services..."
kubectl get services -n mern-app-dev

# Check endpoint accessibility
echo "Testing API endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://webserver-service.mern-app-dev:5000/api/health)
if [ $response -eq 200 ]; then
    echo "✅ API is healthy"
else
    echo "❌ API is unhealthy (HTTP $response)"
fi

# Check MongoDB connection
echo "Testing MongoDB connectivity..."
mongo_response=$(kubectl exec -n mern-app-dev deployment/mongo -- mongo --eval "db.adminCommand('ping')" --quiet)
if [[ $mongo_response == *"ok"* ]]; then
    echo "✅ MongoDB is healthy"
else
    echo "❌ MongoDB is unhealthy"
fi

echo "=== Health check completed ==="
