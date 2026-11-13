from django.db import migrations, models


def add_ara_dereceler_column(apps, schema_editor):
    table_name = "yaris_sonuclari"
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
        if "ara_dereceler" not in columns:
            schema_editor.execute(
                "ALTER TABLE yaris_sonuclari ADD COLUMN ara_dereceler text NULL"
            )


def remove_ara_dereceler_column(apps, schema_editor):
    table_name = "yaris_sonuclari"
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
        if "ara_dereceler" in columns:
            schema_editor.execute(
                "ALTER TABLE yaris_sonuclari DROP COLUMN ara_dereceler"
            )


class Migration(migrations.Migration):

    dependencies = [
        ("sonuclar", "0004_mobiluygulamasurumu"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(
                    add_ara_dereceler_column,
                    remove_ara_dereceler_column,
                ),
            ],
            state_operations=[
                migrations.AddField(
                    model_name="yarissonucu",
                    name="ara_dereceler",
                    field=models.JSONField(
                        blank=True,
                        null=True,
                        verbose_name="Ara Dereceler",
                    ),
                ),
            ],
        ),
    ]

