#!/bin/sh
# Wait for DB
#echo "Waiting for database at $DB_HOST:$DB_PORT..."
#until nc -z $DB_HOST $DB_PORT; do
#    sleep 1
#done

cd /app

#python -c "from app import init_db; init_db()"
#echo "Starting Gunicorn..."
#exec gunicorn -b 0.0.0.0:80 app:app --workers 2 --timeout 120
