package com.gafeso.reader

import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Source déchiffrante AEAD segmentée — port fidèle du `crypto_util.SegmentedStore` du banc.
 *
 * Contrainte d'archi héritée de l'addendum Spike-A : le blob chiffré est **mmap** (MappedByteBuffer,
 * read-only, page-cache réclamable) — JAMAIS lu en entier. Seules les pages des segments touchés
 * faultent. Le clair résident est borné par un cache LRU de `lruMax` segments (~256 Ko).
 *
 * Format (identique au chiffreur Python) :
 *   MAGIC("GAFS1\0") | u32LE headerLen | headerJson{file_len,seg_size,n_segs}
 *   | N * [ nonce(12) | ciphertext | tag(16) ]
 * AAD par segment = <QQQ> little-endian (index, seg_size, file_len). AES-256-GCM.
 *
 * La CEK (32 o) est INJECTÉE (déballée du keystore via la licence) — le format est
 * identique à celui du backend (interop TS→Kotlin prouvée par vecteur croisé).
 */
class SegmentedBlobReader(path: String, key: ByteArray, private val lruMax: Int = 16) {

    companion object {
        private const val NONCE = 12
        private const val TAG = 16
        private val MAGIC = byteArrayOf('G'.code.toByte(), 'A'.code.toByte(), 'F'.code.toByte(),
            'S'.code.toByte(), '1'.code.toByte(), 0)
    }

    val fileLen: Long
    val segSize: Int
    val nSegs: Int
    private val bodyOff: Int
    private val map: MappedByteBuffer
    private val keySpec = SecretKeySpec(key, "AES")

    // Métriques (miroir du banc) — pour le rapport de mesure.
    val touched = HashSet<Int>()
    var decryptCalls = 0; private set

    // Cache LRU clair : borne le clair résident, indépendant de la taille du fichier.
    private val cache = object : LinkedHashMap<Int, ByteArray>(lruMax + 1, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Int, ByteArray>) = size > lruMax
    }

    init {
        val f = File(path)
        val raf = RandomAccessFile(f, "r")
        val ch = raf.channel
        // mmap read-only de tout le fichier : l'adresse virtuelle existe, mais rien n'est
        // résident tant qu'on ne touche pas les pages (contrainte "jamais entier").
        map = ch.map(FileChannel.MapMode.READ_ONLY, 0, f.length())
        map.order(ByteOrder.LITTLE_ENDIAN)

        val magic = ByteArray(6); for (i in 0 until 6) magic[i] = map.get(i)
        require(magic.contentEquals(MAGIC)) { "magic GAFS1 attendu" }
        val headerLen = map.getInt(6)
        val hb = ByteArray(headerLen); for (i in 0 until headerLen) hb[i] = map.get(10 + i)
        val h = JSONObject(String(hb, Charsets.UTF_8))
        fileLen = h.getLong("file_len")
        segSize = h.getInt("seg_size")
        nSegs = h.getInt("n_segs")
        bodyOff = 10 + headerLen
    }

    private fun encSegLen(k: Int): Int {
        val ptLen = minOf(segSize.toLong(), fileLen - k.toLong() * segSize).toInt()
        return NONCE + ptLen + TAG
    }

    private fun segStart(k: Int): Int = bodyOff + k * (NONCE + segSize + TAG)

    /** Déchiffre le segment k (avec cache LRU). Ne matérialise que ce segment. */
    private fun decryptSeg(k: Int): ByteArray {
        cache[k]?.let { return it }
        val start = segStart(k)
        val encLen = encSegLen(k)
        val nonce = ByteArray(NONCE)
        for (i in 0 until NONCE) nonce[i] = map.get(start + i)
        val ctLen = encLen - NONCE
        val ct = ByteArray(ctLen)
        for (i in 0 until ctLen) ct[i] = map.get(start + NONCE + i)

        val aad = ByteBuffer.allocate(24).order(ByteOrder.LITTLE_ENDIAN)
            .putLong(k.toLong()).putLong(segSize.toLong()).putLong(fileLen).array()

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, keySpec, GCMParameterSpec(TAG * 8, nonce))
        cipher.updateAAD(aad)
        val pt = cipher.doFinal(ct)   // JCE : ct inclut le tag en fin, comme le chiffreur Python

        decryptCalls++
        touched.add(k)
        cache[k] = pt
        return pt
    }

    /**
     * Sert [position, position+size) en ne déchiffrant que les segments couvrants.
     * Appelé depuis le callback natif m_GetBlock de PDFium (upcall JNI).
     */
    fun readRange(position: Long, size: Int): ByteArray {
        if (position >= fileLen) return ByteArray(0)
        val n = minOf(size.toLong(), fileLen - position).toInt()
        val first = (position / segSize).toInt()
        val last = ((position + n - 1) / segSize).toInt()
        val out = ByteArray(n)
        var written = 0
        for (k in first..last) {
            val seg = decryptSeg(k)
            val segStartByte = k.toLong() * segSize
            val lo = (maxOf(position, segStartByte) - segStartByte).toInt()
            val hi = (minOf(position + n, segStartByte + seg.size) - segStartByte).toInt()
            System.arraycopy(seg, lo, out, written, hi - lo)
            written += (hi - lo)
        }
        return out
    }

    fun cacheBytes(): Int = cache.values.sumOf { it.size }
}
