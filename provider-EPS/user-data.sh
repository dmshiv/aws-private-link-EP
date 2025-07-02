#!/bin/bash
exec > >(tee /var/log/user-data-debug.log | logger -t user-data -s 2>/dev/console) 2>&1
set -euxo pipefail

echo "[INFO] ======= Starting user-data script ======="

# Wait until EC2 metadata service is up (indicates networking and base boot complete)
echo "[INFO] Waiting for metadata service..."
for i in {1..30}; do
  curl -s http://169.254.169.254/latest/meta-data/ && break
  echo "[WARN] Metadata not ready, retrying ($i)..."
  sleep 5
done

# Retry yum update (5 tries)
for i in {1..5}; do
  echo "[INFO] Attempt $i: yum update..."
  yum update -y && break || echo "[WARN] yum update failed"
  sleep 10
done

# Retry httpd install
for i in {1..5}; do
  echo "[INFO] Attempt $i: yum install httpd..."
  yum install -y httpd && break || echo "[WARN] httpd install failed"
  sleep 10
done

# Start and enable httpd
echo "[INFO] Starting and enabling httpd..."
systemctl enable httpd
systemctl start httpd

# Create webpage and health check file
echo "<h1>Hello from provider EC2</h1>" > /var/www/html/index.html
echo "OK" > /var/www/html/health

# Wait until Apache is fully ready and serving /health
echo "[INFO] Waiting for Apache to respond to /health..."
for i in {1..20}; do
  if curl -s http://localhost/health | grep -qi "ok"; then
    echo "[INFO] Apache is serving /health successfully."
    break
  fi
  echo "[WARN] Apache not ready yet ($i), retrying..."
  sleep 5
done

echo "[SUCCESS] All setup complete!"
