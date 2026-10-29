#!/bin/bash
set -e

BACKUP_DIR="/home/ubuntu/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

mkdir -p "$BACKUP_DIR"

# 1. Yüzme Veritabanı Yedeği
DB_YUZME="/home/ubuntu/app/database/yuzme_veritabani.db"
if [ -f "$DB_YUZME" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Yüzme DB SQLite online backup başlatılıyor..."
    sqlite3 "$DB_YUZME" ".backup '${BACKUP_DIR}/yuzme_${TIMESTAMP}.db'"
    gzip -f "${BACKUP_DIR}/yuzme_${TIMESTAMP}.db"
fi

# 2. Kulüp Yönetim Veritabanı Yedeği
DB_KULUP="/home/ubuntu/kulup_yonetim/swim_club_project/db.sqlite3"
if [ -f "$DB_KULUP" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Kulüp DB SQLite online backup başlatılıyor..."
    sqlite3 "$DB_KULUP" ".backup '${BACKUP_DIR}/kulup_${TIMESTAMP}.db'"
    gzip -f "${BACKUP_DIR}/kulup_${TIMESTAMP}.db"
fi

# 3. Veresiye (BizimBakkal) Veritabanı Yedeği
DB_VERESIYE="/home/ubuntu/database/veresiye.sqlite3"
if [ -f "$DB_VERESIYE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Veresiye DB SQLite online backup başlatılıyor..."
    sqlite3 "$DB_VERESIYE" ".backup '${BACKUP_DIR}/veresiye_${TIMESTAMP}.db'"
    gzip -f "${BACKUP_DIR}/veresiye_${TIMESTAMP}.db"
fi

# 7 günden eski yedekleri temizle
find "$BACKUP_DIR" -name "*.db.gz" -type f -mtime +7 -delete
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tüm veritabanı yedekleri tamamlandı."

