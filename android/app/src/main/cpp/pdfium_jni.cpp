// Pont JNI PDFium (production) — porté du Spike-B, prouvé sur device réel.
//
// PDFium ne reçoit JAMAIS de chemin de fichier ni de buffer complet : on lui fournit un
// FPDF_FILEACCESS dont le callback m_GetBlock remonte en JNI vers la source déchiffrante
// Kotlin (SegmentedBlobReader.readRange), qui déchiffre à la demande, segment par segment,
// en mémoire. Le rendu se fait directement dans un Bitmap Android. Aucun clair sur disque,
// aucun round-trip PNG vers Dart (le Bitmap est peint dans la PlatformView native).

#include <jni.h>
#include <android/bitmap.h>
#include <android/log.h>
#include <cstring>

#include "fpdfview.h"

#define LOG_TAG "GafesoPdfium"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static JavaVM* g_vm = nullptr;

struct DocCtx {
    FPDF_FILEACCESS fa;
    jobject reader;        // global ref vers SegmentedBlobReader
    jmethodID readRange;   // ByteArray readRange(long position, int size)
    FPDF_DOCUMENT doc;
};

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

static JNIEnv* getEnv() {
    JNIEnv* env = nullptr;
    if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) return env;
    if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) return env;
    return nullptr;
}

static int getBlock(void* param, unsigned long position, unsigned char* pBuf, unsigned long size) {
    DocCtx* ctx = reinterpret_cast<DocCtx*>(param);
    JNIEnv* env = getEnv();
    if (!env) return 0;
    jbyteArray arr = reinterpret_cast<jbyteArray>(
        env->CallObjectMethod(ctx->reader, ctx->readRange, (jlong)position, (jint)size));
    if (!arr) return 0;
    jsize n = env->GetArrayLength(arr);
    jsize copy = (n < (jsize)size) ? n : (jsize)size;
    env->GetByteArrayRegion(arr, 0, copy, reinterpret_cast<jbyte*>(pBuf));
    env->DeleteLocalRef(arr);
    return (copy == (jsize)size) ? 1 : 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_gafeso_reader_PdfiumBridge_nativeInit(JNIEnv*, jobject) {
    FPDF_InitLibrary();
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_gafeso_reader_PdfiumBridge_nativeOpen(JNIEnv* env, jobject, jobject reader, jlong fileLen) {
    DocCtx* ctx = new DocCtx();
    ctx->reader = env->NewGlobalRef(reader);
    jclass cls = env->GetObjectClass(reader);
    ctx->readRange = env->GetMethodID(cls, "readRange", "(JI)[B");
    if (!ctx->readRange) { LOGE("readRange introuvable"); return 0; }
    ctx->fa.m_FileLen = (unsigned long)fileLen;
    ctx->fa.m_GetBlock = getBlock;
    ctx->fa.m_Param = ctx;
    ctx->doc = FPDF_LoadCustomDocument(&ctx->fa, nullptr);
    if (!ctx->doc) {
        LOGE("FPDF_LoadCustomDocument a échoué, err=%lu", FPDF_GetLastError());
        env->DeleteGlobalRef(ctx->reader);
        delete ctx;
        return 0;
    }
    return reinterpret_cast<jlong>(ctx);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_gafeso_reader_PdfiumBridge_nativePageCount(JNIEnv*, jobject, jlong handle) {
    return FPDF_GetPageCount(reinterpret_cast<DocCtx*>(handle)->doc);
}

extern "C" JNIEXPORT jfloatArray JNICALL
Java_com_gafeso_reader_PdfiumBridge_nativePageSize(JNIEnv* env, jobject, jlong handle, jint index) {
    DocCtx* ctx = reinterpret_cast<DocCtx*>(handle);
    FPDF_PAGE page = FPDF_LoadPage(ctx->doc, index);
    float wh[2] = { (float)FPDF_GetPageWidth(page), (float)FPDF_GetPageHeight(page) };
    FPDF_ClosePage(page);
    jfloatArray out = env->NewFloatArray(2);
    env->SetFloatArrayRegion(out, 0, 2, wh);
    return out;
}

// Rend la page `index` à l'échelle mobile DANS le Bitmap Android fourni (RGBA_8888).
extern "C" JNIEXPORT jint JNICALL
Java_com_gafeso_reader_PdfiumBridge_nativeRenderPage(JNIEnv* env, jobject, jlong handle,
                                                     jint index, jobject bitmap) {
    DocCtx* ctx = reinterpret_cast<DocCtx*>(handle);
    AndroidBitmapInfo info;
    if (AndroidBitmap_getInfo(env, bitmap, &info) != ANDROID_BITMAP_RESULT_SUCCESS) return -1;
    if (info.format != ANDROID_BITMAP_FORMAT_RGBA_8888) return -2;
    void* pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, bitmap, &pixels) != ANDROID_BITMAP_RESULT_SUCCESS) return -3;

    int bw = info.width, bh = info.height;
    FPDF_BITMAP bm = FPDFBitmap_CreateEx(bw, bh, FPDFBitmap_BGRA, pixels, info.stride);
    FPDFBitmap_FillRect(bm, 0, 0, bw, bh, 0xFFFFFFFF);
    FPDF_PAGE page = FPDF_LoadPage(ctx->doc, index);
    FPDF_RenderPageBitmap(bm, page, 0, 0, bw, bh, 0, 0);
    FPDF_ClosePage(page);
    FPDFBitmap_Destroy(bm);

    // Android RGBA_8888 (R,G,B,A) vs PDFium BGRA (B,G,R,A) → échanger R et B.
    uint8_t* p = reinterpret_cast<uint8_t*>(pixels);
    for (int y = 0; y < bh; ++y) {
        uint8_t* row = p + (size_t)y * info.stride;
        for (int x = 0; x < bw; ++x) { uint8_t t = row[x*4]; row[x*4] = row[x*4+2]; row[x*4+2] = t; }
    }
    AndroidBitmap_unlockPixels(env, bitmap);
    return 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_gafeso_reader_PdfiumBridge_nativeClose(JNIEnv* env, jobject, jlong handle) {
    DocCtx* ctx = reinterpret_cast<DocCtx*>(handle);
    if (!ctx) return;
    FPDF_CloseDocument(ctx->doc);
    env->DeleteGlobalRef(ctx->reader);
    delete ctx;
}
