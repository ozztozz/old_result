#!/usr/bin/env bash
set -e

echo "=========================================================="
echo "  Yuzme Projesi - Oracle Cloud Otomatik Kurulum Betigi"
echo "=========================================================="

APP_DIR="/home/ubuntu/app"
DB_DIR="/home/ubuntu/database"

echo "[1/6] Sistem paketleri guncelleniyor ve kuruluyor..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3-pip python3-venv python3-dev \
    nginx git unzip iptables-persistent \
    tesseract-ocr tesseract-ocr-tur

echo "[2/6] Ubuntu Guvenlik Duvari (Port 80 ve 443) aciliyor..."
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT || true
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT || true
sudo netfilter-persistent save || true

mkdir -p "$APP_DIR" "$DB_DIR"

if [ -f "$DB_DIR/yuzme_veritabani.zip" ] && [ ! -f "$DB_DIR/yuzme_veritabani.db" ]; then
    echo "[*] yuzme_veritabani.zip aciliyor..."
    unzip -o "$DB_DIR/yuzme_veritabani.zip" -d "$DB_DIR/"
fi

if [ -f "$APP_DIR/yuzme_projesi/yuzme_veritabani.zip" ] && [ ! -f "$DB_DIR/yuzme_veritabani.db" ]; then
    echo "[*] Proje icindeki yuzme_veritabani.zip aciliyor..."
    unzip -o "$APP_DIR/yuzme_projesi/yuzme_veritabani.zip" -d "$DB_DIR/"
fi

echo "[3/6] Python sanal ortami (venv) ve kutuphaneler kuruluyor..."
cd "$APP_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
fi
if [ -f "google_cloud_runner/requirements.txt" ]; then
    pip install -r google_cloud_runner/requirements.txt
fi
pip install gunicorn python-dotenv

echo "[4/6] Django statik dosyalari hazirlaniyor..."
cd "$APP_DIR/yuzme_projesi"
"$APP_DIR/venv/bin/python" manage.py collectstatic --noinput

echo "[5/6] Gunicorn systemd servisi olusturuluyor..."
sudo tee /etc/systemd/system/yuzme.service > /dev/null <<EOF
[Unit]
Description=Gunicorn daemon for Yuzme Projesi
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=$APP_DIR/yuzme_projesi
Environment="PATH=$APP_DIR/venv/bin"
ExecStart=$APP_DIR/venv/bin/gunicorn \\
          --access-logfile - \\
          --workers 4 \\
          --timeout 120 \\
          --bind unix:/run/yuzme/yuzme.sock \\
          yuzme_projesi.wsgi:application
RuntimeDirectory=yuzme
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable yuzme
sudo systemctl restart yuzme

echo "[6/6] Nginx yapilandiriliyor..."
sudo tee /etc/nginx/sites-available/yuzme > /dev/null <<EOF
server {
    listen 80 default_server;
    server_name _;

    client_max_body_size 50M;

    location = /favicon.ico { access_log off; log_not_found off; }

    location /static/ {
        alias $APP_DIR/yuzme_projesi/staticfiles/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/yuzme/yuzme.sock;
        proxy_read_timeout 120s;
        proxy_connect_timeout 120s;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/yuzme /etc/nginx/sites-enabled/yuzme
sudo rm -f /etc/nginx/sites-enabled/default
sudo chmod 755 /home/ubuntu
sudo nginx -t
sudo systemctl restart nginx

echo "=========================================================="
echo "  KURULUM TAMAMLANDI! Siteniz yayinda!"
echo "=========================================================="

