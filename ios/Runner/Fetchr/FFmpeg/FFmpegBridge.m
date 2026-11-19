#import <Foundation/Foundation.h>
#import <ffmpegkit/FFmpegKit.h>
#import <ffmpegkit/FFmpegKitConfig.h>
#import <ffmpegkit/FFprobeSession.h>
#include <stdlib.h>
#include <string.h>

#include "FFmpegBridge.h"

bool fetchr_ff_serialize = true;

static const int kCancelledCode = 255;
static const int kCancelRetries = 30;
static const int64_t kCancelRetryNs = 100 * NSEC_PER_MSEC;

@interface FetchrFFRun : NSObject
@property(nonatomic, strong) id<Session> session;
@property(atomic) BOOL cancelled;
@property(nonatomic) BOOL finished;
@end

@implementation FetchrFFRun
@end

// The serialize lock is a condition so a cancel can wake a run that is still waiting for its turn.
static NSCondition *gate(void) {
  static NSCondition *condition;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ condition = [NSCondition new]; });
  return condition;
}

static BOOL gate_busy = NO;

// Returns NO, without taking the turn, when the run was cancelled while it waited.
static BOOL gate_enter(FetchrFFRun *run) {
  NSCondition *condition = gate();
  [condition lock];
  while (gate_busy && !run.cancelled) [condition wait];
  BOOL go = !run.cancelled;
  if (go) gate_busy = YES;
  [condition unlock];
  return go;
}

static void gate_leave(void) {
  NSCondition *condition = gate();
  [condition lock];
  gate_busy = NO;
  [condition broadcast];
  [condition unlock];
}

static void gate_wake(void) {
  NSCondition *condition = gate();
  [condition lock];
  [condition broadcast];
  [condition unlock];
}

// Task id to its runs; every access holds @synchronized on the dictionary.
static NSMutableDictionary<NSString *, NSMutableArray<FetchrFFRun *> *> *all_runs(void) {
  static NSMutableDictionary *runs;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ runs = [NSMutableDictionary new]; });
  return runs;
}

// Tasks cancelled and not yet forgotten. Guarded by the same @synchronized(all_runs()) as the runs, so a run
// registering and a cancel marking cannot interleave: a run either is in the list the cancel stops or sees the mark.
static NSMutableSet<NSString *> *cancelled_tasks(void) {
  static NSMutableSet *tasks;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ tasks = [NSMutableSet new]; });
  return tasks;
}

static char *copy_bytes(NSData *data) {
  char *out = malloc(data.length + 1);
  if (!out) return NULL;
  memcpy(out, data.bytes, data.length);
  out[data.length] = '\0';
  return out;
}

static char *copy_text(NSString *text) {
  return copy_bytes([text ?: @"" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]);
}

static NSMutableArray<NSString *> *arguments(const char *const *argv, int argc) {
  NSMutableArray<NSString *> *args = [NSMutableArray arrayWithCapacity:(NSUInteger)argc + 2];
  for (int i = 0; i < argc; i++) {
    NSString *arg = argv[i] ? [NSString stringWithUTF8String:argv[i]] : nil;
    if (!arg) return nil;
    [args addObject:arg];
  }
  return args;
}

static BOOL is_version_probe(NSArray<NSString *> *args) {
  NSMutableArray<NSString *> *rest = [args mutableCopy];
  [rest removeObject:@"-nostdin"];
  return rest.count == 1 && ([rest[0] isEqualToString:@"-version"] || [rest[0] isEqualToString:@"-bsfs"]);
}

// FFmpegKit's cancel only reaches a session its C side has registered, which happens inside the execute call;
// a cancel sent just before that can be lost, so it is resent for a few seconds while the run lasts.
static void resend_cancel(FetchrFFRun *run, int left) {
  NSMutableDictionary *runs = all_runs();
  @synchronized(runs) {
    if (run.finished) return;
  }
  [FFmpegKit cancel:[run.session getSessionId]];
  if (left <= 0) return;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kCancelRetryNs), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    resend_cancel(run, left - 1);
  });
}

int fetchr_ff_run(int probe, const char *const *argv, int argc, const char *task_id, char **output) {
  @autoreleasepool {
    *output = NULL;
    NSMutableArray<NSString *> *args = arguments(argv, argc);
    NSString *task = task_id ? [NSString stringWithUTF8String:task_id] : nil;
    if (!args || !task) {
      *output = copy_text(@"fetchr_ff_run: an argument or the task id is not UTF-8");
      return 1;
    }

    // In-process ffprobe has no stdout of its own, so it writes the report to a file the way the CLI prints it.
    NSString *stdout_path = nil;
    if (probe && ![args containsObject:@"-o"]) {
      NSString *name = [NSString stringWithFormat:@"ffprobe-%@.out", NSUUID.UUID.UUIDString];
      stdout_path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
      [args insertObjects:@[ @"-o", stdout_path ] atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
    }

    // A session registers itself through a C function that does not trigger FFmpegKitConfig's +initialize, which
    // creates the session history; the process's first session would go unregistered and lose its whole log,
    // and yt-dlp would cache its version probe as "no ffmpeg" until the app restarts.
    [FFmpegKitConfig class];
    id<Session> session = probe ? [FFprobeSession create:args
                                      withCompleteCallback:nil
                                           withLogCallback:nil
                                withLogRedirectionStrategy:LogRedirectionStrategyNeverPrintLogs]
                                : [FFmpegSession create:args
                                      withCompleteCallback:nil
                                           withLogCallback:nil
                                    withStatisticsCallback:nil
                                withLogRedirectionStrategy:LogRedirectionStrategyNeverPrintLogs];
    FetchrFFRun *run = [FetchrFFRun new];
    run.session = session;
    NSMutableDictionary<NSString *, NSMutableArray<FetchrFFRun *> *> *runs = all_runs();
    @synchronized(runs) {
      NSMutableArray *list = runs[task] ?: (runs[task] = [NSMutableArray new]);
      [list addObject:run];
      if ([cancelled_tasks() containsObject:task]) run.cancelled = YES;
    }

    bool serialized = fetchr_ff_serialize;
    BOOL skip = serialized ? !gate_enter(run) : run.cancelled;
    if (!skip) {
      if (probe) {
        [FFmpegKitConfig ffprobeExecute:(FFprobeSession *)session];
      } else {
        [FFmpegKitConfig ffmpegExecute:(FFmpegSession *)session];
      }
    }
    if (serialized && !skip) gate_leave();

    @synchronized(runs) {
      run.finished = YES;
      NSMutableArray *list = runs[task];
      [list removeObjectIdenticalTo:run];
      if (list.count == 0) [runs removeObjectForKey:task];
    }

    int code;
    if (skip) {
      code = kCancelledCode;
    } else {
      ReturnCode *rc = [session getReturnCode];
      code = rc ? [rc getValue] : 1;
    }

    if (probe) {
      NSData *printed = stdout_path ? [NSData dataWithContentsOfFile:stdout_path] : nil;
      if (stdout_path) [NSFileManager.defaultManager removeItemAtPath:stdout_path error:nil];
      // Options such as -version and -bsfs print through the log, not the writer; yt-dlp detects ffprobe by them.
      if (stdout_path && printed.length == 0 && code == 0) {
        printed = [[session getAllLogsAsString] dataUsingEncoding:NSUTF8StringEncoding];
      }
      *output = copy_bytes(printed ?: [NSData data]);
    } else {
      // yt-dlp reads ffmpeg's output only after a failed run and for the -version and -bsfs detection probes;
      // fetching the log also waits for FFmpegKit to deliver the pending messages.
      NSString *log = skip || (code == 0 && !is_version_probe(args)) ? @"" : [session getAllLogsAsString];
      NSString *trace = [session getFailStackTrace];
      *output = copy_text(trace.length ? [NSString stringWithFormat:@"%@\n%@", log ?: @"", trace] : log);
    }
    // FFmpegKit keeps finished sessions and their whole log in its history; this run has read what it needs.
    [FFmpegKitConfig deleteSession:[session getSessionId]];
    return code;
  }
}

void fetchr_ff_cancel(const char *task_id) {
  @autoreleasepool {
    NSString *task = task_id ? [NSString stringWithUTF8String:task_id] : nil;
    if (!task) return;
    NSMutableDictionary<NSString *, NSMutableArray<FetchrFFRun *> *> *runs = all_runs();
    NSArray<FetchrFFRun *> *targets;
    @synchronized(runs) {
      [cancelled_tasks() addObject:task];
      targets = [runs[task] copy];
      for (FetchrFFRun *run in targets) run.cancelled = YES;
    }
    if (targets.count) gate_wake();
    for (FetchrFFRun *run in targets) resend_cancel(run, kCancelRetries);
  }
}

void fetchr_ff_forget(const char *task_id) {
  @autoreleasepool {
    NSString *task = task_id ? [NSString stringWithUTF8String:task_id] : nil;
    if (!task) return;
    NSMutableDictionary *runs = all_runs();
    @synchronized(runs) {
      [cancelled_tasks() removeObject:task];
    }
  }
}
