package com.gafeso.reader

import android.graphics.Bitmap

/**
 * Pont Kotlin ↔ natif PDFium. Le natif rappelle `reader.readRange(...)` (upcall JNI) pour
 * chaque plage — aucun chemin de fichier, aucun buffer complet ne traverse la frontière.
 * Le rendu se fait dans un Bitmap fourni par l'appelant (permet le recyclage en fenêtre
 * glissante côté PdfReaderView).
 */
class PdfiumBridge {
    companion object { init { System.loadLibrary("pdfium_jni") } }

    private external fun nativeInit()
    private external fun nativeOpen(reader: SegmentedBlobReader, fileLen: Long): Long
    private external fun nativePageCount(handle: Long): Int
    private external fun nativePageSize(handle: Long, index: Int): FloatArray
    private external fun nativeRenderPage(handle: Long, index: Int, bitmap: Bitmap): Int
    private external fun nativeClose(handle: Long)

    private var handle: Long = 0L

    fun open(reader: SegmentedBlobReader) {
        nativeInit()
        handle = nativeOpen(reader, reader.fileLen)
        check(handle != 0L) { "FPDF_LoadCustomDocument a échoué (voir logcat GafesoPdfium)" }
    }

    fun pageCount(): Int = nativePageCount(handle)

    /** Dimensions (points) de la page — pour dimensionner le Bitmap à la largeur écran. */
    fun pageSize(index: Int): FloatArray = nativePageSize(handle, index)

    /** Rend la page dans le Bitmap fourni (déjà dimensionné). Le natif remplit les pixels. */
    fun renderInto(index: Int, bitmap: Bitmap) {
        val rc = nativeRenderPage(handle, index, bitmap)
        check(rc == 0) { "nativeRenderPage rc=$rc" }
    }

    fun close() { if (handle != 0L) { nativeClose(handle); handle = 0L } }
}
