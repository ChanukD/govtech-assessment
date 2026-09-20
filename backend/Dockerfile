# One image, two services. The API and the worker run the same code with different
# entrypoints - exactly as they do in AWS, where both ECS services pull from their own
# ECR repository but share this build.

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Run as a non-root user. Creating /data here as well as declaring it a volume mount
# point matters: Docker seeds a fresh named volume from the image, ownership included,
# so the unprivileged process can write the SQLite file.
RUN useradd --create-home --uid 10001 app \
    && mkdir -p /data \
    && chown app:app /data

WORKDIR /srv/app

# Dependencies are declared in pyproject.toml, so the source has to be present to
# install. That costs a layer rebuild when application code changes; with a larger
# dependency set it would be worth splitting them into a separate requirements layer.
COPY --chown=app:app pyproject.toml ./
COPY --chown=app:app app ./app

RUN pip install --no-cache-dir .

USER app

ENV PIPELINE_DATABASE_PATH=/data/pipeline.db \
    PIPELINE_SOURCE_FILE=/srv/data/records.csv

VOLUME ["/data"]
EXPOSE 8000

# Overridden by the worker service in docker-compose.yaml.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
