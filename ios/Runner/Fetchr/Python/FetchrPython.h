#ifndef FETCHR_PYTHON_H
#define FETCHR_PYTHON_H

// The only Python surface Swift sees; Python.h stays out of the bridging header.

typedef void (*fetchr_emit_fn)(const char *task_id, const char *json);

// Returns 0, or -1 with *error_out set to a malloc'd message (free it with fetchr_py_free). `ytdlp_dir` is the
// installed yt-dlp update on `paths`, or NULL for the bundled copy; Python reads it as sys._xoptions.
int fetchr_py_init(const char *home, const char *const *paths, int path_count, const char *ytdlp_dir,
                   char **error_out);

// Returns Python's malloc'd JSON envelope, {"ok":true,"value":...} or {"ok":false,"hint":...,"message":...},
// or NULL with *error_out set to a malloc'd message when Python could not reply. Free both with fetchr_py_free.
// Takes the GIL, so never call it on the main thread.
char *fetchr_py_call(const char *name, const char *payload_json, char **error_out);

void fetchr_py_free(char *p);

void fetchr_py_set_emit(fetchr_emit_fn fn);

#endif
