CREATE OR REPLACE FUNCTION _sysinternal.create_schema(
    schema_name NAME
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
BEGIN
    EXECUTE format(
        $$
            CREATE SCHEMA IF NOT EXISTS %I
        $$, schema_name);
END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.create_main_table(
    schema_name NAME,
    table_name  NAME
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
BEGIN
    EXECUTE format(
        $$
            CREATE TABLE IF NOT EXISTS %I.%I (
            )
        $$, schema_name, table_name);
END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.create_root_table(
    schema_name NAME,
    table_name  NAME
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
BEGIN
    EXECUTE format(
        $$
            CREATE TABLE IF NOT EXISTS %I.%I (
            )
        $$, schema_name, table_name);
END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.create_root_distinct_table(
    schema_name NAME,
    table_name  NAME
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
BEGIN
    EXECUTE format(
        $$
            CREATE TABLE IF NOT EXISTS %1$I.%2$I (
                field TEXT,
                value TEXT,
                PRIMARY KEY(field, value)
            );
        $$, schema_name, table_name);
END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.create_local_distinct_table(
    schema_name         NAME,
    table_name          NAME,
    replica_schema_name NAME,
    replica_table_name  NAME
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
BEGIN
    EXECUTE format(
        $$
            CREATE TABLE IF NOT EXISTS %1$I.%2$I (PRIMARY KEY(field, value))
            INHERITS(%3$I.%4$I);

        $$, schema_name, table_name, replica_schema_name, replica_table_name);
END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.create_remote_table(
    schema_name        NAME,
    table_name         NAME,
    parent_schema_name NAME,
    parent_table_name  NAME,
    database_name      NAME
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
DECLARE
    node_row node;
BEGIN
    SELECT *
    INTO STRICT node_row
    FROM node n
    WHERE n.database_name = create_remote_table.database_name;

    EXECUTE format(
        $$
            CREATE FOREIGN TABLE IF NOT EXISTS %1$I.%2$I () INHERITS(%3$I.%4$I) SERVER %5$I
            OPTIONS (schema_name %1$L, table_name %2$L)
        $$,
        schema_name, table_name, parent_schema_name, parent_table_name, node_row.server_name);
END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.create_local_data_table(
    schema_name        NAME,
    table_name         NAME,
    parent_schema_name NAME,
    parent_table_name  NAME
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
BEGIN
    EXECUTE format(
        $$
            CREATE TABLE IF NOT EXISTS %1$I.%2$I () INHERITS(%3$I.%4$I);
        $$,
        schema_name, table_name, parent_schema_name, parent_table_name);
END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.create_replica_table(
    schema_name        NAME,
    table_name         NAME,
    parent_schema_name NAME,
    parent_table_name  NAME
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
BEGIN
    EXECUTE format(
        $$
            CREATE TABLE IF NOT EXISTS %1$I.%2$I () INHERITS(%3$I.%4$I)
        $$,
        schema_name, table_name, parent_schema_name, parent_table_name);
END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.create_data_partition_table(
    schema_name        NAME,
    table_name         NAME,
    parent_schema_name NAME,
    parent_table_name  NAME,
    keyspace_start     SMALLINT,
    keyspace_end       SMALLINT,
    epoch_id           INT
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
DECLARE
    epoch_row    partition_epoch;
    field_exists BOOLEAN;
BEGIN
    SELECT *
    INTO STRICT epoch_row
    FROM partition_epoch pe
    WHERE pe.id = epoch_id;

    EXECUTE format(
        $$
            CREATE TABLE IF NOT EXISTS %1$I.%2$I (
            ) INHERITS(%3$I.%4$I)
        $$,
        schema_name, table_name, parent_schema_name, parent_table_name);

    SELECT COUNT(*) > 0
    INTO field_exists
    FROM field f
    WHERE f.hypertable_name = epoch_row.hypertable_name
          AND f.name = epoch_row.partitioning_field;

    IF field_exists THEN
        PERFORM _sysinternal.add_partition_constraint(schema_name, table_name, keyspace_start, keyspace_end, epoch_id);
    END IF;
END
$BODY$;

CREATE SEQUENCE IF NOT EXISTS pidx_index_name_seq;

CREATE OR REPLACE FUNCTION _sysinternal.add_partition_constraint(
    schema_name    NAME,
    table_name     NAME,
    keyspace_start SMALLINT,
    keyspace_end   SMALLINT,
    epoch_id       INT
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
DECLARE
    epoch_row partition_epoch;
BEGIN
    SELECT *
    INTO STRICT epoch_row
    FROM partition_epoch pe
    WHERE pe.id = epoch_id;

    EXECUTE format(
        $$
            ALTER TABLE %1$I.%2$I 
            ADD CONSTRAINT partition CHECK(%3$s(%4$I::text, %5$L) BETWEEN %6$L AND %7$L)
        $$,
        schema_name, table_name,
        epoch_row.partitioning_func, epoch_row.partitioning_field,
        epoch_row.partitioning_mod, keyspace_start, keyspace_end);

END
$BODY$;

CREATE OR REPLACE FUNCTION _sysinternal.set_time_constraint(
    schema_name NAME,
    table_name  NAME,
    start_time  BIGINT,
    end_time    BIGINT
)
    RETURNS VOID LANGUAGE PLPGSQL VOLATILE AS
$BODY$
DECLARE
BEGIN
    EXECUTE format(
        $$
            ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS time_range
        $$,
        schema_name, table_name);

    IF start_time IS NOT NULL AND end_time IS NOT NULL THEN
        EXECUTE format(
            $$
            ALTER TABLE %I.%I ADD CONSTRAINT time_range CHECK(time >= %L AND time <= %L)
        $$,
            schema_name, table_name, start_time, end_time);
    ELSIF start_time IS NOT NULL THEN
        EXECUTE format(
            $$
            ALTER TABLE %I.%I ADD CONSTRAINT time_range CHECK(time >= %L)
        $$,
            schema_name, table_name, start_time);
    ELSIF end_time IS NOT NULL THEN
        EXECUTE format(
            $$
            ALTER TABLE %I.%I ADD CONSTRAINT time_range CHECK(time <= %L)
        $$,
            schema_name, table_name, end_time);
    END IF;
END
$BODY$;

