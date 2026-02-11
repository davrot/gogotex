docker exec keycloak-postgres bash -c "pg_dump -U keycloak -d keycloak -F c -f /backup/backup.sql"
