FROM python:3.12-slim

RUN pip install --no-cache-dir \
    dbt-core==1.9.8 \
    dbt-snowflake==1.9.4

WORKDIR /opt/dbt
COPY . /opt/dbt
RUN chmod +x /opt/dbt/run_dbt.sh

ENTRYPOINT []
CMD ["bash", "/opt/dbt/run_dbt.sh"]
