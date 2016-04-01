#import "AudioController.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioServices.h>

#define kInputBus 1
#define kOutputBus 0

@interface AudioController ()
{
    AudioUnit audiounit;
}
@end

@implementation AudioController

- (void)setUp
{
    AVAudioSession *sess = [AVAudioSession sharedInstance];
    NSError *error = nil;
    double rate = 44100.0;
    [sess setPreferredSampleRate:rate error:&error];
    [sess setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    [sess setActive:YES error:&error];
    rate = [sess sampleRate];
    if (error)
        NSLog(@"%@", error);

    NSLog(@"Initing");

    // createUnitDesc
    AudioComponentDescription desc = {0};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    // getAudioUnit
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    OSStatus res = AudioComponentInstanceNew(component, &audiounit);
    if (noErr != res)
        [self showStatus:res];

    UInt32 flag;
    OSStatus err;

    // enableIORec
    flag = 1;
    err = AudioUnitSetProperty(audiounit, kAudioOutputUnitProperty_EnableIO,
      kAudioUnitScope_Input, kInputBus, &flag, sizeof(flag));
    if (noErr != err)
        [self showStatus:err];

    // enableIOPb
    flag = 1;
    err = AudioUnitSetProperty(audiounit, kAudioOutputUnitProperty_EnableIO,
      kAudioUnitScope_Output, kOutputBus, &flag, sizeof(flag));
    if (noErr != err) {
        [self showStatus:err];
    }

    // createFormat, Describe format
    AudioStreamBasicDescription audioFormat = {0};
    audioFormat.mSampleRate         = rate;
    audioFormat.mFormatID           = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags        = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mFramesPerPacket    = 1;
    audioFormat.mChannelsPerFrame   = 1;
    audioFormat.mBitsPerChannel     = 16;
    audioFormat.mBytesPerPacket     = 2;
    audioFormat.mBytesPerFrame      = 2;

    // applyFormat
    err = AudioUnitSetProperty(audiounit, kAudioUnitProperty_StreamFormat,
      kAudioUnitScope_Output, kInputBus, &audioFormat, sizeof(audioFormat));
    if (noErr != err)
        [self showStatus:err];

    //
    err = AudioUnitInitialize(audiounit);
    if (noErr != err)
        [self showStatus:err];

    // connect input to output unit
    AudioUnitConnection conn;
    conn.destInputNumber = 0;
    conn.sourceAudioUnit = audiounit;
    conn.sourceOutputNumber = 1;
    err = AudioUnitSetProperty(audiounit, kAudioUnitProperty_MakeConnection,
      kAudioUnitScope_Input, 0, &conn, sizeof(conn));
    if (noErr != err)
        [self showStatus:err];
}

- (void)start
{
    NSLog(@"starting");
    OSStatus err = AudioOutputUnitStart(audiounit);
    if (noErr != err)
        [self showStatus:err];
}

- (void)end
{
    NSLog(@"ending");
    OSStatus err = AudioOutputUnitStop(audiounit);
    if (noErr != err)
        [self showStatus:err];
}

- (void)showStatus:(OSStatus)st
{
    NSString *text = nil;
    switch (st)
    {
        case kAudioUnitErr_CannotDoInCurrentContext: text = @"kAudioUnitErr_CannotDoInCurrentContext"; break;
        case kAudioUnitErr_FailedInitialization: text = @"kAudioUnitErr_FailedInitialization"; break;
        case kAudioUnitErr_FileNotSpecified: text = @"kAudioUnitErr_FileNotSpecified"; break;
        case kAudioUnitErr_FormatNotSupported: text = @"kAudioUnitErr_FormatNotSupported"; break;
        case kAudioUnitErr_Initialized: text = @"kAudioUnitErr_Initialized"; break;
        case kAudioUnitErr_InvalidElement: text = @"kAudioUnitErr_InvalidElement"; break;
        case kAudioUnitErr_InvalidFile: text = @"kAudioUnitErr_InvalidFile"; break;
        case kAudioUnitErr_InvalidOfflineRender: text = @"kAudioUnitErr_InvalidOfflineRender"; break;
        case kAudioUnitErr_InvalidParameter: text = @"kAudioUnitErr_InvalidParameter"; break;
        case kAudioUnitErr_InvalidProperty: text = @"kAudioUnitErr_InvalidProperty"; break;
        case kAudioUnitErr_InvalidPropertyValue: text = @"kAudioUnitErr_InvalidPropertyValue"; break;
        case kAudioUnitErr_InvalidScope: text = @"kAudioUnitErr_InvalidScope"; break;
        case kAudioUnitErr_NoConnection: text = @"kAudioUnitErr_NoConnection"; break;
        case kAudioUnitErr_PropertyNotInUse: text = @"kAudioUnitErr_PropertyNotInUse"; break;
        case kAudioUnitErr_PropertyNotWritable: text = @"kAudioUnitErr_PropertyNotWritable"; break;
        case kAudioUnitErr_TooManyFramesToProcess: text = @"kAudioUnitErr_TooManyFramesToProcess"; break;
        case kAudioUnitErr_Unauthorized: text = @"kAudioUnitErr_Unauthorized"; break;
        case kAudioUnitErr_Uninitialized: text = @"kAudioUnitErr_Uninitialized"; break;
        case kAudioUnitErr_UnknownFileType: text = @"kAudioUnitErr_UnknownFileType"; break;
        default: text = @"unknown error";
    }
    NSLog(@"TRANSLATED_ERROR = %i = %@", (int)st, text);
}

- (void)dealloc
{
    AudioUnitUninitialize(audiounit);
}

@end

