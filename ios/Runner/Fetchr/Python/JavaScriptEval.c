#include "JavaScriptEval.h"

#include <JavaScriptCore/JavaScriptCore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *utf8_copy(JSStringRef string) {
  size_t capacity = JSStringGetMaximumUTF8CStringSize(string);
  char *out = malloc(capacity);
  if (out) JSStringGetUTF8CString(string, out, capacity);
  return out;
}

static char *value_text(JSContextRef ctx, JSValueRef value) {
  JSStringRef string = JSValueToStringCopy(ctx, value, NULL);
  if (!string) return NULL;
  char *out = utf8_copy(string);
  JSStringRelease(string);
  return out;
}

static char *property_text(JSContextRef ctx, JSObjectRef object, const char *name) {
  JSStringRef key = JSStringCreateWithUTF8CString(name);
  JSValueRef value = JSObjectGetProperty(ctx, object, key, NULL);
  JSStringRelease(key);
  if (!value || JSValueIsUndefined(ctx, value)) return NULL;
  return value_text(ctx, value);
}

static char *exception_text(JSContextRef ctx, JSValueRef exception) {
  char *name = NULL;
  char *message = NULL;
  if (JSValueIsObject(ctx, exception)) {
    JSObjectRef object = JSValueToObject(ctx, exception, NULL);
    if (object) {
      name = property_text(ctx, object, "name");
      message = property_text(ctx, object, "message");
    }
  }
  char *text = NULL;
  if (name && message) {
    size_t size = strlen(name) + strlen(message) + 3;
    text = malloc(size);
    if (text) snprintf(text, size, "%s: %s", name, message);
  } else {
    text = value_text(ctx, exception);
  }
  free(name);
  free(message);
  return text ? text : strdup("JavaScript error");
}

char *fetchr_js_eval(const char *source, char **error_out) {
  *error_out = NULL;
  JSContextGroupRef group = JSContextGroupCreate();
  JSGlobalContextRef ctx = JSGlobalContextCreateInGroup(group, NULL);
  JSStringRef script = JSStringCreateWithUTF8CString(source);
  JSValueRef exception = NULL;
  JSValueRef result = JSEvaluateScript(ctx, script, NULL, NULL, 1, &exception);

  char *out = NULL;
  if (exception || !result) {
    *error_out = exception ? exception_text(ctx, exception) : strdup("JavaScript evaluation failed");
  } else {
    out = value_text(ctx, result);
    if (!out) *error_out = strdup("JavaScript result could not be converted to a string");
  }
  JSStringRelease(script);
  JSGlobalContextRelease(ctx);
  JSContextGroupRelease(group);
  return out;
}
