package com.gafeso.reader

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Fabrique la PlatformView du lecteur.
 *
 * ⚠ ELLE RETIENT LA VUE VIVANTE. Un seul document est ouvert à la fois, et le
 * changement de mode de lecture doit atteindre CETTE vue — une PlatformView ne
 * reçoit pas de nouveaux `creationParams` quand Dart se reconstruit. La
 * référence est relâchée à la fermeture du lecteur, pour ne pas retenir un
 * document fermé.
 */
class PdfReaderFactory(
    private val surPage: (index: Int, total: Int) -> Unit = { _, _ -> },
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    var vueCourante: PdfReaderView? = null
        private set

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = (args as? Map<String, Any?>) ?: emptyMap()
        val vue = PdfReaderView(context, params, surPage) { vueCourante = null }
        vueCourante = vue
        return vue
    }
}
