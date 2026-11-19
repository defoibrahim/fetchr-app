#ifndef FETCHR_FFMPEG_BRIDGE_H
#define FETCHR_FFMPEG_BRIDGE_H

#include <stdbool.h>

// Plain C so FetchrPython.c and Swift can call it; FFmpegKit's headers stay in FFmpegBridge.m.

// When true, every fetchr_ff_run holds one process-wide lock for the whole session.
extern bool fetchr_ff_serialize;

// Runs ffmpeg, or ffprobe when probe != 0, synchronously on the calling thread. argv excludes the program name.
// *output is a malloc'd UTF-8 string (free it with free()): ffmpeg's log, or what ffprobe would print to stdout,
// which is empty when argv has its own -o. Returns the exit code, 255 when cancelled.
int fetchr_ff_run(int probe, const char *const *argv, int argc, const char *task_id, char **output);

// Cancels every session running, or waiting for the lock, under task_id, and every later one until
// fetchr_ff_forget(task_id); those return 255 without running.
void fetchr_ff_cancel(const char *task_id);

// Clears the cancel mark, for when the task has ended or is retried under the same id.
void fetchr_ff_forget(const char *task_id);

#endif
