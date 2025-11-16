#!/bin/sh
# Wait for DB
echo "Waiting for database at $DB_HOST:$DB_PORT..."
until nc -z $DB_HOST $DB_PORT; do
    sleep 1
done

echo "Starting Gunicorn..."
exec gunicorn -b 0.0.0.0:5000 app:app --workers 2 --timeout 120
