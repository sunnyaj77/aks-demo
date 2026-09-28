import unittest
from unittest.mock import patch

import main


class DbCheckRouteTests(unittest.TestCase):
    def test_db_check_uses_shared_database_connectivity_helper(self):
        with patch("main.check_database_connectivity") as mocked_check:
            result = main.db_check()

        mocked_check.assert_called_once_with()
        self.assertTrue(result["ok"])
        self.assertIn("latencyMs", result)

    def test_db_check_surfaces_connectivity_errors(self):
        with patch(
            "main.check_database_connectivity",
            side_effect=RuntimeError("db unavailable"),
        ):
            result = main.db_check()

        self.assertEqual(result, {"ok": False, "reason": "db unavailable"})


if __name__ == "__main__":
    unittest.main()
