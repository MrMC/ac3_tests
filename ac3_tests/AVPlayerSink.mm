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
#import "AVPlayerSink.h"

#import <AVFoundation/AVFoundation.h>

@interface AVAudioSession()
-(id)audioFormats;
-(long long)audioFormat;
-(BOOL)isDolbyAtmosAvailable;
-(BOOL)isDolbyDigitalEncoderAvailable;
-(BOOL)setAudioHardwareControlFlags:(unsigned long long)arg1 error:(id*)arg2 ;
-(BOOL)isHardwareFormatFixedToMultiChannel;
-(BOOL)fixHardwareFormatToMultiChannel:(BOOL)arg1 error:(id*)arg2 ;
-(void)privateUpdateAudioFormat:(id)arg1 ;
-(void)privateUpdateAudioFormats:(id)arg1 ;
-(BOOL)privateSetPropertyValue:(unsigned)arg1 withBool:(BOOL)arg2 error:(id*)arg3 ;
-(double)currentHardwareSampleRate;
-(long long)currentHardwareInputNumberOfChannels;
-(long long)currentHardwareOutputNumberOfChannels;
-(double)preferredHardwareSampleRate;
@end

static NSString *XXStringForOSType(OSType type) {
    unichar c[4];
    c[0] = (type >> 24) & 0xFF;
    c[1] = (type >> 16) & 0xFF;
    c[2] = (type >> 8) & 0xFF;
    c[3] = (type >> 0) & 0xFF;
    NSString *string = [NSString stringWithCharacters:c length:4];
    return string;
}

#pragma mark - ResourceLoader

static void *playbackLikelyToKeepUp = &playbackLikelyToKeepUp;
static void *playbackBufferEmpty = &playbackBufferEmpty;
static void *playbackBufferFull = &playbackBufferFull;

/*
@interface AVAssetResourceLoadingContentInformationRequest()
- (void)setDiskCachingPermitted:(BOOL)arg1;
@end
*/

@interface ResourceLoader : NSObject <AVAssetResourceLoaderDelegate>
@property (atomic) float currentTime;
@property (atomic) float bufferedTime;
@property (atomic) float minBufferedTime;
@end

@implementation ResourceLoader
  bool mAbortflag;
  char *mReadbuffer;
  size_t mReadbufferSize;
  int mFileReader;
  float mFrameBytes;
  float mFrameDuration;
  int64_t mBufferedBytes;
  int64_t mdataRequestCount;

- (NSError *)loaderCancelledError
{
  NSError *error = [[NSError alloc] initWithDomain:@"ResourceLoaderErrorDomain"
    code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Resource loader cancelled"}];

  return error;
}

- (id)initWithFrameBytes:(unsigned int)frameBytes
{
  NSLog(@"resourceLoader: initWithFrameBytes %d", frameBytes);
  self = [super init];
  if (self)
  {
    _currentTime = 0.0f;
    _bufferedTime = 0.0f;
    _minBufferedTime = 3.0f;
    mFrameBytes = frameBytes;
    mFrameDuration = (256.0 * 6) / 48000.0; // 0.032 seconds
    mBufferedBytes = 0;
    mAbortflag = false;
    mdataRequestCount = 0;
    mReadbufferSize = mFrameBytes * 40;
    if (mReadbufferSize < 65536)
      mReadbufferSize = 65536;
    mReadbuffer = new char[mReadbufferSize];
    std::string tmpBufferFile = [NSTemporaryDirectory() UTF8String];
    tmpBufferFile += "avaudio.ec3";
    mFileReader = open(tmpBufferFile.c_str(), O_RDONLY, 00666);
  }

  return self;
}

- (void)dealloc
{
  NSLog(@"resourceLoader: dealloc");
}

- (void)abort
{
  mAbortflag = true;
}

- (bool)checkFileBufferLength:(size_t)offset length:(size_t)length
{
  struct stat statbuf;
  fstat(mFileReader, &statbuf);
  off_t filelength = statbuf.st_size;
  NSLog(@"resourceLoader: file size %lld", filelength);
  if (filelength >= offset + length)
    return true;

  return false;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
  AVAssetResourceLoadingContentInformationRequest* contentRequest = loadingRequest.contentInformationRequest;

  if (contentRequest)
  {
    // figure out if this is ac3 or eac3
    NSURL *resourceURL = [loadingRequest.request URL];
    if ([resourceURL.pathExtension isEqualToString:@"ac3"])
      contentRequest.contentType = @"public.ac3-audio";
    else if ([resourceURL.pathExtension isEqualToString:@"eac3"])
      contentRequest.contentType = @"public.enhanced-ac3-audio";
    else if ([resourceURL.pathExtension isEqualToString:@"ec3"])
      contentRequest.contentType = @"public.enhanced-ac3-audio";
    contentRequest.contentLength = INT_MAX;
    //[contentRequest setDiskCachingPermitted:NO];
    // must be 'NO' to get player to start playing immediately
    contentRequest.byteRangeAccessSupported = NO;
    NSLog(@"resourceLoader: contentRequest %@", contentRequest);
  }

  if (mAbortflag)
  {
    [loadingRequest finishLoadingWithError:[self loaderCancelledError]];
    return YES;
  }

  AVAssetResourceLoadingDataRequest* dataRequest = loadingRequest.dataRequest;
  if (dataRequest)
  {
    mdataRequestCount++;
    // avplayer does a few probing requests.
    bool probing = false;
    if (dataRequest.requestedLength == 65536)
    {
      if (dataRequest.requestedOffset > 0)
        probing = true;
    }


    NSLog(@"probing %d, resourceLoader dataRequest %@", probing, dataRequest);

    // overflow throttle, keep about 3-4 seconds buffered in avplayer
    _bufferedTime = mFrameDuration * ((float)mBufferedBytes / mFrameBytes);
    while (!mAbortflag && _bufferedTime - _currentTime > _minBufferedTime)
    {
      usleep(5 * 1000);
    }

    //dispatch_async(dispatch_get_main_queue(), ^{
      size_t offset = dataRequest.requestedOffset;
      if (dataRequest.requestedLength == 2)
      {
        // avplayer always 1st reads two bytes to check for a content tag.
        // ac3/eac3 has two byte tag of 0x0b77, \v is vertical tab == 0x0b
        [dataRequest respondWithData:[NSData dataWithBytes:"\vw" length:2]];
        NSLog(@"resourceLoader: probing 1, sending 2 bytes");
        [loadingRequest finishLoading];
      }
      else if (offset != mBufferedBytes)
      {
        // more probing, grr feed the pig junk
        NSLog(@"resourceLoader: probing 1, currentOffset %lu", (unsigned long)dataRequest.currentOffset);
        [dataRequest respondWithData:[NSData dataWithBytes:"\vw" length:2]];
        [loadingRequest finishLoading];
      }
      else
      {
        size_t length = mReadbufferSize;
        if (dataRequest.requestedLength == 65536)
        {
          // 1st 64k read attempt or probes
          offset = 0;
          length = 65536;
        }

        // Pull audio from buffer
        while (!mAbortflag && ![self checkFileBufferLength:offset length:length])
        {
          usleep(5 * 1000);
        }
        lseek(mFileReader, offset, SEEK_SET);
        size_t availableBytes = read(mFileReader, mReadbuffer, length);

        // check if we have enough data
        if (availableBytes > 0)
        {
          size_t requestedLength = (size_t)dataRequest.requestedLength;
          size_t bytesToCopy = requestedLength > availableBytes ? availableBytes : requestedLength;
          if (bytesToCopy > 0)
          {
              NSData *data = [NSData dataWithBytes:mReadbuffer length:bytesToCopy];
              [dataRequest respondWithData:data];
              NSLog(@"resourceLoader: probing %d, sending %lu bytes", probing, (unsigned long)[data length]);
              NSLog(@"resourceLoader: probing %d, currentOffset %lu", probing, (unsigned long)dataRequest.currentOffset);
              if (!probing)
                mBufferedBytes = dataRequest.currentOffset;
          }
          [loadingRequest finishLoading];
        }
        else
        {
          // maybe return an empty buffer so silence is played until we have data
          NSLog(@"resourceLoader: loading finished");
          [loadingRequest finishLoadingWithError:[self loaderCancelledError]];
        }
      }
    //});
  }

  return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader
  didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
  NSLog(@"resourceLoader didCancelLoadingRequest");
}

@end

#pragma mark - AVPlayerSink

@interface AVPlayerSink ()
@property (nonatomic) AVPlayer *ac3player;
@property (nonatomic) CMTimeRange timerange;
@end

@implementation AVPlayerSink

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if (object == _ac3player.currentItem && [keyPath isEqualToString:@"loadedTimeRanges"])
  {
    /*
    NSArray *timeRanges = (NSArray*)[change objectForKey:NSKeyValueChangeNewKey];
    if (timeRanges && [timeRanges count])
    {
      _timerange = [[timeRanges objectAtIndex:0]CMTimeRangeValue];
      float start =CMTimeGetSeconds(_timerange.start);
      float duration = CMTimeGetSeconds(_timerange.duration);
      NSLog(@"timerange.start %f, timerange.duration %f", start, duration);
    }
    */
  }
  else if ([keyPath isEqualToString:@"playbackBufferFull"] )
  {
    NSLog(@"player: playbackBufferFull");
    if (_ac3player.currentItem.playbackBufferFull)
    {
    }
  }
  else if ([keyPath isEqualToString:@"playbackBufferEmpty"] )
  {
    NSLog(@"player: playbackBufferEmpty");
    if (_ac3player.currentItem.playbackBufferEmpty)
    {
    }
  }
  else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"])
  {
    NSLog(@"player: playbackLikelyToKeepUp");
    if (_ac3player.currentItem.playbackLikelyToKeepUp)
    {
    }
  }
  else
  {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)startPlayback
{
  [self blahblah];
  [self dumpAudioComponents];

  [[NSNotificationCenter defaultCenter] addObserverForName:(__bridge NSString*)kAudioComponentRegistrationsChangedNotification
    object:NULL queue:NULL usingBlock:^(NSNotification * _Nonnull notification)
  {
    NSLog(@"kAudioComponentRegistrationsChangedNotification");
    // This block is called when the notification is received - obtain a list of available AUs which meet our criteria
    //NSArray<AVAudioUnitComponent*> *pAVAudioComponents = [[AVAudioUnitComponentManager sharedAudioUnitComponentManager]
    [self dumpAudioComponents];
  }];


  //NSString * const extension = @"eac3";
  //NSString * testPath = [[NSBundle mainBundle] pathForResource: @"sample1-5.1" ofType: extension];
  NSString * const extension = @"ec3";
  NSString * testPath = [[NSBundle mainBundle] pathForResource: @"out_2" ofType: extension];

  int reader = open(testPath.UTF8String, O_RDONLY, 00666);

  std::string tmpBufferFile = [NSTemporaryDirectory() UTF8String];
  tmpBufferFile += "avaudio.ec3";
  unlink(tmpBufferFile.c_str());
  int writer = open(tmpBufferFile.c_str(), O_CREAT | O_WRONLY | O_APPEND | O_SYNC, 00666);
  fsync(writer);

  // 2304 = 256 * 9
  ResourceLoader *resourceloader = [[ResourceLoader alloc] initWithFrameBytes:2304];

  // needs leading dir ('fake') or pathExtension in ResourceLoader will fail
  NSMutableString *url = [NSMutableString stringWithString:@"mrmc_streaming://fake/dummy."];
  [url appendString:extension];
  NSURL *ac3URL = [NSURL URLWithString: url];
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:ac3URL options:nil];
/*
  for (NSString *mime in [AVURLAsset audiovisualTypes])
    NSLog(@"AVURLAsset audiovisualTypes:%@", mime);

  for (NSString *mime in [AVURLAsset audiovisualMIMETypes])
    NSLog(@"AVURLAsset audiovisualMIMETypes:%@", mime);
*/
  [asset.resourceLoader setDelegate:resourceloader queue:dispatch_get_main_queue()];

  AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];
  [playerItem addObserver:self forKeyPath:@"playbackBufferFull" options:NSKeyValueObservingOptionNew context:playbackBufferFull];
  [playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:playbackBufferEmpty];
  [playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:playbackLikelyToKeepUp];
  [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];

  _ac3player = [[AVPlayer alloc] initWithPlayerItem:playerItem];
  _ac3player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
  _ac3player.automaticallyWaitsToMinimizeStalling = NO;
  _ac3player.currentItem.canUseNetworkResourcesForLiveStreamingWhilePaused = YES;

  AVPlayerStatus status;
  char* transferBuffer = new char[65536];
  while (1)
  {
    ssize_t bytes = read(reader, transferBuffer, 4096);
    if (bytes > 0)
      bytes = write(writer, transferBuffer, bytes);

    status = [_ac3player status];
    if (status != AVPlayerStatusUnknown)
    {
      NSLog(@"player: %s", status == AVPlayerStatusReadyToPlay ? "AVPlayerStatusReadyToPlay":"AVPlayerStatusFailed");
      break;
    }
    usleep(10*1000);
  }
  [_ac3player play];

  while (1)
  {
    ssize_t bytes = read(reader, transferBuffer, 65536);
    if (bytes > 0)
      bytes = write(writer, transferBuffer, bytes);

    float currentTime = CMTimeGetSeconds([playerItem currentTime]);
    float bufferedTime = resourceloader.bufferedTime;
    if (currentTime > 0.0f)
    {
      resourceloader.currentTime = currentTime;

      NSLog(@"player: currentTime %f, bufferedTime %f",
        currentTime, bufferedTime - currentTime);
    }

    static bool blahblahOnce = true;
    if (blahblahOnce)
    {
      [self blahblah];
      blahblahOnce = false;
    }

    /*
      // besides fourCC also the bsid in cookie created by CMAudioFormatDescriptionGetMagicCookie needs to be fixed
      NSRange cookieBsidRange = NSMakeRange(2, 1);
      uint8_t cookieBsidByte[1];
      [ac3Info getBytes:cookieBsidByte range:cookieBsidRange];
      // keep fscod, replace bsid with 0x10. This can happen, if bsid=0x10 frames are embedded as substream inside bsid=0x06 frames.
      cookieBsidByte[0] = (cookieBsidByte[0] & 0xC0) | (0x10 << 1);
      [ac3Info replaceBytesInRange:cookieBsidRange withBytes:cookieBsidByte length:1];
    */

    /*
    int err;
    UInt32 size1;
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
    AudioComponentDescription descr = {0};
    descr.componentType = kAudioUnitType_Output;
    NSArray *components = [[AVAudioUnitComponentManager sharedAudioUnitComponentManager] componentsMatchingDescription: descr];

    unsigned long componentsCount = [components count];
    for (int k = 0; k < componentsCount; ++k)
    {
      AVAudioUnitComponent *component = [components objectAtIndex:k];
      NSLog(@"%d, component name: %@", k, component.name);
      NSLog(@"%d, component typeName: %@", k, component.typeName);

    }
    */

    /*
    NSArray *tagNames = [[AVAudioUnitComponentManager sharedAudioUnitComponentManager] standardLocalizedTagNames];

    unsigned long tagNamesCount = [tagNames count];
    for (int k = 0; k < tagNamesCount; ++k)
    {
      NSString *tagName = [tagNames objectAtIndex:k];
      NSLog(@"%d, component tagName: %@", k, tagName);

    }
    */

    static bool dumpaudioTracks = true;
    if (dumpaudioTracks)
    {
      dumpaudioTracks = false;
      NSArray *audioTracks = [playerItem tracks];
      if (audioTracks && [audioTracks count])
      {
        float estimatedSize = 0.0 ;
        AVPlayerItemTrack *audioTrack =  [audioTracks objectAtIndex:0];
        AVAssetTrack *avAssetTrack = [audioTrack assetTrack];
        if (avAssetTrack && avAssetTrack.formatDescriptions)
        {
          float rate = ([avAssetTrack estimatedDataRate] / 8); // convert bits per second to bytes per second
          float seconds = CMTimeGetSeconds([avAssetTrack timeRange].duration);
          estimatedSize += seconds * rate;
          for (id formatDescription in avAssetTrack.formatDescriptions)
          {
              NSLog(@"estimatedSize %f, formatDescription:  %@", estimatedSize, formatDescription);
              //CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)formatDescription;
              //CMVideoCodecType codec = CMFormatDescriptionGetMediaSubType(desc);
          }
        }
      }
    }


    status = [_ac3player status];
    if (status == AVPlayerStatusFailed)
      break;

    usleep(250*1000);
  }

  sleep(10000);
  
  //_ac3player = NULL;
}

-(void)blahblah
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
  BOOL isDolbyAtmosAvailable = [[AVAudioSession sharedInstance] isDolbyAtmosAvailable];
  NSLog(@"isDolbyAtmosAvailable: %d", isDolbyAtmosAvailable);
  BOOL isDolbyDigitalEncoderAvailable = [[AVAudioSession sharedInstance] isDolbyDigitalEncoderAvailable];
  NSLog(@"isDolbyDigitalEncoderAvailable: %d", isDolbyDigitalEncoderAvailable);
  BOOL isHardwareFormatFixedToMultiChannel = [[AVAudioSession sharedInstance] isHardwareFormatFixedToMultiChannel];
  NSLog(@"isHardwareFormatFixedToMultiChannel: %d", isHardwareFormatFixedToMultiChannel);

  double currentHardwareSampleRate = [[AVAudioSession sharedInstance] currentHardwareSampleRate];
  NSLog(@"currentHardwareSampleRate: %f", currentHardwareSampleRate);
  long long currentHardwareInputNumberOfChannels = [[AVAudioSession sharedInstance] currentHardwareInputNumberOfChannels];
  NSLog(@"currentHardwareInputNumberOfChannels: %lld", currentHardwareInputNumberOfChannels);
  long long currentHardwareOutputNumberOfChannels = [[AVAudioSession sharedInstance] currentHardwareOutputNumberOfChannels];
  NSLog(@"currentHardwareOutputNumberOfChannels: %lld", currentHardwareOutputNumberOfChannels);
}

- (void) dumpAudioComponents
{
  AudioComponentDescription searchDesc = { 0, 0, 0, 0, 0 };
  AudioComponent comp = NULL;
  while (true)
  {
    comp = AudioComponentFindNext(comp, &searchDesc);
    if (comp == NULL)
      break;

    AudioComponentDescription desc;
    if (AudioComponentGetDescription(comp, &desc)) continue;

    NSLog(@"componentType %@", XXStringForOSType(desc.componentType));
    NSLog(@"componentSubType %@", XXStringForOSType(desc.componentSubType));
    NSLog(@"componentManufacturer %@", XXStringForOSType(desc.componentManufacturer));
  }
}

@end

