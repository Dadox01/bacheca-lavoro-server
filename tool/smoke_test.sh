#!/usr/bin/env bash
# Smoke test end-to-end delle API: copre S1, S2, S3 del compito.
# Uso:  ./tool/smoke_test.sh [http://127.0.0.1:8080]
# Richiede: curl, jq. Il server deve essere già avviato.
set -uo pipefail

BASE="${1:-http://127.0.0.1:8080}"
TMP="$(mktemp -d)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32mOK\033[0m   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then pass "$1 ($2)"; else fail "$1: atteso $3, ottenuto $2"; fi; }
check_not() { if [ "$2" != "$3" ]; then pass "$1 ($2)"; else fail "$1: non atteso $3"; fi; }

# --- Curriculum di prova (PDF vero, generato dal sistema) -------------------
printf 'Mario Rossi\nCurriculum Vitae\nEsperienza: sviluppatore Flutter.\n' > "$TMP/cv.txt"
cupsfilter -m application/pdf "$TMP/cv.txt" > "$TMP/cv.pdf" 2>/dev/null
echo 'non sono un pdf' > "$TMP/finto.txt"

STAMP="$(date +%s)"
EMAIL_A="azienda${STAMP}@example.com"
EMAIL_B="altra${STAMP}@example.com"

echo "== S1: registrazione, login, pubblicazione annuncio =="
REG=$(curl -s -w '\n%{http_code}' -X POST "$BASE/api/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Acme Srl\",\"email\":\"$EMAIL_A\",\"password\":\"Password1\"}")
CODE=$(echo "$REG" | tail -1); BODY=$(echo "$REG" | sed '$d')
TOKEN=$(echo "$BODY" | jq -r '.token // empty')
check "registrazione azienda" "$CODE" "201"
check_not "token emesso" "${TOKEN:0:8}" ""

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"Acme Srl\",\"email\":\"$EMAIL_A\",\"password\":\"Password1\"}")
check "email duplicata rifiutata" "$CODE" "409"

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL_A\",\"password\":\"sbagliata1\"}")
check "login con password errata" "$CODE" "401"

LOGIN=$(curl -s -w '\n%{http_code}' -X POST "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL_A\",\"password\":\"Password1\"}")
CODE=$(echo "$LOGIN" | tail -1); BODY=$(echo "$LOGIN" | sed '$d')
TOKEN=$(echo "$BODY" | jq -r '.token // empty')
check "login azienda" "$CODE" "200"

JOB=$(curl -s -w '\n%{http_code}' -X POST "$BASE/api/jobs" \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{"title":"Sviluppatore Flutter","description":"Cerchiamo una persona per sviluppare app mobile con Flutter e Dart.","location":"Milano","contract":"Tempo indeterminato","salary":"30.000 - 38.000 EUR"}')
CODE=$(echo "$JOB" | tail -1); BODY=$(echo "$JOB" | sed '$d')
JOB_ID=$(echo "$BODY" | jq -r '.id // empty')
check "pubblicazione annuncio" "$CODE" "201"
check_not "id annuncio" "$JOB_ID" ""

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/jobs" \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{"title":"X","description":"corta","location":"","contract":"Boh"}')
check "annuncio non valido rifiutato" "$CODE" "422"

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/jobs" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Senza token","description":"Non deve funzionare senza token","location":"Roma","contract":"Stage"}')
check "pubblicazione senza token" "$CODE" "401"

echo "== S2: bacheca pubblica e candidatura =="
JOBS=$(curl -s "$BASE/api/jobs")
COUNT=$(echo "$JOBS" | jq 'length')
[ "$COUNT" -ge 1 ] && pass "bacheca pubblica ($COUNT annunci)" || fail "bacheca pubblica vuota"

CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/jobs/$JOB_ID")
check "dettaglio annuncio" "$CODE" "200"

APP=$(curl -s -w '\n%{http_code}' -X POST "$BASE/api/jobs/$JOB_ID/applications" \
  -F "firstName=Mario" -F "lastName=Rossi" -F "email=mario.rossi@example.com" \
  -F "message=Allego il mio curriculum, sono molto interessato." \
  -F "cv=@$TMP/cv.pdf;type=application/pdf")
CODE=$(echo "$APP" | tail -1); BODY=$(echo "$APP" | sed '$d')
APP_ID=$(echo "$BODY" | jq -r '.id // empty')
check "invio candidatura con PDF" "$CODE" "201"
check "nome file conservato" "$(echo "$BODY" | jq -r '.cv.originalName')" "cv.pdf"

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/jobs/$JOB_ID/applications" \
  -F "firstName=Mario" -F "lastName=Rossi" -F "email=mario.rossi@example.com")
check "candidatura senza curriculum" "$CODE" "422"

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/jobs/$JOB_ID/applications" \
  -F "firstName=Mario" -F "lastName=Rossi" -F "email=mario.rossi@example.com" \
  -F "cv=@$TMP/finto.txt;type=text/plain")
check "allegato non PDF rifiutato" "$CODE" "422"

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/jobs/$JOB_ID/applications" \
  -F "firstName=M" -F "lastName=Rossi" -F "email=non-una-email" -F "cv=@$TMP/cv.pdf")
check "candidatura con dati non validi" "$CODE" "422"

echo "== S3: consultazione candidature, curriculum, logout =="
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/jobs/$JOB_ID/applications")
check "candidature senza token" "$CODE" "401"

MINE=$(curl -s "$BASE/api/jobs/mine" -H "Authorization: Bearer $TOKEN")
check "conteggio candidature negli annunci" "$(echo "$MINE" | jq -r '.[0].applicationsCount')" "1"

LIST=$(curl -s "$BASE/api/jobs/$JOB_ID/applications" -H "Authorization: Bearer $TOKEN")
check "elenco candidature" "$(echo "$LIST" | jq -r '.applications | length')" "1"
check "dati candidato" "$(echo "$LIST" | jq -r '.applications[0].lastName')" "Rossi"

CODE=$(curl -s -o "$TMP/scarico.pdf" -w '%{http_code}' "$BASE/api/applications/$APP_ID/cv" \
  -H "Authorization: Bearer $TOKEN")
check "download curriculum" "$CODE" "200"
if cmp -s "$TMP/cv.pdf" "$TMP/scarico.pdf"; then pass "curriculum identico all'originale"; else fail "curriculum diverso dall'originale"; fi
check "content-type PDF" "$(curl -s -o /dev/null -w '%{content_type}' "$BASE/api/applications/$APP_ID/cv" -H "Authorization: Bearer $TOKEN")" "application/pdf"
check "download con ?token" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/applications/$APP_ID/cv?token=$TOKEN")" "200"

# Azienda estranea: non vede né annuncio altrui né candidature
REG_B=$(curl -s -X POST "$BASE/api/auth/register" -H 'Content-Type: application/json' \
  -d "{\"name\":\"Beta Spa\",\"email\":\"$EMAIL_B\",\"password\":\"Password1\"}")
TOKEN_B=$(echo "$REG_B" | jq -r '.token // empty')
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/jobs/$JOB_ID/applications" -H "Authorization: Bearer $TOKEN_B")
check "azienda estranea bloccata" "$CODE" "403"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/applications/$APP_ID/cv" -H "Authorization: Bearer $TOKEN_B")
check "curriculum non accessibile ad altri" "$CODE" "403"

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/logout" -H "Authorization: Bearer $TOKEN")
check "logout" "$CODE" "204"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/auth/me" -H "Authorization: Bearer $TOKEN")
check "token revocato dopo il logout" "$CODE" "401"

echo
echo "Risultato: $PASS test superati, $FAIL falliti"
rm -rf "$TMP"
[ "$FAIL" -eq 0 ]
