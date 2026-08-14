#!/usr/bin/env bash

set -euo pipefail

OUT="/opt/ansible/hosts/inventory.yml"
TMP="/opt/ansible/temp/hosts.txt"
ENV_FILE="/opt/ansible/.env"

LDAP_SERVER="ldap://192.168.0.2"
LDAP_USER="admin.vitor@coopershoes.com.br"
LDAP_BASE="DC=coopershoes,DC=com,DC=br"

# ============================================================
# Carregar .env
# ============================================================

if [[ ! -f "$ENV_FILE" ]]; then
    echo "[ERRO] Arquivo .env não encontrado: $ENV_FILE"
    exit 1
fi

source "$ENV_FILE"

if [[ -z "${LDAP_PASSWORD:-}" ]]; then
    echo "[ERRO] LDAP_PASSWORD não definida no .env"
    exit 1
fi

# ============================================================
# Preparar diretórios
# ============================================================

mkdir -p "$(dirname "$OUT")"
mkdir -p "$(dirname "$TMP")"

# ============================================================
# Consultar Active Directory
# ============================================================

echo "[INFO] Consultando Active Directory..."

ldapsearch -x \
    -H "$LDAP_SERVER" \
    -D "$LDAP_USER" \
    -w "$LDAP_PASSWORD" \
    -b "$LDAP_BASE" \
    -E pr=1000/noprompt \
    "(&(objectClass=computer)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))" \
    dNSHostName |
    awk '/^dNSHostName:/ {print $2}' |
    sort -u > "$TMP"

TOTAL=$(wc -l < "$TMP")

if [[ "$TOTAL" -eq 0 ]]; then
    echo "[ERRO] Nenhum computador encontrado no Active Directory."
    exit 1
fi

echo "[INFO] Computadores encontrados: $TOTAL"

# ============================================================
# Gerar inventário
# ============================================================

cat > "$OUT" <<EOF
all:
  children:
    windows:
      hosts:
EOF

while read -r host; do
    echo "        ${host}:" >> "$OUT"
done < "$TMP"

echo "[INFO] Inventário atualizado:"
echo "       $OUT"
echo "[INFO] Total de hosts: $TOTAL"