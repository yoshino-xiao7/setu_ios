#import "VLCAudioProbe.h"
#import <unistd.h>
// Stable public libVLC 3 API. MobileVLCKit exports the symbols but not these C headers.
typedef struct libvlc_instance_t libvlc_instance_t;
typedef struct libvlc_media_player_t libvlc_media_player_t;
extern libvlc_media_player_t *libvlc_media_player_new(libvlc_instance_t *);
extern void libvlc_audio_set_callbacks(libvlc_media_player_t *,
    void (*)(void *, const void *, unsigned, int64_t), void (*)(void *, int64_t),
    void (*)(void *, int64_t), void (*)(void *, int64_t), void (*)(void *), void *);
extern void libvlc_audio_set_format(libvlc_media_player_t *, const char *, unsigned, unsigned);
extern int64_t libvlc_clock(void);
extern void libvlc_media_player_stop(libvlc_media_player_t *);

@interface VLCAudioProbe ()
@property(nonatomic) VLCLibrary *library;
@property(nonatomic, readwrite) VLCMediaPlayer *player;
@property(nonatomic) NSLock *lock;
@property(nonatomic) NSMutableData *samples;
@property(nonatomic) BOOL capturing;
@property(nonatomic) BOOL awaitingFlush;
@property(nonatomic, assign) libvlc_media_player_t *instance;
@end
static void samples(void *opaque, const void *data, unsigned count, int64_t pts) {
    VLCAudioProbe *probe = (__bridge VLCAudioProbe *)opaque;
    // A callback sink replaces the hardware device and must respect its presentation clock.
    int64_t wait = pts - libvlc_clock();
    if (wait > 0) usleep((useconds_t)MIN(wait, 100000));
    [probe.lock lock];
    if (probe.capturing && probe.samples.length < 88200) [probe.samples appendBytes:data length:count * sizeof(int16_t)];
    [probe.lock unlock];
}
static void flush(void *opaque, int64_t pts) {
    VLCAudioProbe *probe = (__bridge VLCAudioProbe *)opaque;
    [probe.lock lock]; [probe.samples setLength:0];
    if (probe.awaitingFlush) { probe.capturing = YES; probe.awaitingFlush = NO; }
    [probe.lock unlock];
}
@implementation VLCAudioProbe
- (instancetype)init {
    if ((self = [super init])) {
        _lock = [NSLock new]; _samples = [NSMutableData data];
        _library = [[VLCLibrary alloc] initWithOptions:@[@"--no-video"]];
        libvlc_media_player_t *instance = libvlc_media_player_new(_library.instance);
        _instance = instance;
        libvlc_audio_set_callbacks(instance, samples, NULL, NULL, flush, NULL, (__bridge void *)self);
        libvlc_audio_set_format(instance, "S16N", 44100, 1);
        _player = [[VLCMediaPlayer alloc] initWithLibVLCInstance:instance andLibrary:_library];
    }
    return self;
}
- (void)beginCapture { [_lock lock]; _capturing = NO; _awaitingFlush = YES; [_samples setLength:0]; [_lock unlock]; }
- (NSData *)capturedPCM { [_lock lock]; NSData *result = [_samples copy]; [_lock unlock]; return result; }
- (void)stop { libvlc_media_player_stop(_instance); }
- (void)dealloc { libvlc_media_player_stop(_instance); }
@end
