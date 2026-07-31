#import "include/KVAudioEngineHelper.h"

@implementation KVAudioEngineHelper

+ (BOOL)startEngine:(AVAudioEngine *)engine
              error:(NSError **)outError {
    @try {
        NSError *err = nil;
        BOOL ok = [engine startAndReturnError:&err];
        if (!ok) {
            if (outError) *outError = err;
            return NO;
        }
        return YES;
    } @catch (NSException *ex) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"com.kyro.KyroVoice"
                                           code:-1
                                       userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"AVAudioEngine init failed (%@): %@",
                    ex.name, ex.reason ?: @"no reason"]
            }];
        }
        return NO;
    }
}

+ (BOOL)catchException:(void (NS_NOESCAPE ^)(void))block
                 error:(NSError **)outError {
    @try {
        block();
        return YES;
    } @catch (NSException *ex) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"com.kyro.KyroVoice"
                                           code:-2
                                       userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"Audio engine error (%@): %@",
                    ex.name, ex.reason ?: @"no reason"]
            }];
        }
        return NO;
    }
}

+ (BOOL)installTapOn:(AVAudioNode *)node
                 bus:(AVAudioNodeBus)bus
          bufferSize:(AVAudioFrameCount)bufferSize
              format:(AVAudioFormat *)format
               block:(AVAudioNodeTapBlock)block
               error:(NSError **)outError {
    @try {
        [node installTapOnBus:bus bufferSize:bufferSize format:format block:block];
        return YES;
    } @catch (NSException *ex) {
        if (outError) {
            // ex.reason carries the AVAE assertion text, e.g.
            // "required condition is false: IsFormatSampleRateAndChannelCountValid(format)".
            // That string is the whole diagnosis, so surface it verbatim.
            *outError = [NSError errorWithDomain:@"com.kyro.KyroVoice"
                                           code:-3
                                       userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"installTap failed (%@): %@",
                    ex.name, ex.reason ?: @"no reason"]
            }];
        }
        return NO;
    }
}

+ (void)removeTapOn:(AVAudioNode *)node bus:(AVAudioNodeBus)bus {
    @try {
        [node removeTapOnBus:bus];
    } @catch (NSException *ex) {
        NSLog(@"KyroVoice: removeTapOnBus raised (%@): %@", ex.name, ex.reason ?: @"no reason");
    }
}

@end
