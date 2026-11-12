// Finding RemoteCompanion's command-line tools and running them, shared by the tweak (in
// SpringBoard) and rc-screen. Header-only: each includes it.
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/wait.h>
#import <signal.h>
#import <fcntl.h>
#import <dlfcn.h>

extern char **environ;

// The jailbreak's bin folder holding `name`: next to whoever asks (rc-screen sits beside
// rc-client), or under the jailbreak root the tweak was loaded from (rootless /var/jb, roothide's
// randomized folder), or the usual places
static inline NSString *rc_tool_path(NSString *name) {
    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    Dl_info info;
    if (dladdr((const void *)&rc_tool_path, &info) && info.dli_fname) {
        NSString *image = @(info.dli_fname);
        NSString *dir = image.stringByDeletingLastPathComponent;
        if ([dir hasSuffix:@"/usr/bin"]) [dirs addObject:dir];
        for (NSString *marker in @[@"/Library/MobileSubstrate/", @"/usr/lib/TweakInject/", @"/usr/lib/ellekit/"]) {
            NSRange r = [image rangeOfString:marker];
            if (r.location != NSNotFound) [dirs addObject:[[image substringToIndex:r.location] stringByAppendingString:@"/usr/bin"]];
        }
    }
    [dirs addObjectsFromArray:@[@"/var/jb/usr/bin", @"/usr/bin"]];
    for (NSString *dir in dirs) {
        NSString *path = [dir stringByAppendingPathComponent:name];
        if (access(path.fileSystemRepresentation, X_OK) == 0) return path;
    }
    return nil;
}

// Runs `path` with `args`, waiting up to `timeout` seconds. Its exit status, or -1 if it couldn't
// start or took too long (then it's sent SIGTERM, and SIGKILL a second later if it's still there);
// what it printed (stdout and stderr) in *output
static inline int rc_run_tool(NSString *path, NSArray<NSString *> *args, double timeout, NSString **output) {
    if (output) *output = @"";
    if (!path) return -1;
    int out[2];
    if (pipe(out) != 0) return -1;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, out[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, out[0]);
    char **argv = calloc(args.count + 2, sizeof(char *));
    argv[0] = (char *)path.fileSystemRepresentation;
    for (NSUInteger i = 0; i < args.count; i++) argv[i + 1] = (char *)args[i].UTF8String;
    pid_t pid;
    int err = posix_spawn(&pid, argv[0], &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    free(argv);
    close(out[1]);
    if (err != 0) {
        close(out[0]);
        return -1;
    }
    NSMutableData *data = [NSMutableData data];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
    int status = 0;
    BOOL exited = NO, timedOut = NO;
    fcntl(out[0], F_SETFL, O_NONBLOCK);
    char buffer[1024];
    ssize_t n;
    while (!exited) {
        while ((n = read(out[0], buffer, sizeof(buffer))) > 0) [data appendBytes:buffer length:(NSUInteger)n];
        if (waitpid(pid, &status, WNOHANG) == pid) { exited = YES; break; }
        if ([until timeIntervalSinceNow] < 0) {
            timedOut = YES;
            kill(pid, SIGTERM);
            for (int i = 0; i < 50 && !exited; i++) {
                if (waitpid(pid, &status, WNOHANG) == pid) exited = YES; else usleep(20000);
            }
            if (!exited) { kill(pid, SIGKILL); waitpid(pid, &status, 0); exited = YES; }
            break;
        }
        usleep(20000);
    }
    while ((n = read(out[0], buffer, sizeof(buffer))) > 0) [data appendBytes:buffer length:(NSUInteger)n];
    close(out[0]);
    if (output) *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (timedOut) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
