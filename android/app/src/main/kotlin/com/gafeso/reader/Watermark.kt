package com.gafeso.reader

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint

/** Filigrane incrusté DANS le bitmap de page (nom/tenant/horodatage), répété en diagonale. */
object Watermark {
    fun draw(canvas: Canvas, w: Int, h: Int, text: String) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(38, 0, 0, 0) // gris très translucide, lisible sans gêner
            textSize = w / 26f
            isFakeBoldText = true
        }
        val step = (w / 2.2f)
        canvas.save()
        canvas.rotate(-30f, w / 2f, h / 2f)
        var y = -h.toFloat()
        while (y < h * 2) {
            var x = -w.toFloat()
            while (x < w * 2) {
                canvas.drawText(text, x, y, paint)
                x += step * 2
            }
            y += step
        }
        canvas.restore()
    }
}
