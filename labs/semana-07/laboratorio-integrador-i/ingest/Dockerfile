FROM python:3.12-slim

RUN pip install --no-cache-dir \
    requests==2.32.3 \
    snowflake-connector-python==3.13.2

WORKDIR /opt/pipeline
COPY ingest.py /opt/pipeline/ingest.py

ENTRYPOINT []
CMD ["python", "/opt/pipeline/ingest.py"]

