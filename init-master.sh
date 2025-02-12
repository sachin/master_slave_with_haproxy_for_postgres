#!/bin/bash

# Check if PRIMARY_ROLE is set
if [ "${PRIMARY_ROLE}" = "true" ]; then
    # Enable replication settings for master
    cat >> "${PGDATA}/postgresql.conf" << EOF
    listen_addresses = '*'
    wal_level = replica
    max_wal_senders = 10
    wal_keep_size = 64MB
    hot_standby = on
    max_replication_slots = 10
    synchronous_commit = on
    max_connections = 100
    shared_buffers = 128MB
EOF

    # Configure authentication for replication
    cat >> "${PGDATA}/pg_hba.conf" << EOF
    host replication myuser all md5
    host all all all md5
EOF

    # Create replication slot for slaves
    psql -U myuser -d mydb -c "SELECT pg_create_physical_replication_slot(slot_name) FROM unnest(ARRAY['slave1_slot', 'slave2_slot', 'slave3_slot']) AS slot_name;" || true
fi