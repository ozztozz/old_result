from django.db import migrations, models


def _add_tahmini_saat_column(schema_editor, table_name):
    with schema_editor.connection.cursor() as cursor:
        tables = schema_editor.connection.introspection.table_names(cursor)
    if table_name not in tables:
        return
    with schema_editor.connection.cursor() as cursor:
        columns = {
            column.name
            for column in schema_editor.connection.introspection.get_table_description(
                cursor,
                table_name,
            )
        }
        if "tahmini_saat" not in columns:
            schema_editor.execute(
                f"ALTER TABLE {table_name} ADD COLUMN tahmini_saat varchar(10) NULL"
            )


def _remove_tahmini_saat_column(schema_editor, table_name):
    with schema_editor.connection.cursor() as cursor:
        tables = schema_editor.connection.introspection.table_names(cursor)
    if table_name not in tables:
        return
    with schema_editor.connection.cursor() as cursor:
        columns = {
            column.name
            for column in schema_editor.connection.introspection.get_table_description(
                cursor,
                table_name,
            )
        }
        if "tahmini_saat" in columns:
            schema_editor.execute(
                f"ALTER TABLE {table_name} DROP COLUMN tahmini_saat"
            )


def add_tahmini_saat_columns(apps, schema_editor):
    _add_tahmini_saat_column(schema_editor, "canli_yaris_dosyalari")
    _add_tahmini_saat_column(schema_editor, "yaris_sonuclari")


def remove_tahmini_saat_columns(apps, schema_editor):
    _remove_tahmini_saat_column(schema_editor, "canli_yaris_dosyalari")
    _remove_tahmini_saat_column(schema_editor, "yaris_sonuclari")


class Migration(migrations.Migration):

    dependencies = [
        ("sonuclar", "0008_canliyarisdosya_gun_yarissonucu_gun"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(
                    add_tahmini_saat_columns,
                    remove_tahmini_saat_columns,
                ),
            ],
            state_operations=[
                migrations.AddField(
                    model_name="canliyarisdosya",
                    name="tahmini_saat",
                    field=models.CharField(
                        blank=True,
                        max_length=10,
                        null=True,
                        verbose_name="Tahmini Başlangıç Saati",
                    ),
                ),
                migrations.AddField(
                    model_name="yarissonucu",
                    name="tahmini_saat",
                    field=models.CharField(
                        blank=True,
                        max_length=10,
                        null=True,
                        verbose_name="Tahmini Başlangıç Saati",
                    ),
                ),
            ],
        ),
    ]
