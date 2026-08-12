#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════
# Environnement de recette e2e du mobile — montage en une commande.
#
#   ./scripts/e2e-env.sh up      # monte l'infra + amorce le tenant de démo
#   ./scripts/e2e-env.sh test    # joue la suite COMPLÈTE (e2e gatés compris)
#   ./scripts/e2e-env.sh down    # arrête l'infra
#
# POURQUOI CE SCRIPT. Deux e2e sont gatés par MOBILE_E2E=1 : la lecture hors
# ligne de bout en bout (device EC → licence → CEK → blob → PDF → révocation →
# purge) et le parcours MVP. Sans environnement, ils sont IGNORÉS — et une
# suite qui affiche « All tests passed » en ayant sauté la preuve du cœur du
# produit est un faux silencieux de plus. Le montage prenait assez d'étapes
# pour qu'on y renonce ; c'est exactement ainsi qu'une garantie se perd.
#
# Ce qu'il faut savoir, appris en le montant :
#   · l'infra DEV est requise (MinIO sur 9000), pas la pile de production —
#     celle-ci n'expose que Caddy ;
#   · le harnais démarre SA PROPRE API : aucune API ne doit occuper le port
#     4000 pendant les tests ;
#   · la fixture exige le tenant `zinda`, que seul seed-demo.mjs crée ;
#   · le parcours MVP se connecte aux comptes de démo, dont le mot de passe est
#     TIRÉ AU HASARD par défaut — d'où SEED_PASSWORD, fixé ici.
# ═════════════════════════════════════════════════════════════════════════
set -euo pipefail

BACKEND="${GAFESO_BACKEND_DIR:-$HOME/bibliocloud}"
# SEED_PASSWORD est OBLIGATOIRE — aucun défaut, délibérément.
#
# Ce script portait une valeur EN DUR. Publiée, elle ouvre les
# comptes de démonstration de toute installation où le seed aurait été lancé
# sans surcharger la variable. C'est le QUATRIÈME mot de passe versionné de ce
# projet, et aucun des quatre n'a été vu par gitleaks : ce sont des identifiants
# applicatifs écrits à la main, pas des motifs de clé API.
#
# Le retirer une fois de plus ne suffirait pas — le défaut pratique revient
# toujours, parce qu'il est pratique. Un script qui REFUSE DE DÉMARRER sans sa
# variable ne peut pas le voir revenir en douce.
if [ -z "${SEED_PASSWORD:-}" ]; then
  printf '\033[31m✖ SEED_PASSWORD est requis.\033[0m\n' >&2
  printf '  Le mot de passe des comptes de démonstration est tiré au hasard par\n' >&2
  printf '  seed-demo.mjs. Choisissez-en un pour cette session et exportez-le :\n\n' >&2
  printf '    export SEED_PASSWORD="$(openssl rand -base64 12)Aa1!"\n' >&2
  printf '    ./scripts/e2e-env.sh up && ./scripts/e2e-env.sh test\n\n' >&2
  printf '  Aucune valeur par défaut ici : elle finirait versionnée.\n' >&2
  exit 1
fi
SEED_PW="$SEED_PASSWORD"
COMPOSE=(docker compose -f "$BACKEND/docker/docker-compose.yml" --env-file "$BACKEND/.env")

info() { printf '\033[34m→\033[0m %s\n' "$*"; }

# Arrête l'API d'amorçage et ATTEND que le port se libère.
#
# `kill` sur le PID retourné par `&` ne suffit pas : la commande lancée est
# `npx dotenv -- node …`, donc ce PID est celui de l'enveloppe npx. La tuer
# laisse `node dist/main.js` vivant, et le harnais e2e échoue ensuite sur un
# port occupé. Constaté en montant ce script — le garde-fou de `test` l'a
# attrapé, sinon la panne aurait été attribuée aux tests.
stop_api() {
  kill "${1:-0}" 2>/dev/null || true
  pkill -f 'node dist/main.js' 2>/dev/null || true
  for _ in $(seq 1 20); do
    curl -sf http://localhost:4000/health >/dev/null 2>&1 || return 0
    sleep 1
  done
  die "L'API d'amorçage n'a pas libéré le port 4000."
}
ok()   { printf '\033[32m✔\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$BACKEND" ] || die "Dépôt backend introuvable : $BACKEND (export GAFESO_BACKEND_DIR=…)"

up() {
  info "Infra de développement (db, minio, meilisearch, redis)…"
  "${COMPOSE[@]}" up -d db minio meilisearch redis >/dev/null
  for _ in $(seq 1 30); do
    docker exec "$("${COMPOSE[@]}" ps -q db)" pg_isready -q 2>/dev/null && break
    sleep 2
  done
  ok "infra démarrée"

  info "Migrations Prisma…"
  (cd "$BACKEND/apps/api" && npx dotenv -e ../../.env -- npx prisma migrate deploy >/dev/null)
  ok "migrations appliquées"

  # L'amorçage passe par l'API d'administration : il faut une API le temps du
  # seed, et SEULEMENT le temps du seed — le harnais e2e démarre la sienne.
  info "API temporaire (amorçage)…"
  (cd "$BACKEND/apps/api" && npx dotenv -e ../../.env -- node dist/main.js >/tmp/gafeso-seed-api.log 2>&1) &
  local pid=$!
  for _ in $(seq 1 40); do curl -sf http://localhost:4000/health >/dev/null 2>&1 && break; sleep 2; done
  curl -sf http://localhost:4000/health >/dev/null 2>&1 || { kill "$pid" 2>/dev/null; die "API non démarrée (voir /tmp/gafeso-seed-api.log)"; }

  info "Amorçage du tenant de démonstration…"
  (cd "$BACKEND" && SEED_PASSWORD="$SEED_PW" npx dotenv -e .env -- node scripts/seed-demo.mjs >/tmp/gafeso-seed.log 2>&1) \
    || { kill "$pid" 2>/dev/null; die "Amorçage échoué (voir /tmp/gafeso-seed.log)"; }

  stop_api "$pid"
  ok "tenant « zinda » prêt, mot de passe des comptes : $SEED_PW"
  ok "API temporaire arrêtée (le port 4000 doit rester libre)"
}

run_tests() {
  # Un port 4000 occupé ferait échouer le harnais avec un message obscur.
  if curl -sf http://localhost:4000/health >/dev/null 2>&1; then
    die "Une API occupe le port 4000. Arrêtez-la : le harnais e2e démarre la sienne."
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  # -j 1 : les fichiers de test s'exécutent en PARALLÈLE par défaut, et les deux
  # e2e partagent la MÊME fixture (même tenant, même étudiant, même document).
  # `fixture create` réinitialise les données : l'un remettait à zéro pendant
  # que l'autre attendait le statut de sa licence, qui ressortait alors
  # `unknown` au lieu de `revoked`. Le symptôme accusait la révocation ; la
  # cause était l'ordonnancement. Constaté ici — et mes exécutions vertes
  # précédentes passaient par chance de calendrier, pas parce que c'était juste.
  MOBILE_E2E=1 SEED_PASSWORD="$SEED_PW" GAFESO_BACKEND_DIR="$BACKEND" \
    flutter test -j 1 "$@"
}

case "${1:-}" in
  up)   up ;;
  test) shift; run_tests "$@" ;;
  down) "${COMPOSE[@]}" stop db minio meilisearch redis >/dev/null && ok "infra arrêtée" ;;
  *)    die "Usage : $0 {up|test|down}" ;;
esac
