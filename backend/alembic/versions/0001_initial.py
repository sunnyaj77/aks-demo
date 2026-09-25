"""Initial empty migration.

This establishes Alembic's migration history without inventing application
schema. Add tables through models and generate the next revision with:

    alembic revision --autogenerate -m "describe schema change"
"""
from typing import Sequence, Union

from alembic import op


revision: str = "0001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
