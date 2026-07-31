#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Wraps -[AVAudioEngine startAndReturnError:] in @try/@catch so that the
/// NSException thrown by AVAudioEngineGraph::Initialize on macOS 26+ (Tahoe)
/// is converted to an NSError instead of crashing the process.
@interface KVAudioEngineHelper : NSObject
+ (BOOL)startEngine:(AVAudioEngine *)engine
              error:(NSError * _Nullable * _Nullable)outError;

/// Runs `block` inside @try/@catch, converting any NSException into an
/// NSError. Needed for AVAudioEngine calls like installTapOnBus: which
/// raise ObjC exceptions that Swift cannot catch (process aborts otherwise).
+ (BOOL)catchException:(void (NS_NOESCAPE ^)(void))block
                 error:(NSError * _Nullable * _Nullable)outError;

/// Installs a tap with the -installTapOnBus: call itself inside the @try.
///
/// Wrapping a Swift closure that calls installTapOnBus: is NOT sound: the
/// raise then unwinds through Swift frames, which is undefined behaviour and
/// leaks under ARC. Keeping the raising call in Objective-C means no Swift
/// frame ever sits between @try and the throw.
+ (BOOL)installTapOn:(AVAudioNode *)node
                 bus:(AVAudioNodeBus)bus
          bufferSize:(AVAudioFrameCount)bufferSize
              format:(AVAudioFormat * _Nullable)format
               block:(AVAudioNodeTapBlock)block
               error:(NSError * _Nullable * _Nullable)outError;

/// Removes a tap inside @try/@catch. Safe on a bus with no tap.
+ (void)removeTapOn:(AVAudioNode *)node bus:(AVAudioNodeBus)bus;
@end

NS_ASSUME_NONNULL_END
