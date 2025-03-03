#!/bin/bash

echo "Waiting for Postgres at $POSTGRES_HOST:$POSTGRES_PORT..."

until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER"; do
  echo "Database unavailable, retrying in 2 seconds..."
  sleep 2
done

echo "Database is ready!"
exec "$@"
