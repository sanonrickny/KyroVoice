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

@end
