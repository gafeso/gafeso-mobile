# Règles R8/ProGuard — build release.
#
# ⚠ Constaté sur device en RELEASE (invisible en debug) : R8 SUPPRIMAIT
# `SegmentedBlobReader.readRange`, appelée UNIQUEMENT depuis le code natif (callback
# `m_GetBlock` de PDFium via `GetMethodID`). R8 ne voit pas cet usage → méthode jugée morte →
# « readRange introuvable » et refus d'ouvrir le document. Vérifié dans le DEX : 0 occurrence
# de `readRange` en release contre 1 en debug.
#
# ⚠ Piège de directive : `-keepclasseswithmembernames` ne suffit PAS (elle autorise le
# shrinking : elle préserve les NOMS de ce qui est conservé, pas l'existence). Il faut `-keep`.
#
# L'enregistrement JNI est IMPLICITE (symboles `Java_com_gafeso_reader_PdfiumBridge_*`) : le nom
# de la classe ET celui des méthodes natives doivent survivre à l'obfuscation.

# Source déchiffrante : appelée par le natif en upcall JNI (readRange), et son fileLen est lu
# depuis Kotlin lors de l'ouverture.
-keep class com.gafeso.reader.SegmentedBlobReader { *; }

# Pont JNI : liaison par nom au chargement de la bibliothèque.
-keep class com.gafeso.reader.PdfiumBridge { *; }

# Toute méthode native, quelle que soit la classe (défense générale).
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
