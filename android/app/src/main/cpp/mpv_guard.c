// JNI side of MpvGuard.kt. libmpv is already loaded by media_kit through Dart FFI, so it is looked up, not linked:
// when it was never loaded there are no players to detach.
#include <dlfcn.h>
#include <jni.h>
#include <stddef.h>
#include <stdint.h>

typedef void (*set_wakeup_callback_fn)(void *ctx, void (*cb)(void *), void *d);
typedef int (*command_string_fn)(void *ctx, const char *args);

// Untrack runs before media_kit's own dispose clears the callback, with a platform-channel round trip in between;
// clearing it here leaves no window where an untracked player still points at Dart. Dart clears it again later.
JNIEXPORT void JNICALL Java_com_defo_fetchr_MpvNative_clearWakeup(JNIEnv *env, jclass cls, jlong handle) {
    (void) env;
    (void) cls;
    void *lib = dlopen("libmpv.so", RTLD_NOW | RTLD_NOLOAD);
    if (lib == NULL) return;
    set_wakeup_callback_fn set_wakeup_callback = (set_wakeup_callback_fn) dlsym(lib, "mpv_set_wakeup_callback");
    if (set_wakeup_callback != NULL) set_wakeup_callback((void *) (intptr_t) handle, NULL, NULL);
    dlclose(lib);
}

JNIEXPORT void JNICALL Java_com_defo_fetchr_MpvNative_detach(JNIEnv *env, jclass cls, jlongArray handles) {
    (void) cls;
    void *lib = dlopen("libmpv.so", RTLD_NOW | RTLD_NOLOAD);
    if (lib == NULL) return;
    set_wakeup_callback_fn set_wakeup_callback = (set_wakeup_callback_fn) dlsym(lib, "mpv_set_wakeup_callback");
    command_string_fn command_string = (command_string_fn) dlsym(lib, "mpv_command_string");
    jlong *ctx = (*env)->GetLongArrayElements(env, handles, NULL);
    if (set_wakeup_callback != NULL && command_string != NULL && ctx != NULL) {
        jsize count = (*env)->GetArrayLength(env, handles);
        for (jsize i = 0; i < count; i++) {
            void *player = (void *) (intptr_t) ctx[i];
            // mpv holds its wakeup lock while it runs the callback, so once this returns none is in flight.
            set_wakeup_callback(player, NULL, NULL);
            // What media_kit itself uses to stop a player; mpv_terminate_destroy here would race Dart's own dispose.
            command_string(player, "quit");
        }
    }
    if (ctx != NULL) (*env)->ReleaseLongArrayElements(env, handles, ctx, JNI_ABORT);
    dlclose(lib);
}
