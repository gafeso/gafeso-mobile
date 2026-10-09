package com.gafeso.reader

import android.content.Context
import android.graphics.Matrix
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.widget.ImageView

/**
 * Page de lecture zoomable.
 *
 * ⚠ POURQUOI UNE VUE PLUTÔT QU'UNE BIBLIOTHÈQUE. Le lecteur ne peut dépendre
 * d'aucun composant qui prendrait le bitmap en charge : la page déchiffrée ne
 * doit traverser que du code que nous tenons. Une centaine de lignes de matrice
 * contre une dépendance tierce dans le chemin du clair — le choix est vite fait.
 *
 * ⚠ ET LE PIÈGE DU PAGER. Un zoom posé dans un `ViewPager2` rend le document
 * impossible à déplacer : le glissement horizontal part au pager, pas à la
 * page. On coupe donc l'entrée du pager tant que la page est agrandie, et on la
 * rend dès le retour à l'échelle 1.
 */
class ZoomableImageView(
    context: Context,
    private val surZoom: (zoome: Boolean) -> Unit,
) : ImageView(context) {

    private val m = Matrix()
    private var echelle = 1f
    private var dx = 0f
    private var dy = 0f
    private var dernierX = 0f
    private var dernierY = 0f

    private val detecteur = ScaleGestureDetector(
        context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(d: ScaleGestureDetector): Boolean {
                val avant = echelle
                echelle = (echelle * d.scaleFactor).coerceIn(1f, 4f)
                // Le point pincé reste sous les doigts : sans cela le document
                // fuit vers un coin et le geste paraît cassé.
                val f = echelle / avant
                dx = d.focusX - f * (d.focusX - dx)
                dy = d.focusY - f * (d.focusY - dy)
                appliquer()
                return true
            }
        },
    )

    init {
        scaleType = ScaleType.MATRIX
    }

    /** Remet l'échelle à 1 — appelé quand la page change. */
    fun reinitialiser() {
        echelle = 1f; dx = 0f; dy = 0f
        appliquer()
    }

    private fun appliquer() {
        m.reset()
        m.postScale(echelle, echelle)
        m.postTranslate(dx, dy)
        imageMatrix = m
        surZoom(echelle > 1.01f)
    }

    override fun setImageBitmap(bm: android.graphics.Bitmap?) {
        super.setImageBitmap(bm)
        // Cadrage initial : la page occupe la largeur, comme avant le zoom.
        post {
            val d = drawable ?: return@post
            if (d.intrinsicWidth <= 0) return@post
            echelle = 1f
            dx = 0f
            dy = 0f
            m.reset()
            val k = width.toFloat() / d.intrinsicWidth
            m.postScale(k, k)
            imageMatrix = m
            surZoom(false)
        }
    }

    @Suppress("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        detecteur.onTouchEvent(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { dernierX = e.x; dernierY = e.y }
            MotionEvent.ACTION_MOVE -> if (echelle > 1.01f && e.pointerCount == 1) {
                dx += e.x - dernierX
                dy += e.y - dernierY
                dernierX = e.x; dernierY = e.y
                appliquer()
            }
        }
        return true
    }
}
