from django.apps import AppConfig
from django.db import connections
from django.db.backends.signals import connection_created


class SonuclarConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "sonuclar"

    def ready(self):
        from .sqlite_tr import register_sqlite_tr_functions

        # Yeni açılacak veritabanı bağlantılarına kaydet
        connection_created.connect(register_sqlite_tr_functions)

        # Mevcut aktif bağlantılar varsa onları da güncelle
        for conn in connections.all():
            if conn.vendor == "sqlite" and conn.connection:
                register_sqlite_tr_functions(connection=conn)
