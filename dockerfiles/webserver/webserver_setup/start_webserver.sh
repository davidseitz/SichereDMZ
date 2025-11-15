#!/bin/sh
# Wait for database
echo "Waiting for database at $DB_HOST:$DB_PORT..."
while ! nc -z $DB_HOST $DB_PORT; do
  sleep 1
done

echo "Database reachable, starting Flask..."
exec gunicorn -b 0.0.0.0:80 app:app --workers 2 --timeout 120
