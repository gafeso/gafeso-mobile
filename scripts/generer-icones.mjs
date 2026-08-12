#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════
// Génération des icônes Android depuis la source de marque.
//
//   node scripts/generer-icones.mjs
//
// Produit, à partir du SEUL fichier `assets/marque/gafeso_icone_simplifiee.svg` :
//   · mipmap-*/ic_launcher_foreground.png  — premier plan de l'icône adaptative
//   · mipmap-*/ic_launcher_monochrome.png  — silhouette des icônes thématiques
//   · mipmap-*/ic_launcher.png             — repli hérité (voir plus bas)
//   · drawable-*/ic_notification.png       — silhouette de la barre d'état
//
// POURQUOI UN SCRIPT PLUTÔT QUE DES PNG POSÉS À LA MAIN. USAGE.md interdit de
// régénérer les fichiers de marque : le SVG est la vérité. Un script qui part
// de ce SVG garde ce lien vérifiable — on peut rejouer la génération et
// comparer. Des PNG déposés à la main sont orphelins dès le lendemain : plus
// personne ne sait à quelle version du logo ils correspondent.
//
// ── Les deux pièges, et ce qui les désamorce ─────────────────────────────
//
// 1. LE MASQUAGE. Android découpe l'icône selon le lanceur (cercle, squircle,
//    carré arrondi, goutte). Sur les 108 dp de la couche, seuls les 72 dp
//    centraux sont visibles, et le cercle inscrit dans ces 72 dp est la seule
//    surface commune à TOUTES les formes — un cercle est le masque qui rogne
//    le plus, toute autre forme le contient.
//
//    On y inscrit l'artwork par son CERCLE ENGLOBANT MINIMAL, pas par sa boîte
//    englobante : la boîte a une diagonale de 910 unités quand le cercle réel
//    n'en fait que 717, soit 27 % de marge perdue pour rien — une icône
//    inutilement rabougrie dans la grille.
//
//    Attention : deux « 66 » circulent et ne désignent pas la même chose.
//    72/108 = 66,7 % est la garantie géométrique du masque ; 66/108 = 61 % est
//    la recommandation de Google, qui réserve en plus de quoi encaisser la
//    PARALLAXE (certains lanceurs décalent le premier plan par rapport au fond
//    pendant l'animation). On vise 61 % : cela satisfait les deux lectures.
//
// 2. LE VERT SUR LE VERT. Le toit du logo est #1B5E3F — exactement la couleur
//    du fond en aplat. Posé tel quel, IL DISPARAÎT : il ne reste qu'un livre
//    orange flottant, et « la maison des livres » perd sa maison. Aucun
//    fichier ne le laisse deviner, et les rendus masqués paraissent corrects
//    tant qu'on ne les regarde pas. Le toit passe donc en blanc sur l'icône
//    (le livre garde son orange, qui tranche déjà sur le vert).
//
//    C'est la raison pour laquelle la vérification se fait à l'écran d'accueil
//    et pas sur les fichiers générés.
// ═════════════════════════════════════════════════════════════════════════

import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const RACINE = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// `sharp` est le seul moteur de rendu SVG disponible sur les postes du projet.
// Il vit dans le dépôt backend — même convention que scripts/e2e-env.sh.
const BACKEND = process.env.GAFESO_BACKEND_DIR || join(process.env.HOME, 'bibliocloud');
let sharp;
try {
  sharp = (await import(join(BACKEND, 'node_modules/sharp/lib/index.js'))).default;
} catch {
  console.error(
    `✖ sharp introuvable dans ${BACKEND}/node_modules.\n` +
      `  Installez les dépendances du backend, ou pointez GAFESO_BACKEND_DIR ailleurs.`,
  );
  process.exit(1);
}

const SRC = join(RACINE, 'assets/marque/gafeso_icone_simplifiee.svg');
const RES = join(RACINE, 'android/app/src/main/res');

// ── Géométrie de la source ───────────────────────────────────────────────
// Cercle englobant minimal de l'artwork, en unités du viewBox (840 × 800).
// Noter que son centre n'est PAS celui du viewBox (420, 400) : le dessin est
// légèrement plus haut. Centrer sur le viewBox décalerait l'icône vers le bas.
const ART = { cx: 420, cy: 393.6, d: 717.2 };

// Part de la largeur de la couche occupée par le cercle englobant (cf. piège 1).
const PART_SURE = 0.611;

const VERT = '#1B5E3F';

// Couleurs du premier plan sur l'aplat vert (cf. piège 2).
const SUR_VERT = { toit: '#FFFFFF', pageG: '#E07A2B', pageD: '#C4641F', filet: VERT };

// Densités Android : facteur × 108 dp pour les couches d'icône adaptative.
const DENSITES = [
  ['mdpi', 1],
  ['hdpi', 1.5],
  ['xhdpi', 2],
  ['xxhdpi', 3],
  ['xxxhdpi', 4],
];

// ── Fabrique de SVG ──────────────────────────────────────────────────────
const source = readFileSync(SRC, 'utf8');
const corps = source.match(/<g transform="translate\(0,0\) scale\(1\)">([\s\S]*?)<\/g>/)?.[1];
if (!corps) {
  console.error('✖ Le SVG source n’a plus la forme attendue — génération interrompue.');
  process.exit(1);
}

/** Rejoue les chemins de la source avec d’autres couleurs. */
function teinte({ toit, pageG, pageD, filet }) {
  return corps
    .replace('fill="#1B5E3F"', `fill="${toit}"`)
    .replace('fill="#E07A2B"', `fill="${pageG}"`)
    .replace('fill="#C4641F"', `fill="${pageD}"`)
    .replace('stroke="#FFFFFF"', `stroke="${filet}"`);
}

/**
 * Enveloppe le corps dans un canevas carré de `n` px, l'artwork inscrit dans un
 * cercle de `part` × `n` et centré sur son propre centre englobant.
 */
function canevas(n, contenu, part = PART_SURE, defs = '', attrsG = '') {
  const s = (part * n) / ART.d;
  const tx = n / 2 - ART.cx * s;
  const ty = n / 2 - ART.cy * s;
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${n}" height="${n}" viewBox="0 0 ${n} ${n}">` +
      `${defs}<g transform="translate(${tx.toFixed(3)},${ty.toFixed(3)}) scale(${s.toFixed(6)})"${attrsG}>` +
      `${contenu}</g></svg>`,
  );
}

/**
 * Silhouette pleine d'une seule couleur, utilisée pour la couche monochrome et
 * pour la barre d'état.
 *
 * Le filet central du livre ne peut pas être un TRAIT ici : une silhouette n'a
 * qu'un canal alpha, un trait blanc y deviendrait de la matière comme le reste
 * et les deux pages fusionneraient en un bloc. Il faut un VRAI TROU — d'où le
 * masque, qui retire le trait de la surface au lieu de l'y peindre.
 */
function silhouette(n, couleur, part = PART_SURE) {
  const plein = corps
    .replace(/fill="#[0-9A-Fa-f]{6}"/g, `fill="${couleur}"`)
    // Le trait devient l'agent du trou : il est noir DANS le masque.
    .replace(/<path d="M420 520 L420 720"[^/]*\/>/, '');
  const defs =
    `<defs><mask id="filet" maskUnits="userSpaceOnUse" x="0" y="0" width="840" height="800">` +
    `<rect x="0" y="0" width="840" height="800" fill="#FFFFFF"/>` +
    `<path d="M420 520 L420 720" stroke="#000000" stroke-width="24"/>` +
    `</mask></defs>`;
  return canevas(n, plein, part, defs, ' mask="url(#filet)"');
}

function ecrire(dossier, nom, buffer) {
  mkdirSync(join(RES, dossier), { recursive: true });
  writeFileSync(join(RES, dossier, nom), buffer);
}

const rendu = (svg, n) => sharp(svg, { density: 384 }).resize(n, n).png({ compressionLevel: 9 }).toBuffer();

// ── 1. Premier plan de l'icône adaptative (108 dp) ───────────────────────
for (const [d, f] of DENSITES) {
  const n = Math.round(108 * f);
  ecrire(`mipmap-${d}`, 'ic_launcher_foreground.png', await rendu(canevas(n, teinte(SUR_VERT)), n));
}

// ── 2. Couche monochrome (icônes thématiques, Android 13+) ───────────────
// Le système ne garde que l'alpha et la teinte lui-même : on dessine en noir.
for (const [d, f] of DENSITES) {
  const n = Math.round(108 * f);
  ecrire(`mipmap-${d}`, 'ic_launcher_monochrome.png', await rendu(silhouette(n, '#000000'), n));
}

// ── 3. Icône héritée ─────────────────────────────────────────────────────
// minSdk = 33 : aucun appareil supporté ne l'affichera jamais comme icône de
// lanceur (mipmap-anydpi-v26 l'emporte partout). On la régénère quand même
// plutôt que de laisser traîner l'icône Flutter par défaut : c'est le repli
// qu'exhument les outils d'inventaire et les fiches de magasin, et une icône
// bleue générique y passerait pour l'identité du produit.
for (const [d, f] of DENSITES) {
  const n = Math.round(48 * f);
  const fond = await sharp({ create: { width: n, height: n, channels: 4, background: VERT } })
    .png()
    .toBuffer();
  // Pas de masque ici : on remplit davantage, mais on garde une marge visuelle.
  const marque = canevas(n, teinte(SUR_VERT), 0.72);
  ecrire(
    `mipmap-${d}`,
    'ic_launcher.png',
    await sharp(fond).composite([{ input: await rendu(marque, n) }]).png({ compressionLevel: 9 }).toBuffer(),
  );
}

// ── 4. Icône de barre d'état ─────────────────────────────────────────────
// Android ≥ 5 ne retient QUE l'alpha des petites icônes de notification et les
// peint en blanc. L'app pointait `@mipmap/ic_launcher`, une image opaque : son
// alpha est un rectangle plein, donc la notification affichait un CARRÉ BLANC.
// Une silhouette dédiée est la seule forme correcte.
for (const [d, f] of [
  ['mdpi', 1],
  ['hdpi', 1.5],
  ['xhdpi', 2],
  ['xxhdpi', 3],
  ['xxxhdpi', 4],
]) {
  const n = Math.round(24 * f);
  // Presque plein cadre : la barre d'état applique déjà sa propre marge, et
  // 24 dp est le plancher de lisibilité de l'icône simplifiée (USAGE.md).
  // Y appliquer la marge de masquage de 61 % la rendrait illisible.
  const svg = silhouette(n, '#FFFFFF', 0.92);
  ecrire(`drawable-${d}`, 'ic_notification.png', await rendu(svg, n));
}

console.log('✔ Icônes générées dans android/app/src/main/res');
