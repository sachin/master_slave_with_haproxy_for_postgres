#!/bin/bash

# Function to check if a command was successful
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    local host=$1
    local port=$2
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        PGPASSWORD=mypassword psql -h localhost -p $port -U myuser -d mydb -c "SELECT 1;" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "PostgreSQL at $host:$port is ready"
            return 0
        fi
        echo "Waiting for PostgreSQL at $host:$port (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done

    echo "Timeout waiting for PostgreSQL at $host:$port"
    return 1
}

# Clean up any existing containers
echo "Cleaning up existing containers..."
docker compose down -v
rm -rf pg_* 
# Start the containers
echo "Starting containers..."
docker compose up -d
check_status "Failed to start containers"

# Wait for master and slaves to be ready
echo "Waiting for PostgreSQL instances to be ready..."
wait_for_postgres "localhost" "5500"  # HAProxy read port
check_status "HAProxy read port not ready"

wait_for_postgres "localhost" "5501"  # HAProxy write port
check_status "HAProxy write port not ready"

# Test 1: Create a table through HAProxy write port
echo "\nTest 1: Creating table through HAProxy write port..."
PGPASSWORD=mypassword psql -h localhost -p 5501 -U myuser -d mydb -c "
    CREATE TABLE test_table (id SERIAL PRIMARY KEY, name VARCHAR(50));
    INSERT INTO test_table (name) VALUES ('test1'), ('test2');"
check_status "Failed to create table through HAProxy write port"

# Test 2: Verify data through HAProxy read port
echo "\nTest 2: Verifying data through HAProxy read port..."
sleep 5  # Give some time for replication to occur
PGPASSWORD=mypassword psql -h localhost -p 5500 -U myuser -d mydb -c "SELECT * FROM test_table;"
check_status "Failed to verify data through HAProxy read port"

# Test 3: Check load balancing by running multiple read queries
echo "\nTest 3: Testing load balancing through HAProxy read port..."
for i in {1..6}; do
    echo "Read query $i:"
    PGPASSWORD=mypassword psql -h localhost -p 5500 -U myuser -d mydb -c "SELECT COUNT(*) FROM test_table;"
    check_status "Failed to execute read query through HAProxy"
done

# Test 4: Verify read-only enforcement on read port
echo "\nTest 4: Verifying read-only enforcement on HAProxy read port..."
PGPASSWORD=mypassword psql -h localhost -p 5500 -U myuser -d mydb -c "INSERT INTO test_table (name) VALUES ('test3');" 2>&1 | grep -q "cannot execute INSERT in a read-only transaction"
if [ $? -eq 0 ]; then
    echo "Read port is correctly in read-only mode"
else
    echo "Error: Read port is not enforcing read-only mode"
    exit 1
fi

# Test 5: Write data and verify through read port
echo "\nTest 5: Writing data through write port and verifying through read port..."
PGPASSWORD=mypassword psql -h localhost -p 5501 -U myuser -d mydb -c "INSERT INTO test_table (name) VALUES ('test4'), ('test5');"
check_status "Failed to insert additional data through write port"

sleep 5  # Give some time for replication to occur

echo "Verifying data through read port..."
PGPASSWORD=mypassword psql -h localhost -p 5500 -U myuser -d mydb -c "SELECT COUNT(*) FROM test_table;"
check_status "Failed to verify data through read port"

# Clean up
echo "\nCleaning up..."
docker compose down -v
check_status "Failed to clean up containers"
rm -rf pg_* 
echo "\nAll tests completed successfully!"