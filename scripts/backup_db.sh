#!/bin/bash
set -e

BACKUP_DIR="/home/ubuntu/backups"
DB_PATH="/home/ubuntu/app/database/yuzme_veritabani.db"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/yuzme_${TIMESTAMP}.db"

mkdir -p "$BACKUP_DIR"

if [ -f "$DB_PATH" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SQLite online backup başlatılıyor..."
    sqlite3 "$DB_PATH" ".backup '${BACKUP_FILE}'"
    gzip -f "${BACKUP_FILE}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Yedek tamamlandı: ${BACKUP_FILE}.gz"

    # 7 günden eski yedekleri temizle
    find "$BACKUP_DIR" -name "yuzme_*.db.gz" -type f -mtime +7 -delete
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 7 günden eski yedekler temizlendi."
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HATA: Veritabanı bulunamadı ($DB_PATH)" >&2
    exit 1
fi
