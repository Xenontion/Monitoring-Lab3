"""Generate repeatable PostgreSQL workload for LR3 and collect measurements."""

from __future__ import annotations

import argparse
import getpass
import os
import time
from pathlib import Path

import psycopg


ROOT = Path(__file__).resolve().parent
REPORT_DIR = ROOT / "results"


def connection_args(args: argparse.Namespace) -> dict[str, object]:
    password = os.environ.get("PGPASSWORD") or getpass.getpass("Пароль PostgreSQL: ")
    return {
        "host": args.host,
        "port": args.port,
        "dbname": args.database,
        "user": args.user,
        "password": password,
    }


def execute_workload(connection: psycopg.Connection, seconds: int) -> None:
    queries = [
        ("full_scan", "SELECT count(*) FROM lr3_orders WHERE status = 'paid'"),
        (
            "join_and_sort",
            """
            SELECT c.region, c.full_name, sum(o.amount) AS total_amount
            FROM lr3_customers AS c
            JOIN lr3_orders AS o ON o.customer_id = c.customer_id
            WHERE o.created_at >= now() - interval '180 days'
            GROUP BY c.region, c.full_name
            ORDER BY total_amount DESC
            LIMIT 100
            """,
        ),
        (
            "indexed_lookup_candidate",
            "SELECT * FROM lr3_orders WHERE customer_id = 42 ORDER BY created_at DESC LIMIT 20",
        ),
    ]
    end_at = time.monotonic() + seconds
    executions = 0
    while time.monotonic() < end_at:
        for name, query in queries:
            with connection.cursor() as cursor:
                cursor.execute(query)
                cursor.fetchall()
            executions += 1
    print(f"Виконано запитів: {executions} за {seconds} секунд.")


def collect_report(connection: psycopg.Connection) -> None:
    REPORT_DIR.mkdir(exist_ok=True)
    with connection.cursor() as cursor:
        cursor.execute("SELECT to_regprocedure('public.powa_take_snapshot(integer)') IS NOT NULL")
        has_powa = cursor.fetchone()[0]
        if has_powa:
            for _ in range(5):
                cursor.execute("SELECT public.powa_take_snapshot(0)")

    top_queries = """
        SELECT queryid, calls, round(total_exec_time::numeric, 2) AS total_ms,
               round(mean_exec_time::numeric, 2) AS avg_ms, rows,
               shared_blks_hit, shared_blks_read,
               left(regexp_replace(query, '\\s+', ' ', 'g'), 180) AS query
        FROM pg_stat_statements
        WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
          AND query NOT LIKE '%pg_stat_statements%'
        ORDER BY total_exec_time DESC
        LIMIT 10
    """
    explain_query = """
        EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
        SELECT c.region, c.full_name, sum(o.amount) AS total_amount
        FROM lr3_customers AS c
        JOIN lr3_orders AS o ON o.customer_id = c.customer_id
        WHERE o.created_at >= now() - interval '180 days'
        GROUP BY c.region, c.full_name
        ORDER BY total_amount DESC
        LIMIT 100
    """
    with connection.cursor() as cursor:
        cursor.execute(top_queries)
        rows = cursor.fetchall()
        cursor.execute(explain_query)
        plan = "\n".join(row[0] for row in cursor.fetchall())
        cursor.execute("SELECT * FROM pg_stat_wal")
        wal = cursor.fetchone()

    with (REPORT_DIR / "top_queries.tsv").open("w", encoding="utf-8") as output:
        output.write("queryid\tcalls\ttotal_ms\tavg_ms\trows\thit\tread\tquery\n")
        for row in rows:
            output.write("\t".join(str(value) for value in row) + "\n")
    (REPORT_DIR / "explain.txt").write_text(plan + "\n", encoding="utf-8")
    (REPORT_DIR / "wal.txt").write_text(str(wal) + "\n", encoding="utf-8")
    print(f"Зібрано {len(rows)} найактивніших запитів у {REPORT_DIR}.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", default=5432, type=int)
    parser.add_argument("--database", default="lr3_powa")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--seconds", default=30, type=int)
    args = parser.parse_args()
    with psycopg.connect(**connection_args(args), autocommit=True) as connection:
        execute_workload(connection, args.seconds)
        collect_report(connection)


if __name__ == "__main__":
    main()
