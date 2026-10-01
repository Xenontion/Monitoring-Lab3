-- Run this file while connected to the lr3_powa database as a superuser.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

DROP TABLE IF EXISTS lr3_orders;
DROP TABLE IF EXISTS lr3_customers;

CREATE TABLE lr3_customers (
    customer_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name text NOT NULL,
    region text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE lr3_orders (
    order_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES lr3_customers(customer_id),
    status text NOT NULL,
    amount numeric(12, 2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO lr3_customers (full_name, region)
SELECT 'Customer ' || n, (ARRAY['north', 'south', 'east', 'west'])[1 + (n % 4)]
FROM generate_series(1, 10000) AS numbers(n);

INSERT INTO lr3_orders (customer_id, status, amount, created_at)
SELECT 1 + (n % 10000),
       (ARRAY['new', 'paid', 'shipped', 'cancelled'])[1 + (n % 4)],
       round((10 + random() * 990)::numeric, 2),
       now() - ((n % 365) || ' days')::interval
FROM generate_series(1, 100000) AS numbers(n);

ANALYZE lr3_customers;
ANALYZE lr3_orders;

-- Deliberately no index on region/status: the workload demonstrates Seq Scan.
SELECT 'Database setup complete' AS status,
       (SELECT count(*) FROM lr3_customers) AS customers,
       (SELECT count(*) FROM lr3_orders) AS orders;
