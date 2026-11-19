#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <os/log.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../FFmpeg/FFmpegBridge.h"
#include "FetchrPython.h"
#include "JavaScriptEval.h"

static _Atomic(fetchr_emit_fn) emit_fn = NULL;
static PyObject *api_module = NULL;

static char *unicode_copy(PyObject *text) {
  const char *utf8 = text ? PyUnicode_AsUTF8(text) : NULL;
  if (!utf8) PyErr_Clear();
  return utf8 ? strdup(utf8) : NULL;
}

// Formats the raised exception with its traceback and clears it; falls back to str(exc).
static char *exception_text(void) {
  PyObject *exc = PyErr_GetRaisedException();
  if (!exc) return strdup("unknown Python error");
  PyObject *traceback = PyImport_ImportModule("traceback");
  PyObject *lines = traceback ? PyObject_CallMethod(traceback, "format_exception", "O", exc) : NULL;
  PyObject *empty = lines ? PyUnicode_FromString("") : NULL;
  PyObject *joined = empty ? PyUnicode_Join(empty, lines) : NULL;
  if (!joined) PyErr_Clear();
  char *text = unicode_copy(joined);
  if (!text) {
    PyObject *plain = PyObject_Str(exc);
    if (!plain) PyErr_Clear();
    text = unicode_copy(plain);
    Py_XDECREF(plain);
  }
  Py_XDECREF(joined);
  Py_XDECREF(empty);
  Py_XDECREF(lines);
  Py_XDECREF(traceback);
  Py_DECREF(exc);
  return text ? text : strdup("unknown Python error");
}

static PyObject *fetchr_emit(PyObject *self, PyObject *args) {
  const char *task_id;
  const char *json;
  if (!PyArg_ParseTuple(args, "ss", &task_id, &json)) return NULL;
  fetchr_emit_fn fn = atomic_load(&emit_fn);
  if (!fn) Py_RETURN_NONE;
  // The pointers borrow from the args tuple's str objects, which outlive this call; fn copies them before returning.
  Py_BEGIN_ALLOW_THREADS
  fn(task_id, json);
  Py_END_ALLOW_THREADS
  Py_RETURN_NONE;
}

static PyObject *fetchr_js_eval_method(PyObject *self, PyObject *args) {
  const char *source;
  if (!PyArg_ParseTuple(args, "s", &source)) return NULL;
  // The tuple's str may not be touched without the GIL, so JSC gets its own copy.
  char *copy = strdup(source);
  if (!copy) return PyErr_NoMemory();
  char *error = NULL;
  char *result;
  Py_BEGIN_ALLOW_THREADS
  result = fetchr_js_eval(copy, &error);
  Py_END_ALLOW_THREADS
  free(copy);
  if (!result) {
    PyErr_SetString(PyExc_RuntimeError, error ? error : "JavaScript evaluation failed");
    free(error);
    return NULL;
  }
  PyObject *text = PyUnicode_DecodeUTF8(result, (Py_ssize_t)strlen(result), "replace");
  free(result);
  return text;
}

static void free_argv(char **argv, Py_ssize_t count) {
  for (Py_ssize_t i = 0; i < count; i++) free(argv[i]);
  free(argv);
}

// The GIL is released for the whole session, so argv and the task id are copied out of their str objects first.
static PyObject *ff_run(PyObject *args, int probe) {
  PyObject *list;
  const char *task_arg;
  if (!PyArg_ParseTuple(args, "Os", &list, &task_arg)) return NULL;
  if (PyUnicode_Check(list)) {
    PyErr_SetString(PyExc_TypeError, "argv must be a list of str, not a str");
    return NULL;
  }
  PyObject *seq = PySequence_Fast(list, "argv must be a list of str");
  if (!seq) return NULL;
  Py_ssize_t count = PySequence_Fast_GET_SIZE(seq);
  char **argv = calloc((size_t)(count ? count : 1), sizeof(char *));
  char *task = strdup(task_arg);
  if (!argv || !task) {
    free(argv);
    free(task);
    Py_DECREF(seq);
    return PyErr_NoMemory();
  }
  for (Py_ssize_t i = 0; i < count; i++) {
    PyObject *item = PySequence_Fast_GET_ITEM(seq, i);
    const char *utf8 = PyUnicode_Check(item) ? PyUnicode_AsUTF8(item) : NULL;
    if (!utf8 && !PyErr_Occurred()) PyErr_SetString(PyExc_TypeError, "argv must be a list of str");
    if (utf8 && !(argv[i] = strdup(utf8))) PyErr_NoMemory();
    if (!argv[i]) {
      free_argv(argv, count);
      free(task);
      Py_DECREF(seq);
      return NULL;
    }
  }
  Py_DECREF(seq);

  char *out = NULL;
  int rc;
  Py_BEGIN_ALLOW_THREADS
  rc = fetchr_ff_run(probe, (const char *const *)argv, (int)count, task, &out);
  Py_END_ALLOW_THREADS
  free_argv(argv, count);
  free(task);
  PyObject *text = PyUnicode_DecodeUTF8(out ? out : "", out ? (Py_ssize_t)strlen(out) : 0, "replace");
  free(out);
  return text ? Py_BuildValue("(iN)", rc, text) : NULL;
}

static PyObject *fetchr_ffmpeg(PyObject *self, PyObject *args) { return ff_run(args, 0); }

static PyObject *fetchr_ffprobe(PyObject *self, PyObject *args) { return ff_run(args, 1); }

static PyObject *task_call(PyObject *args, void (*call)(const char *)) {
  const char *task_arg;
  if (!PyArg_ParseTuple(args, "s", &task_arg)) return NULL;
  char *task = strdup(task_arg);
  if (!task) return PyErr_NoMemory();
  Py_BEGIN_ALLOW_THREADS
  call(task);
  Py_END_ALLOW_THREADS
  free(task);
  Py_RETURN_NONE;
}

static PyObject *fetchr_cancel_session(PyObject *self, PyObject *args) { return task_call(args, fetchr_ff_cancel); }

static PyObject *fetchr_forget_session(PyObject *self, PyObject *args) { return task_call(args, fetchr_ff_forget); }

// Python's own stdout goes to the default log; this one is filterable as subsystem com.defo.fetchr, category python.
static PyObject *fetchr_log(PyObject *self, PyObject *args) {
  static os_log_t log = NULL;
  const char *message;
  if (!PyArg_ParseTuple(args, "s", &message)) return NULL;
  if (!log) log = os_log_create("com.defo.fetchr", "python");
  os_log(log, "%{public}s", message);
  Py_RETURN_NONE;
}

static PyMethodDef fetchr_methods[] = {
    {"js_eval", fetchr_js_eval_method, METH_VARARGS, NULL},
    {"emit", fetchr_emit, METH_VARARGS, NULL},
    {"log", fetchr_log, METH_VARARGS, NULL},
    {"ffmpeg", fetchr_ffmpeg, METH_VARARGS, NULL},
    {"ffprobe", fetchr_ffprobe, METH_VARARGS, NULL},
    {"cancel_session", fetchr_cancel_session, METH_VARARGS, NULL},
    {"forget_session", fetchr_forget_session, METH_VARARGS, NULL},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef fetchr_module = {
    PyModuleDef_HEAD_INIT, "_fetchr", NULL, -1, fetchr_methods,
};

static PyObject *init_fetchr(void) { return PyModule_Create(&fetchr_module); }

static int config_failed(PyInitConfig *config, char **error_out) {
  const char *message = NULL;
  PyInitConfig_GetError(config, &message);
  *error_out = strdup(message ? message : "Python configuration failed");
  PyInitConfig_Free(config);
  return -1;
}

static int configure(PyInitConfig *config, const char *home, const char *const *paths, int path_count,
                     const char *ytdlp_dir) {
  if (PyInitConfig_SetStr(config, "home", home) < 0) return -1;
  if (PyInitConfig_SetInt(config, "utf8_mode", 1) < 0) return -1;
  if (PyInitConfig_SetInt(config, "buffered_stdio", 0) < 0) return -1;
  if (PyInitConfig_SetInt(config, "use_system_logger", 1) < 0) return -1;
  // The bundle is read-only: the stdlib and app_packages ship their bytecode, fetchr_bridge compiles at import.
  if (PyInitConfig_SetInt(config, "write_bytecode", 0) < 0) return -1;
  if (PyInitConfig_SetStrList(config, "module_search_paths", (size_t)path_count, (char *const *)paths) < 0) return -1;
  if (PyInitConfig_SetInt(config, "module_search_paths_set", 1) < 0) return -1;
  if (PyInitConfig_SetInt(config, "install_signal_handlers", 1) < 0) return -1;
  // fetchr_bridge.selftest reads it as sys._xoptions["fetchr_ytdlp_dir"]; no process-wide environment change.
  if (ytdlp_dir) {
    char *option = NULL;
    if (asprintf(&option, "fetchr_ytdlp_dir=%s", ytdlp_dir) < 0) return -1;
    char *options[] = {option};
    int status = PyInitConfig_SetStrList(config, "xoptions", 1, options);
    free(option);
    if (status < 0) return -1;
  }
  return 0;
}

int fetchr_py_init(const char *home, const char *const *paths, int path_count, const char *ytdlp_dir,
                   char **error_out) {
  *error_out = NULL;
  if (PyImport_AppendInittab("_fetchr", init_fetchr) < 0) {
    *error_out = strdup("could not register the _fetchr module");
    return -1;
  }
  PyInitConfig *config = PyInitConfig_Create();
  if (!config) {
    *error_out = strdup("out of memory creating the Python configuration");
    return -1;
  }
  if (configure(config, home, paths, path_count, ytdlp_dir) < 0) return config_failed(config, error_out);
  if (Py_InitializeFromInitConfig(config) < 0) return config_failed(config, error_out);
  PyInitConfig_Free(config);

  int status = 0;
  api_module = PyImport_ImportModule("fetchr_bridge.api");
  PyObject *booted = api_module ? PyObject_CallMethod(api_module, "boot", NULL) : NULL;
  if (!booted) {
    *error_out = exception_text();
    status = -1;
  }
  Py_XDECREF(booted);
  // Hands the GIL to whichever thread calls next; this boot thread never takes it again.
  PyEval_SaveThread();
  return status;
}

char *fetchr_py_call(const char *name, const char *payload_json, char **error_out) {
  *error_out = NULL;
  if (!Py_IsInitialized() || !api_module) {
    *error_out = strdup("Python is not running");
    return NULL;
  }
  PyGILState_STATE gil = PyGILState_Ensure();
  char *out = NULL;
  PyObject *reply = PyObject_CallMethod(api_module, "call", "ss", name, payload_json);
  if (reply && PyUnicode_Check(reply)) out = unicode_copy(reply);
  if (!out) *error_out = PyErr_Occurred() ? exception_text() : strdup("fetchr_bridge.api.call returned no text");
  Py_XDECREF(reply);
  PyGILState_Release(gil);
  return out;
}

void fetchr_py_free(char *p) { free(p); }

void fetchr_py_set_emit(fetchr_emit_fn fn) { atomic_store(&emit_fn, fn); }
