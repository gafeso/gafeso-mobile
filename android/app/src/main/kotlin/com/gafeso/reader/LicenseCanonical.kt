package com.gafeso.reader

import org.json.JSONArray
import org.json.JSONObject

/**
 * Canonicalisation JSON identique au backend (`license-crypto.ts:canonicalize`) : clés triées
 * récursivement, `JSON.stringify` pour les primitives. Serveur et app signent/vérifient donc
 * exactement les mêmes octets. Partagée par LicenseVerifier (vérif) et SeedProvisioner (seed).
 */
object LicenseCanonical {
    fun canonicalize(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> value.keys().asSequence().sorted().toList()
            .joinToString(",", "{", "}") { k -> "${jsonString(k)}:${canonicalize(value.get(k))}" }
        is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { canonicalize(value.get(it)) }
        is String -> jsonString(value)
        is Boolean -> value.toString()
        is Int, is Long -> value.toString()
        is Double -> if (value % 1.0 == 0.0) value.toLong().toString() else value.toString()
        else -> jsonString(value.toString())
    }

    /** Équivalent de JSON.stringify(string) : guillemets + échappements JS standard. */
    fun jsonString(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) when (c) {
            '"' -> sb.append("\\\"")
            '\\' -> sb.append("\\\\")
            '\n' -> sb.append("\\n")
            '\r' -> sb.append("\\r")
            '\t' -> sb.append("\\t")
            else -> if (c < ' ') sb.append("\\u%04x".format(c.code)) else sb.append(c)
        }
        return sb.append("\"").toString()
    }
}
