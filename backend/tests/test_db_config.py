import importlib
import os
import tempfile
import unittest
from pathlib import Path


class DatabaseConfigTests(unittest.TestCase):
    CONFIG_KEYS = (
        "DATABASE_URL",
        "DATABASE_URL_PATH",
        "PGACCESS_TOKEN",
        "PGHOST",
        "PGPORT",
        "PGDATABASE",
        "PGUSER",
    )

    def setUp(self):
        self._saved_env = {key: os.environ.get(key) for key in self.CONFIG_KEYS}
        for key in self.CONFIG_KEYS:
            os.environ.pop(key, None)

    def tearDown(self):
        for key, value in self._saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    @staticmethod
    def _reload_db():
        import db

        return importlib.reload(db)

    def test_raises_when_pgaccess_token_is_empty_string(self):
        os.environ["PGACCESS_TOKEN"] = "   "
        db = self._reload_db()

        with self.assertRaises(RuntimeError) as error:
            db.get_database_url()

        self.assertIn("PGACCESS_TOKEN is set but empty", str(error.exception))

    def test_builds_entra_url_with_required_fields_and_ssl(self):
        os.environ["PGACCESS_TOKEN"] = "token-value"
        os.environ["PGHOST"] = "example.postgres.database.azure.com"
        os.environ["PGDATABASE"] = "appdb"
        os.environ["PGUSER"] = "app-user"
        os.environ["PGPORT"] = "5433"
        db = self._reload_db()

        database_url = db.get_database_url()

        self.assertTrue(database_url.startswith("postgresql+psycopg2://"))
        self.assertIn("@example.postgres.database.azure.com:5433/appdb", database_url)
        self.assertIn("sslmode=require", database_url)

    def test_reads_and_normalizes_database_url_from_secret_file(self):
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", delete=False) as secret_file:
            secret_file.write("******localhost:5432/appdb\n")
            secret_path = secret_file.name

        self.addCleanup(lambda: Path(secret_path).unlink(missing_ok=True))

        os.environ["DATABASE_URL_PATH"] = secret_path
        db = self._reload_db()

        self.assertEqual(
            db.get_database_url(),
            "******localhost:5432/appdb",
        )

    def test_raises_helpful_error_when_no_database_configuration_exists(self):
        db = self._reload_db()

        with self.assertRaises(RuntimeError) as error:
            db.get_database_url()

        message = str(error.exception)
        self.assertIn("No database configuration found", message)
        self.assertIn("DATABASE_URL_PATH", message)


if __name__ == "__main__":
    unittest.main()
