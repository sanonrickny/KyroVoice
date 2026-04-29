#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Wraps -[AVAudioEngine startAndReturnError:] in @try/@catch so that the
/// NSException thrown by AVAudioEngineGraph::Initialize on macOS 26+ (Tahoe)
/// is converted to an NSError instead of crashing the process.
@interface KVAudioEngineHelper : NSObject
+ (BOOL)startEngine:(AVAudioEngine *)engine
              error:(NSError * _Nullable * _Nullable)outError;
@end

NS_ASSUME_NONNULL_END
