package com.gafeso.reader

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import io.flutter.plugin.platform.PlatformView

/**
 * Lecteur PDF natif embarqué en PlatformView. Chaîne prouvée sur device (Spike-B), durcie :
 *   licence Ed25519 vérifiée → CEK déballée du keystore → SegmentedBlobReader (mmap/plages,
 *   LRU) → PDFium `FPDF_LoadCustomDocument` → Bitmap peint DANS la vue (pas de round-trip PNG
 *   vers Dart, jamais de clair sur disque) → filigrane incrusté. Recyclage des bitmaps en
 *   fenêtre glissante via ViewPager2 (page visible + adjacentes seulement).
 *
 * Refus AVANT tout rendu si la licence échoue (signature/expiration/liaisons/anti-recul).
 */
class PdfReaderView(
    context: Context,
    params: Map<String, Any?>,
    /** Remonte la page courante à Dart, qui la MÉMORISE SUR L'APPAREIL. */
    private val surPage: (index: Int, total: Int) -> Unit = { _, _ -> },
    /** Prévient la fabrique que cette vue n'est plus vivante. */
    private val surFermeture: () -> Unit = {},
) : PlatformView {

    private val root = FrameLayout(context)
    private var bridge: PdfiumBridge? = null
    private var screenW: Int = context.resources.displayMetrics.widthPixels.coerceAtLeast(360)
    private val watermark = (params["watermark"] as? String) ?: ""
    private var mode = ModeLecture.depuis(params["mode"] as? String)
    private var pager: ViewPager2? = null

    init {
        try {
            setup(context, params)
        } catch (e: Exception) {
            android.util.Log.e("GafesoReader", "setup a échoué", e)
            errorView(context, e.message ?: e.javaClass.simpleName)
        }
    }

    private fun setup(context: Context, p: Map<String, Any?>): Boolean {
        DeviceKeystore.ensureKey()
        // Identifiant que le BACKEND a lié à la licence (et qui sert d'AAD au déballage).
        val deviceId = DeviceIdentity.current(context)
        val res = LicenseVerifier(context).verify(
            bodyJson = p["licenseBody"] as String,
            signatureB64 = p["signature"] as String,
            publicKeyPem = p["licensePublicKey"] as String,
            expectUserId = p["userId"] as String,
            expectDeviceId = deviceId,
            expectTenant = p["tenant"] as String,
        )
        if (!res.ok) { errorView(context, "Licence refusée : ${res.reason}"); return false }

        // CEK déballée par accord ECDH avec la clé privée non-exportable du keystore (EC-KEM).
        val cek = DeviceKeystore.unwrapCek(p["wrappedCek"] as String, deviceId)
        val reader = SegmentedBlobReader(p["blobPath"] as String, cek, 16)
        cek.fill(0) // le keySpec en détient une copie ; on efface notre tampon

        bridge = PdfiumBridge().also { it.open(reader) }
        val pageCount = bridge!!.pageCount()
        // Trace d'exploitation (niveau info, sans secret) : atteste que la CEK a été déballée
        // par le keystore et que PDFium a ouvert le document.
        android.util.Log.i(
            "GafesoReader",
            "document ouvert : $pageCount page(s), CEK déballée via keystore (EC-KEM), " +
                "segments=${reader.nSegs}, cache=${reader.cacheBytes() / 1024}Ko",
        )

        val vp = ViewPager2(context).apply {
            orientation = ViewPager2.ORIENTATION_VERTICAL
            offscreenPageLimit = 1 // fenêtre glissante : visible + 1 de chaque côté
            adapter = PageAdapter(pageCount)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        pager = vp
        root.setBackgroundColor(mode.fond)

        // ⚠ REPRISE À LA DERNIÈRE PAGE LUE. La valeur vient de Dart, qui la tient
        // sur l'appareil — elle n'est jamais demandée au serveur, et ne lui est
        // jamais envoyée. On borne : une progression enregistrée pour un
        // document remplacé depuis pointerait au-delà du document.
        val depart = ((p["pageDepart"] as? Number)?.toInt() ?: 0).coerceIn(0, pageCount - 1)
        if (depart > 0) vp.setCurrentItem(depart, false)

        vp.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                surPage(position, pageCount)
            }
        })
        // La page de départ ne déclenche pas toujours le rappel : on l'annonce.
        surPage(depart, pageCount)

        root.addView(vp)
        return true
    }

    private fun errorView(context: Context, msg: String?) {
        root.removeAllViews()
        root.addView(TextView(context).apply {
            text = msg ?: "Erreur de lecture"
            setPadding(32, 64, 32, 32)
        })
    }

    override fun getView(): View = root

    override fun dispose() {
        bridge?.close(); bridge = null
        pager = null
        surFermeture()
    }

    /** Adaptateur : rend chaque page à la largeur écran, incruste le filigrane, recycle. */
    private inner class PageAdapter(private val count: Int) :
        RecyclerView.Adapter<PageHolder>() {

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PageHolder {
            val iv = ZoomableImageView(parent.context) { zoome ->
                // Tant que la page est agrandie, le pager ne doit pas voler le
                // glissement : sinon le document est inatteignable dès qu'on
                // zoome, ce qui rend le zoom inutile.
                pager?.isUserInputEnabled = !zoome
            }.apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
                )
                colorFilter = mode.filtre()
            }
            return PageHolder(iv)
        }

        override fun getItemCount() = count

        override fun onBindViewHolder(holder: PageHolder, position: Int) {
            val b = bridge ?: return
            val wh = b.pageSize(position)
            val bw = screenW
            val bh = maxOf(1, (wh[1] * bw / wh[0]).toInt())
            val bmp = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
            b.renderInto(position, bmp)
            if (watermark.isNotEmpty()) Watermark.draw(Canvas(bmp), bw, bh, watermark)
            holder.bind(bmp)
        }

        override fun onViewRecycled(holder: PageHolder) {
            holder.recycle() // libère le bitmap hors fenêtre → RAM bornée
        }
    }

    private inner class PageHolder(private val iv: ZoomableImageView) :
        RecyclerView.ViewHolder(iv) {
        private var bmp: Bitmap? = null
        fun bind(b: Bitmap) {
            recycle()
            bmp = b
            iv.colorFilter = mode.filtre()
            iv.setImageBitmap(b)
        }
        fun recycle() {
            iv.reinitialiser()
            iv.setImageDrawable(null)
            bmp?.recycle()
            bmp = null
        }
    }

    /**
     * Change le mode de lecture sans rouvrir le document.
     *
     * ⚠ Rouvrir coûterait une vérification de licence, un déballage de CEK et
     * un re-rendu de la page — pour un changement qui ne touche QUE l'affichage.
     * On repeint, et la position de lecture est conservée.
     */
    fun changerMode(cle: String?) {
        mode = ModeLecture.depuis(cle)
        root.setBackgroundColor(mode.fond)
        pager?.adapter?.notifyDataSetChanged()
    }
}
