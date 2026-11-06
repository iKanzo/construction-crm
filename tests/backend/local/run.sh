#!/usr/bin/env bash
# Быстрая локальная проверка миграций и pgTAP-тестов на обычном PostgreSQL 15+ с расширением pgTAP.
# Нужны: psql, pg_prove, доступный сервер PostgreSQL (по умолчанию localhost, пользователь postgres).
# Переменные: PGHOST, PGPORT, PGUSER, CRM_TEST_DB (по умолчанию crm_test).
set -euo pipefail
cd "$(dirname "$0")/../../.."

export PGHOST="${PGHOST:-localhost}" PGUSER="${PGUSER:-postgres}"
DB="${CRM_TEST_DB:-crm_test}"
ONERR=(-v ON_ERROR_STOP=1 -q)

psql -d postgres "${ONERR[@]}" -c "drop database if exists ${DB} with (force)" -c "create database ${DB}"
psql -d "$DB" "${ONERR[@]}" -f tests/backend/local/supabase_stub.sql
psql -d "$DB" "${ONERR[@]}" -c "create extension if not exists pgtap with schema extensions" \
  -c "alter database ${DB} set search_path = \"\$user\", public, extensions"

for f in backend/supabase/migrations/*.sql; do
  echo "migration: $(basename "$f")"
  psql -d "$DB" "${ONERR[@]}" -f "$f"
done

if [ -s backend/supabase/seed.sql ]; then
  psql -d "$DB" "${ONERR[@]}" -f backend/supabase/seed.sql >/dev/null
fi

pg_prove -d "$DB" --ext .sql tests/backend/database/*.test.sql
