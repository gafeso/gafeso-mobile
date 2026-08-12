#!/usr/bin/env bash
# Contrôle préalable BLOQUANT de la recette d'appareil.
#
# L'APK ne contient plus armeabi-v7a : le moteur Flutter y était packagé alors
# que libpdfium.so n'existe que pour arm64-v8a et x86_64. Un téléphone 32 bits
# installait l'application et le LECTEUR échouait à l'ouverture du premier
# document. On refuse donc l'installation plutôt que de livrer cassé.
#
# Ce script le dit AVANT la recette, avec le nom de la cause — sinon l'échec
# apparaît à `adb install` sous la forme « INSTALL_FAILED_NO_MATCHING_ABIS »,
# qui n'explique rien.
set -uo pipefail

ADB="$(command -v adb || echo "$HOME/Android/Sdk/platform-tools/adb")"
[ -x "$ADB" ] || { printf '\033[31m✖ adb introuvable.\033[0m\n' >&2; exit 1; }

mapfile -t DEVICES < <("$ADB" devices | awk 'NR>1 && $2=="device"{print $1}')
if [ "${#DEVICES[@]}" -eq 0 ]; then
  printf '\033[31m✖ Aucun appareil connecté (adb devices).\033[0m\n' >&2
  exit 1
fi

CODE=0
for d in "${DEVICES[@]}"; do
  ABI="$("$ADB" -s "$d" shell getprop ro.product.cpu.abi | tr -d '\r')"
  LIST="$("$ADB" -s "$d" shell getprop ro.product.cpu.abilist | tr -d '\r')"
  SDK="$("$ADB" -s "$d" shell getprop ro.build.version.sdk | tr -d '\r')"
  MODELE="$("$ADB" -s "$d" shell getprop ro.product.model | tr -d '\r')"
  printf '\n\033[1m%s — %s\033[0m\n  abi=%s\n  abilist=%s\n  sdk=%s\n' \
    "$d" "$MODELE" "$ABI" "$LIST" "$SDK"

  case "$LIST" in
    *arm64-v8a*|*x86_64*)
      printf '  \033[32m✔\033[0m architecture 64 bits : l’APK s’installera\n' ;;
    *)
      printf '  \033[31m✖ ARM 32 bits UNIQUEMENT : cet appareil ne peut plus installer l’APK.\033[0m\n'
      printf '    Ce n’est pas une régression — libpdfium n’existe pas en 32 bits, et\n'
      printf '    l’application se serait installée pour échouer à l’ouverture d’un document.\n'
      printf '    Utilisez un appareil arm64, ou fournissez une libpdfium 32 bits.\n'
      CODE=1 ;;
  esac

  if [ -n "$SDK" ] && [ "$SDK" -lt 33 ] 2>/dev/null; then
    printf '  \033[31m✖ Android trop ancien (SDK %s < 33).\033[0m minSdk=33 : Ed25519 natif + keystore.\n' "$SDK"
    CODE=1
  else
    printf '  \033[32m✔\033[0m SDK %s ≥ 33\n' "$SDK"
  fi
done

exit "$CODE"
