//
//  AVPlayerSink.m
//  ac3_tests
//
//  Created by Scott D. Davilla on 3/22/16.
//  Copyright © 2016 RootCoder, LLC. All rights reserved.
//

#import "AVPlayerSink.h"
#import "AERingBuffer.h"

#import <AVFoundation/AVFoundation.h>

#pragma mark - ResourceLoader

static void *playbackLikelyToKeepUp = &playbackLikelyToKeepUp;
static void *playbackBufferEmpty = &playbackBufferEmpty;
static void *playbackBufferFull = &playbackBufferFull;

@interface ResourceLoader : NSObject <AVAssetResourceLoaderDelegate>
@property (nonatomic) FILE *fp;
@end

@implementation ResourceLoader
- (NSError *)loaderCancelledError
{
  NSError *error = [[NSError alloc] initWithDomain:@"ResourceLoaderErrorDomain"
    code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Resource loader cancelled"}];

  return error;
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
    contentRequest.contentLength = INT_MAX;
    // must be 'NO' to get player to start playing immediately
    contentRequest.byteRangeAccessSupported = NO;
    NSLog(@"resourceLoader contentRequest %@", contentRequest);
  }

  AVAssetResourceLoadingDataRequest* dataRequest = loadingRequest.dataRequest;
  if (dataRequest)
  {
    NSLog(@"resourceLoader dataRequest %@", dataRequest);
    //dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger reqLen = dataRequest.requestedLength;
      if (reqLen == 2)
      {
        // avplayer always 1st reads two bytes to check for a content tag.
        // ac3/eac3 has two byte tag of 0x0b77, \v is vertical tab == 0x0b
        [dataRequest respondWithData:[NSData dataWithBytes:"\vw" length:2]];
        [loadingRequest finishLoading];
      }
      else
      {
        int bytesRequested = (int)reqLen;

        // Pull audio from buffer
        //int const buffersize = 10752 * 4;
        int const buffersize = 1536 * 80;
        char buffer[buffersize];
        size_t availableBytes = 0;
        size_t requestedBytes = buffersize;
        if (dataRequest.requestedOffset == 0)
        {
          // a requestedOffset of zero needs the two byte ac3 tag
          buffer[0] = 0x0b;
          buffer[1] = 0x77;
          availableBytes = fread(&buffer[2], 1, requestedBytes - 2, _fp);
          availableBytes += 2;
        }
        else
        {
          availableBytes = fread(&buffer, 1, requestedBytes, _fp);
        }

        useconds_t wait = 2 * 32; // each ac3/eac3 frame is 32ms
        usleep(wait * 1000);

        // check if we have enough data
        if (!availableBytes)
        {
          NSLog(@"resourceLoader availableBytes %lu bytes", availableBytes);
          // maybe return an empty buffer so silence is played until we have data
        }
        else
        {
          size_t bytesToCopy = bytesRequested > availableBytes ? availableBytes : bytesRequested;
          if (bytesToCopy > 0)
          {
              NSData *data = [NSData dataWithBytes:buffer length:bytesToCopy];
              [dataRequest respondWithData:data];
              NSLog(@"resourceLoader sending %lu bytes", (unsigned long)[data length]);
          }
        }

        if (availableBytes)
          [loadingRequest finishLoading];
        else
        {
          NSLog(@"resourceLoader loading finished");
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

@end

@implementation AVPlayerSink

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if (object == _ac3player.currentItem && [keyPath isEqualToString:@"loadedTimeRanges"])
  {
    NSArray *timeRanges = (NSArray*)[change objectForKey:NSKeyValueChangeNewKey];
    if (timeRanges && [timeRanges count])
    {
      CMTimeRange timerange = [[timeRanges objectAtIndex:0]CMTimeRangeValue];
      NSLog(@"resourceLoader timerange.start %f", CMTimeGetSeconds(timerange.start));
      NSLog(@"resourceLoader timerange.duration %f", CMTimeGetSeconds(timerange.duration));
    }
  }
  else if ([keyPath isEqualToString:@"playbackBufferFull"] )
  {
    NSLog(@"resourceLoader playbackBufferFull");
    if (_ac3player.currentItem.playbackBufferEmpty)
    {
    }
  }
  else if ([keyPath isEqualToString:@"playbackBufferEmpty"] )
  {
    NSLog(@"resourceLoader playbackBufferEmpty");
    if (_ac3player.currentItem.playbackBufferEmpty)
    {
    }
  }
  else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"])
  {
    NSLog(@"resourceLoader playbackLikelyToKeepUp");
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
  NSString * const extension = @"eac3";

  size_t bytes_read;
  NSString * testPath = [[NSBundle mainBundle] pathForResource: @"sample1-5.1" ofType: extension];
  FILE *fp = fopen(testPath.UTF8String, "rb");
  if (fp)
  {
    char buffer[2];
    bytes_read = fread(buffer, 1, 2, fp);
  }
  ResourceLoader *resourceloader = [ResourceLoader new];
  resourceloader.fp = fp;

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

  AVPlayerStatus status;
  while (1)
  {
    status = [_ac3player status];
    if (status != AVPlayerStatusUnknown)
    {
      NSLog(@"status: %ld", (long)status);
      break;
    }
    usleep(10*1000);
  }
  [_ac3player play];

  while (1)
  {
    CMTime currentTime = [playerItem currentTime];
    NSLog(@"currentTime: %f", CMTimeGetSeconds(currentTime));

    status = [_ac3player status];
    if (status == AVPlayerStatusFailed)
      break;

    usleep(25*1000);
  }

  sleep(10000);
  
  _ac3player = NULL;
}

@end

