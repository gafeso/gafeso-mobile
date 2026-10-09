package com.gafeso.reader

import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter

/**
 * Modes de lecture — **Classique**, **Sépia**, **Nuit**.
 *
 * ⚠ CE QU'ON N'OFFRE PAS, ET POURQUOI. Pas de réglage de police, pas
 * d'interligne : un PDF est une page déjà composée. Afficher un curseur qui ne
 * change rien est pire que ne rien offrir — l'usager essaie, constate que rien
 * ne bouge, et conclut que l'application est cassée.
 *
 * Les trois modes agissent sur le RENDU de la page, par une matrice de
 * couleurs : rien n'est redessiné, rien n'est redéchiffré.
 */
enum class ModeLecture(val cle: String) {
    CLASSIQUE("classique"),
    SEPIA("sepia"),
    NUIT("nuit");

    /** Fond de la vue, derrière la page. */
    val fond: Int
        get() = when (this) {
            CLASSIQUE -> Color.parseColor("#FBFDF9")
            SEPIA -> Color.parseColor("#F3E7D0")
            NUIT -> Color.parseColor("#12140F")
        }

    /** Filtre appliqué au bitmap de la page, ou `null` en classique. */
    fun filtre(): ColorMatrixColorFilter? = when (this) {
        CLASSIQUE -> null
        // Désaturation puis teinte chaude : le blanc du papier devient crème,
        // le noir reste noir. On ne touche pas au contraste du texte.
        SEPIA -> ColorMatrixColorFilter(
            ColorMatrix().apply {
                setSaturation(0f)
                postConcat(
                    ColorMatrix(
                        floatArrayOf(
                            0.95f, 0f, 0f, 0f, 10f,
                            0f, 0.88f, 0f, 0f, 2f,
                            0f, 0f, 0.72f, 0f, 0f,
                            0f, 0f, 0f, 1f, 0f,
                        ),
                    ),
                )
            },
        )
        // ⚠ INVERSION, pas assombrissement. Baisser la luminosité d'une page
        // blanche donne du gris sale et fatigue autant ; inverser rend un texte
        // clair sur fond sombre, ce que l'œil cherche la nuit. L'inversion
        // retourne aussi les illustrations — c'est le prix connu du procédé, et
        // c'est pourquoi le mode se choisit au lieu d'être imposé.
        NUIT -> ColorMatrixColorFilter(
            ColorMatrix(
                floatArrayOf(
                    -1f, 0f, 0f, 0f, 255f,
                    0f, -1f, 0f, 0f, 255f,
                    0f, 0f, -1f, 0f, 255f,
                    0f, 0f, 0f, 1f, 0f,
                ),
            ),
        )
    }

    companion object {
        fun depuis(cle: String?): ModeLecture =
            entries.firstOrNull { it.cle == cle } ?: CLASSIQUE
    }
}
