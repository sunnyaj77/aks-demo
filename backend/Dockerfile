# syntax=docker/dockerfile:1

# ---- builder: install deps into a venv so the runner stage can copy just
# that, same "keep the shipped image small" reasoning as app/Dockerfile ----
FROM python:3.12-slim AS builder
WORKDIR /app
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ---- runner: the image that actually ships to ACR/AKS ----
FROM python:3.12-slim AS runner
WORKDIR /app
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Run as non-root — pairs with securityContext (runAsNonRoot: true) in the
# Helm chart, same pattern as the frontend image.
RUN addgroup --system --gid 1001 app \
  && adduser --system --uid 1001 --gid 1001 app

COPY --from=builder /opt/venv /opt/venv
COPY main.py .
COPY db.py .
COPY models ./models
COPY alembic.ini .
COPY alembic ./alembic

USER app
EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
