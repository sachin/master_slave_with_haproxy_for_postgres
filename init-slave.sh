#!/bin/bash

# Initialize variables
SLAVE_NAME=$1
MASTER_HOST="master"
MASTER_PORT=5432

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Clean up existing data directory
log_message "Cleaning up existing data directory..."
rm -rf /var/lib/postgresql/data/*

# Wait for master and perform base backup
log_message "Waiting for master to be ready and performing base backup..."
until PGPASSWORD=${POSTGRES_PASSWORD} pg_basebackup -h ${MASTER_HOST} -D /var/lib/postgresql/data -U ${POSTGRES_USER} -P -R -X stream -S ${SLAVE_NAME}_slot; do
    log_message "Waiting for master to be ready..."
    sleep 5
done

# Configure standby settings
log_message "Configuring standby settings..."
touch /var/lib/postgresql/data/standby.signal

# Configure connection to primary
log_message "Setting up primary connection info..."
echo "primary_conninfo = 'host=${MASTER_HOST} port=${MASTER_PORT} user=${POSTGRES_USER} password=${POSTGRES_PASSWORD} application_name=${SLAVE_NAME}'" >> /var/lib/postgresql/data/postgresql.auto.conf

# Enable read-only mode
log_message "Enabling read-only mode..."
echo "default_transaction_read_only = on" >> /var/lib/postgresql/data/postgresql.conf
echo "hot_standby_feedback = on" >> /var/lib/postgresql/data/postgresql.conf

# Start PostgreSQL
log_message "Starting PostgreSQL..."
exec docker-entrypoint.sh postgres