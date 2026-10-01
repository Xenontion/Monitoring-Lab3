CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_stat_kcache;
CREATE EXTENSION IF NOT EXISTS pg_qualstats;
CREATE EXTENSION IF NOT EXISTS hypopg;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS powa;

DO $$
DECLARE
    v_srvid integer;
    v_registered boolean;
BEGIN
    SELECT id INTO v_srvid
    FROM public.powa_servers
    WHERE alias = 'local-powa'
    LIMIT 1;

    IF v_srvid IS NULL THEN
        SELECT public.powa_register_server(
            'powa-db', 5432, 'local-powa', 'postgres', 'postgres', 'powa',
            60, 5, '1 day'::interval, true,
            ARRAY['pg_stat_kcache', 'pg_qualstats', 'pg_wait_sampling']
        ) INTO v_registered;

        SELECT id INTO v_srvid
        FROM public.powa_servers
        WHERE alias = 'local-powa'
        LIMIT 1;
    END IF;

    PERFORM public.powa_take_snapshot(0);
END $$;

SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('powa', 'pg_stat_statements', 'pg_stat_kcache', 'pg_qualstats', 'hypopg')
ORDER BY extname;

SELECT id, alias, hostname, port, dbname, frequency
FROM public.powa_servers
WHERE alias = 'local-powa';
