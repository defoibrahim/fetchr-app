#ifndef FETCHR_JAVASCRIPT_EVAL_H
#define FETCHR_JAVASCRIPT_EVAL_H

// Evaluates source in a fresh JavaScriptCore context and returns the completion value as a malloc'd UTF-8 string.
// On a JS exception returns NULL with *error_out = malloc'd "<name>: <message>". Free both with free().
char *fetchr_js_eval(const char *source, char **error_out);

#endif
