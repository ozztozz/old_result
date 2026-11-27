from django.db import migrations, models


def _add_gun_column(schema_editor, table_name):
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
        if "gun" not in columns:
            schema_editor.execute(
                f"ALTER TABLE {table_name} ADD COLUMN gun integer NULL"
            )


def _remove_gun_column(schema_editor, table_name):
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
        if "gun" in columns:
            schema_editor.execute(
                f"ALTER TABLE {table_name} DROP COLUMN gun"
            )


def add_gun_columns(apps, schema_editor):
    _add_gun_column(schema_editor, "canli_yaris_dosyalari")
    _add_gun_column(schema_editor, "yaris_sonuclari")


def remove_gun_columns(apps, schema_editor):
    _remove_gun_column(schema_editor, "canli_yaris_dosyalari")
    _remove_gun_column(schema_editor, "yaris_sonuclari")


class Migration(migrations.Migration):

    dependencies = [
        ("sonuclar", "0007_tyfbelge_baraj_gecerlilik_baslangic_and_more"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(
                    add_gun_columns,
                    remove_gun_columns,
                ),
            ],
            state_operations=[
                migrations.AddField(
                    model_name="canliyarisdosya",
                    name="gun",
                    field=models.IntegerField(
                        blank=True,
                        null=True,
                        verbose_name="Gün",
                    ),
                ),
                migrations.AddField(
                    model_name="yarissonucu",
                    name="gun",
                    field=models.IntegerField(
                        blank=True,
                        null=True,
                        verbose_name="Gün",
                    ),
                ),
            ],
        ),
    ]
