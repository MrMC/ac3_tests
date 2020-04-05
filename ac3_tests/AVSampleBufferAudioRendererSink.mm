//
//  AVPlayerSink.m
//  ac3_tests
//
//  Created by Scott D. Davilla on 3/22/16.
//  Copyright © 2016 RootCoder, LLC. All rights reserved.
//

#import <string>
#import <sys/stat.h>
#import <unistd.h>
#import <malloc/malloc.h>
#import "AVSampleBufferAudioRendererSink.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface AVAudioSession()
-(id)audioFormats;
-(long long)audioFormat;
-(BOOL)isDolbyAtmosAvailable;
-(BOOL)isDolbyDigitalEncoderAvailable;
@end


#define kInputBus 1
#define kOutputBus 0

static NSString *XXStringForOSType(OSType type) {
    unichar c[4];
    c[0] = (type >> 24) & 0xFF;
    c[1] = (type >> 16) & 0xFF;
    c[2] = (type >> 8) & 0xFF;
    c[3] = (type >> 0) & 0xFF;
    NSString *string = [NSString stringWithCharacters:c length:4];
    return string;
}

#pragma mark - AVSampleBufferAudioRendererSink

@interface AVSampleBufferAudioRendererSink ()
@property (nonatomic) AudioStreamBasicDescription inputFormat;
@property (nonatomic) AVSampleBufferAudioRenderer *renderer;
@property (strong, nonatomic) AVSampleBufferRenderSynchronizer *synchronizer;
@property (strong, nonatomic) dispatch_queue_t queue;
@property (nonatomic) CMTimeRange timerange;
@end

@implementation AVSampleBufferAudioRendererSink

- (void)startPlayback
{
  self.inputFormat = {0};

  //NSString * const extension = @"eac3";
  //NSString * testPath = [[NSBundle mainBundle] pathForResource: @"sample1-5.1" ofType: extension];
  NSString * const extension = @"ec3";
  NSString * testPath = [[NSBundle mainBundle] pathForResource: @"out_2" ofType: extension];
  //NSString * const extension = @"mp3";
  //NSString * testPath = [[NSBundle mainBundle] pathForResource: @"file_example_MP3_5MG" ofType: extension];

  CFURLRef soundURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)testPath, kCFURLPOSIXPathStyle, false);
  AudioFileID mAudioFile;
  int err = AudioFileOpenURL(soundURL, kAudioFileReadPermission, 0, &mAudioFile);
  UInt32 size1 = sizeof(self.inputFormat);
  err = AudioFileGetProperty(mAudioFile, kAudioFilePropertyDataFormat, &size1, &_inputFormat);

  /*
  // now we should look to see which decoders we have on the system
  err = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, & size1);
  UInt32 numDecoders = size1 / sizeof (OSType);
  OSType *decoderIDs = new OSType[numDecoders];
  err = AudioFormatGetProperty (kAudioFormatProperty_DecodeFormatIDs, 0, NULL, & size1, decoderIDs);
  for (unsigned int j = 0; j < numDecoders; ++j) {
    NSLog(@"decoderIDs: %@", XXStringForOSType(decoderIDs[j]));
  }
  */

  /*
  // now we should look to see which decoders we have on the system
  err = AudioFormatGetPropertyInfo(kAudioFormatProperty_EncodeFormatIDs, 0, NULL, & size1);
  UInt32 numEcoders = size1 / sizeof (OSType);
  OSType *ecoderIDs = new OSType[numEcoders];
  err = AudioFormatGetProperty (kAudioFormatProperty_EncodeFormatIDs, 0, NULL, & size1, ecoderIDs);
  for (unsigned int j = 0; j < numEcoders; ++j) {
    NSLog(@"ecoderIDs: %@", XXStringForOSType(ecoderIDs[j]));
  }
  */

  [self majic];
  [self checkAudioSettings];
  //[self checkAudioComponents];

  //                  11  d  a  c  3
  //  AC3 -> 00 00 00 0B 64 61 63 33 10 3D 60
  //  AC3 -> 00 00 00 0B 64 61 63 33 10 3D 40
  // mov_write_ac3_tag
  //                  13  d  e  c  3
  // EAC3 -> 00 00 00 0D 64 65 63 33 02 80 20 0F 00
  // mov_write_eac3_tag
  //
  // Atmos -> 00 00 00 10 64 65 63 33 02 40 20 0f 00 01 10 00
  void *magicCookie = NULL;
  UInt32 magicCookieSize = 0;
  //Get Magic Cookie info(if exists) and pass it to converter
  err = AudioFileGetPropertyInfo(mAudioFile, kAudioFilePropertyMagicCookieData, &magicCookieSize, NULL);
  if (err == noErr)
  {
    magicCookie = calloc(1, magicCookieSize);
    if (magicCookie)
      err = AudioFileGetProperty(mAudioFile, kAudioFilePropertyMagicCookieData, &magicCookieSize, magicCookie);
  }


  AudioFormatInfo formatInfo = {self.inputFormat, magicCookie, magicCookieSize};
  UInt32 formatInfoSize = sizeof(formatInfo);

  UInt32 formatListSize = sizeof(AudioFormatListItem);
  err = AudioFormatGetPropertyInfo(kAudioFormatProperty_FormatList, formatInfoSize, &formatInfo, &formatListSize);
  UInt32 numFormats = formatListSize / sizeof(AudioFormatListItem);
  AudioFormatListItem *formatList = new AudioFormatListItem[numFormats];

  err = AudioFormatGetProperty(kAudioFormatProperty_FormatList, formatInfoSize, &formatInfo, &formatListSize, formatList);
  for (unsigned int j = 0; j < numFormats; ++j) {
    NSLog(@"%d, mSampleRate: %f", j, formatList[j].mASBD.mSampleRate);
    NSLog(@"%d, mFormatID: %@", j, XXStringForOSType(formatList[j].mASBD.mFormatID));
    NSLog(@"%d, mFormatFlags: %u", j, formatList[j].mASBD.mFormatFlags);
    NSLog(@"%d, mBytesPerPacket: %u", j, formatList[j].mASBD.mBytesPerPacket);
    NSLog(@"%d, mFramesPerPacket: %u", j, formatList[j].mASBD.mFramesPerPacket);
    NSLog(@"%d, mBytesPerFrame: %u", j, formatList[j].mASBD.mBytesPerFrame);
    NSLog(@"%d, mChannelsPerFrame: %u", j, formatList[j].mASBD.mChannelsPerFrame);
    NSLog(@"%d, mBitsPerChannel: %u", j, formatList[j].mASBD.mBitsPerChannel);
    NSLog(@"%d, mReserved: %u", j, formatList[j].mASBD.mReserved);
    NSLog(@"%d, mChannelLayoutTag: %u", j, formatList[j].mChannelLayoutTag);
    NSLog(@"");
  }
  UInt32 itemIndex;
  UInt32 indexSize = sizeof(itemIndex);
  err = AudioFormatGetProperty(kAudioFormatProperty_FirstPlayableFormatFromList, formatListSize, formatList, &indexSize, &itemIndex);


  NSLog(@"mSampleRate: %f", self.inputFormat.mSampleRate);
  NSLog(@"mFormatID: %u", self.inputFormat.mFormatID);
  NSLog(@"mFormatFlags: %u", self.inputFormat.mFormatFlags);
  NSLog(@"mBytesPerPacket: %u", self.inputFormat.mBytesPerPacket);
  NSLog(@"mFramesPerPacket: %u", self.inputFormat.mFramesPerPacket);
  NSLog(@"mBytesPerFrame: %u", self.inputFormat.mBytesPerFrame);
  NSLog(@"mChannelsPerFrame: %u", self.inputFormat.mChannelsPerFrame);
  NSLog(@"mBitsPerChannel: %u", self.inputFormat.mBitsPerChannel);
  NSLog(@"mReserved: %u", self.inputFormat.mReserved);

  AudioStreamBasicDescription inFormat = self.inputFormat;
/*
  NSLog(@"mod:mFormatID: %u", self.inputFormat.mFormatID);
  inFormat.mFramesPerPacket = 1536;
  NSLog(@"mod:mFramesPerPacket: %u", inFormat.mFramesPerPacket);
  inFormat.mChannelsPerFrame = 16;
  NSLog(@"mod:mChannelsPerFrame: %u", inFormat.mChannelsPerFrame);
*/

/*
  inFormat.mSampleRate = 48000.0;
  inFormat.mFormatID = 'mtb+';
  inFormat.mFormatFlags = 0x4c;
  //inFormat.mBytesPerPacket = 61440;
  inFormat.mFramesPerPacket = 1536;
  //inFormat.mBytesPerFrame = 64;
  inFormat.mChannelsPerFrame = 16;
*/

  self.renderer = [[AVSampleBufferAudioRenderer alloc] init];
  self.synchronizer = [[AVSampleBufferRenderSynchronizer alloc] init];
  [self.synchronizer addRenderer:self.renderer];
  self.queue = dispatch_queue_create("com.mrmc.audio_providercallback", DISPATCH_QUEUE_SERIAL);
  dispatch_set_target_queue( self.queue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0 ) );

  [[NSNotificationCenter defaultCenter] addObserverForName:AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification
    object:self.renderer queue:NULL usingBlock:^(NSNotification * _Nonnull notification)
  {
    NSLog(@"AudioRendererWasFlushedAutomatically");
    dispatch_async(self.queue, ^{
      // The value of this key is an NSValue wrapping a CMTime.
      NSValue *flushTime = notification.userInfo[AVSampleBufferAudioRendererFlushTimeKey];
      NSLog(@"flushTime: %@", flushTime);
    });
  }];

  char* transferBuffer = new char[65536*2];

  // 8,  kAudioChannelLayoutTag_Atmos_5_1_2
  // 12, kAudioChannelLayoutTag_Atmos_7_1_4
  // 16, kAudioChannelLayoutTag_Atmos_9_1_6
  __block AVAudioChannelLayout *avlayout = [[AVAudioChannelLayout alloc]
    initWithLayoutTag:kAudioChannelLayoutTag_Atmos_9_1_6];
  __block size_t layoutSize = malloc_size((__bridge const void *)avlayout);
  //NSLog(@"layout: %@", avlayout);

  __block size_t readHead = 0;
  __block float bufferedTime = 0;
  __block CMFormatDescriptionRef format = NULL;
  __block OSStatus status = 0;
  status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault,
    &inFormat, layoutSize, [avlayout layout], magicCookieSize, magicCookie, NULL, &format);
  //status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &inFormat, 0, NULL, 0, NULL, NULL, &format);
  NSLog(@"format: %@", format);

  {
    const AudioFormatListItem *audioFormatListItem = CMAudioFormatDescriptionGetRichestDecodableFormat(format);
    NSLog(@"GetRichestDecodableFormat: %@", XXStringForOSType(audioFormatListItem->mASBD.mFormatID));

    AudioFormatListItem formatList = {0};
    formatList.mASBD.mFormatID = 'ec-3';
    formatList.mASBD.mSampleRate = 48000.0;
    formatList.mASBD.mFramesPerPacket = 1536;
    formatList.mASBD.mChannelsPerFrame = 8;

    UInt32 formatListSize = sizeof(AudioFormatListItem);
    UInt32 outFormatListSize = 0;
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_OutputFormatList, formatListSize, &formatList, &outFormatListSize);

    UInt32 numFormats = outFormatListSize / sizeof(AudioFormatListItem);
    AudioFormatListItem *outFormatList = new AudioFormatListItem[numFormats];

    status = AudioFormatGetProperty(kAudioFormatProperty_OutputFormatList, formatListSize, &formatList, &outFormatListSize, outFormatList);
    for (unsigned int j = 0; j < numFormats; ++j) {
      NSLog(@"%d, mSampleRate: %f", j, outFormatList[j].mASBD.mSampleRate);
      NSLog(@"%d, mFormatID: %@", j, XXStringForOSType(outFormatList[j].mASBD.mFormatID));
      NSLog(@"%d, mFormatFlags: %u", j, outFormatList[j].mASBD.mFormatFlags);
      NSLog(@"%d, mBytesPerPacket: %u", j, outFormatList[j].mASBD.mBytesPerPacket);
      NSLog(@"%d, mFramesPerPacket: %u", j, outFormatList[j].mASBD.mFramesPerPacket);
      NSLog(@"%d, mBytesPerFrame: %u", j, outFormatList[j].mASBD.mBytesPerFrame);
      NSLog(@"%d, mChannelsPerFrame: %u", j, outFormatList[j].mASBD.mChannelsPerFrame);
      NSLog(@"%d, mBitsPerChannel: %u", j, outFormatList[j].mASBD.mBitsPerChannel);
      NSLog(@"%d, mReserved: %u", j, outFormatList[j].mASBD.mReserved);
      NSLog(@"%d, mChannelLayoutTag: %u", j, outFormatList[j].mChannelLayoutTag);
      NSLog(@"");
    }
  }

  [self.renderer  requestMediaDataWhenReadyOnQueue:self.queue usingBlock:^
  {
    int reader = open(testPath.UTF8String, O_RDONLY, 00666);
    while(self.renderer.readyForMoreMediaData)
    {
      lseek(reader, readHead, SEEK_SET);
      // 2304 = 256 * 9
      ssize_t bytes = read(reader, transferBuffer, 4 * 2304);
      if (bytes > 0)
      {
        CMBlockBufferRef blockBuffer = NULL;
        CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
          transferBuffer, bytes, kCFAllocatorMalloc, NULL, 0, bytes, 0, &blockBuffer);
        CMSampleBufferRef buffer = NULL;

        AudioStreamPacketDescription packetDescription;
        packetDescription.mDataByteSize = (int)bytes;
        packetDescription.mStartOffset = 0;
        packetDescription.mVariableFramesInPacket = 0;

        // calc packets as 2304 byte frames.
        float packets = readHead / 2304;
        // WTF? time is based on 1536 byte frames.
        CMTime sampleTime = CMTimeMake(packets * (256.0 * 6), 48000.0);
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(kCFAllocatorDefault,
          blockBuffer, format, 1, sampleTime, &packetDescription, &buffer);
        //NSLog(@"buffer: %@", buffer);
        //CFRelease(format);

        readHead += bytes;
        bufferedTime = 0.032 * packets;
        NSLog(@"packet %f, readHead %zu", packets, readHead);
        [self.renderer enqueueSampleBuffer:buffer];
        CFRelease(buffer);
      }
      else
      {
        //NSLog(@"no more sample buffers to enqueue %zu", readHead);
        usleep(5 * 1000);
      }
    }
    // yield a little here or we hammer the cpu
    usleep(5 * 1000);
  }];

  [self.synchronizer setRate:1.0];
  [self.renderer setMuted:NO];

  NSLog(@"player volume %f", [self.renderer volume]);

/*
  // need to fetch maximumOutputNumberOfChannels when active
  NSError *nserr = NULL;
  long channels = [[AVAudioSession sharedInstance] maximumOutputNumberOfChannels];
  channels = 16;
  [[AVAudioSession sharedInstance] setPreferredOutputNumberOfChannels: channels error: &nserr];
*/

  while (1)
  {
    CMTime cmTime = CMTimebaseGetTime([self.renderer timebase]);
    float currentTime = CMTimeGetSeconds(cmTime);
    if (currentTime > 0.0f)
      NSLog(@"player: bufferedTime %f, currentTime %f", bufferedTime, currentTime);

    AVQueuedSampleBufferRenderingStatus status = [self.renderer status];
    switch (status)
    {
      case AVQueuedSampleBufferRenderingStatusUnknown:
        NSLog(@"AVSampleBufferDisplayLayer has status unknown, but should be rendering.");
        break;
      case AVQueuedSampleBufferRenderingStatusFailed:
        NSLog(@"AVSampleBufferDisplayLayer has status failed, err %s",
        [[[self.renderer error] description] cStringUsingEncoding:NSUTF8StringEncoding]);
        break;
      case AVQueuedSampleBufferRenderingStatusRendering:
        break;
    }


    usleep(250*1000);
  }
}

- (void)checkAudioSettings
{
  AudioComponentDescription description = {0};
  description.componentType = kAudioUnitType_Output;
  description.componentSubType = kAudioUnitSubType_RemoteIO;
  description.componentManufacturer = kAudioUnitManufacturer_Apple;

  // Get component
  AudioUnit audioUnit;
  AudioComponent component;
  component = AudioComponentFindNext(NULL, &description);
  OSStatus status = AudioComponentInstanceNew(component, &audioUnit);
  if (status == noErr)
  {
    // must initialize for AudioUnitGetPropertyXXXX to work
    status = AudioUnitInitialize(audioUnit);

    UInt32 layoutSize = 0;
    status = AudioUnitGetPropertyInfo(audioUnit,
      kAudioUnitProperty_AudioChannelLayout, kAudioUnitScope_Output, 0, &layoutSize, nullptr);
    if (status == noErr)
    {
      AudioChannelLayout *layout = nullptr;
      layout = (AudioChannelLayout*)malloc(layoutSize);
      status = AudioUnitGetProperty(audioUnit,
        kAudioUnitProperty_AudioChannelLayout, kAudioUnitScope_Output, 0, layout, &layoutSize);

      /*
      CFStringRef layoutName = nullptr;
      UInt32 propertySize = sizeof(layoutName);
      status = AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutName, layoutSize, layout, &propertySize, &layoutName);
      if (layoutName)
      {
        NSLog(@"ChannelLayoutName: %@", layoutName);
        CFRelease(layoutName);
      }

      status = AudioFormatGetProperty(kAudioFormatProperty_ChannelLayoutSimpleName, layoutSize, layout, &propertySize, &layoutName);
      // later
      if (layoutName)
      {
        NSLog(@"ChannelLayoutSimpleName: %@", layoutName);
        CFRelease(layoutName);
      }
      */

      // function returns noErr only if audio set to Stereo or DD5.1
      AudioChannelLayoutTag layoutTag = kAudioChannelLayoutTag_Unknown;
      UInt32 layoutTagSize = sizeof(layoutTagSize);
      status = AudioFormatGetProperty(kAudioFormatProperty_TagForChannelLayout, layoutSize, layout, &layoutTagSize, &layoutTag);
      //NSLog(@"mChannelLayoutTag: %u", layoutTag);
      if (layoutTag == kAudioChannelLayoutTag_Stereo)
        NSLog(@"Setting is Stereo");
      else if (layoutTag == kAudioChannelLayoutTag_MPEG_5_1_C)
        NSLog(@"Setting is DD5.1");
      else if (layoutTag == kAudioChannelLayoutTag_Unknown)
      {
        long maxChannels = [[AVAudioSession sharedInstance] maximumOutputNumberOfChannels];
        //NSLog(@"maxChannels: %ld", maxChannels);
        if (maxChannels > 8)
          NSLog(@"Setting is Auto, Atmos Enabled");
        else
          NSLog(@"Setting is Auto, Atmos Disabled");
      }

      free(layout);
    }

  }

  AudioUnitUninitialize(audioUnit);
  AudioComponentInstanceDispose(audioUnit);
}

-(void)checkAudioComponents
{
  AudioComponentDescription descr = {0};
  NSArray *components = [[AVAudioUnitComponentManager sharedAudioUnitComponentManager] componentsMatchingDescription: descr];

  unsigned long componentsCount = [components count];
  for (int k = 0; k < componentsCount; ++k)
  {
    AVAudioUnitComponent *component = [components objectAtIndex:k];
    NSLog(@"%d, component name: %@", k, component.name);
    NSLog(@"%d, component typeName: %@", k, component.typeName);

  }
}

-(void)majic
{
  long long audioFormat = [[AVAudioSession sharedInstance] audioFormat];
  NSLog(@"AVAudioSession audioFormat:  %@", XXStringForOSType((OSType)audioFormat));
  NSArray *audioFormats = [[AVAudioSession sharedInstance] audioFormats];
  //id audioFormats = [[AVAudioSession sharedInstance] audioFormats];
  unsigned long  audioFormatsCount = [audioFormats count];
  for (int k = 0; k < audioFormatsCount; ++k)
  {
    id audioFormat = [audioFormats objectAtIndex:k];
    NSLog(@"AVAudioSession audioFormats: %@", XXStringForOSType((OSType)[audioFormat longValue]));
  }
  //NSLog(@"audioFormats: %@", audioFormats);
  BOOL isDolbyAtmosAvailable = [[AVAudioSession sharedInstance] isDolbyAtmosAvailable];
  NSLog(@"AVAudioSession isDolbyAtmosAvailable: %d", isDolbyAtmosAvailable);
  BOOL isDolbyDigitalEncoderAvailable = [[AVAudioSession sharedInstance] isDolbyDigitalEncoderAvailable];
  NSLog(@"AVAudioSession isDolbyDigitalEncoderAvailable: %d", isDolbyDigitalEncoderAvailable);

/*
  // besides fourCC also the bsid in cookie created by CMAudioFormatDescriptionGetMagicCookie needs to be fixed
  NSRange cookieBsidRange = NSMakeRange(2, 1);
  uint8_t cookieBsidByte[1];
  [ac3Info getBytes:cookieBsidByte range:cookieBsidRange];
  // keep fscod, replace bsid with 0x10. This can happen, if bsid=0x10 frames are embedded as substream inside bsid=0x06 frames.
  cookieBsidByte[0] = (cookieBsidByte[0] & 0xC0) | (0x10 << 1);
  [ac3Info replaceBytesInRange:cookieBsidRange withBytes:cookieBsidByte length:1];
*/
}
@end

