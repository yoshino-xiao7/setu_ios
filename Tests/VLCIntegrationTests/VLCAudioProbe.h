#import <Foundation/Foundation.h>
#import <MobileVLCKit/MobileVLCKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Test-only PCM sink. Uses the public libVLC audio callback API, not a microphone.
@interface VLCAudioProbe : NSObject
@property(nonatomic, readonly) VLCMediaPlayer *player;
- (void)beginCapture;
- (NSData *)capturedPCM;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
