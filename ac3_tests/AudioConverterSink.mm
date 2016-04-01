//
//  AudioConverterSink.m
//  ac3_tests
//
//  Created by Scott D. Davilla on 3/22/16.
//  Copyright © 2016 RootCoder, LLC. All rights reserved.
//

#import "AudioConverterSink.h"
#import "AERingBuffer.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <algorithm>

typedef struct AudioConverterIO
{
  FILE       *fp;
	char       *buffer;
	UInt32			buffersize;
	UInt32			frames;
  int         framesize;
	UInt32      packets;
	AudioStreamBasicDescription stream_format;
	AudioStreamPacketDescription *packet_desciption;
} AudioConverterIO;

static void setAVAudioSessionProperties(NSTimeInterval bufferseconds, double samplerate)
{
  // drawin docs explicity says,
  // deavtivate the session before changing the values
  NSError *err = nil;
  AVAudioSession *mySession = [AVAudioSession sharedInstance];

  // deavivate the session
  if (![[AVAudioSession sharedInstance] setActive: NO error: &err])
    NSLog(@"AVAudioSession setActive NO failed: %ld", (long)err.code);

  // change the sample rate
  [mySession setPreferredSampleRate: samplerate error: &err];
  if (err != nil)
    NSLog(@"%s setPreferredSampleRate failed", __PRETTY_FUNCTION__);

  // change the i/o buffer duration
  err = nullptr;
  [mySession setPreferredIOBufferDuration: bufferseconds error: &err];
  if (err != nil)
    NSLog(@"%s setPreferredIOBufferDuration failed", __PRETTY_FUNCTION__);

  // reactivate the session
  if (![[AVAudioSession sharedInstance] setActive: YES error: &err])
    NSLog(@"AVAudioSession setActive YES failed: %ld", (long)err.code);

  // check that we got the samperate what we asked for
  if (samplerate != [mySession sampleRate])
    NSLog(@"sampleRate do not match: asked %f, is %f", samplerate, [mySession sampleRate]);
}

static OSStatus renderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
  const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData)
{
  AERingBuffer *ringbuffer = (AERingBuffer*)inRefCon;

  for (unsigned int i = 0; i < ioData->mNumberBuffers; i++)
  {
    unsigned int wanted = ioData->mBuffers[i].mDataByteSize;
    unsigned int bytes = std::min(ringbuffer->GetReadSize(), wanted);
    ringbuffer->Read((unsigned char*)ioData->mBuffers[i].mData, bytes);

    if (bytes == 0)
    {
      // Apple iOS docs say kAudioUnitRenderAction_OutputIsSilence provides a hint to
      // the audio unit that there is no audio to process. and you must also explicitly
      // set the buffers contents pointed at by the ioData parameter to 0.
      memset(ioData->mBuffers[i].mData, 0x00, ioData->mBuffers[i].mDataByteSize);
      *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
    }
    else if (bytes < wanted)
    {
      // zero out what we did not copy over (underflow)
      uint8_t *empty = (uint8_t*)ioData->mBuffers[i].mData + bytes;
      memset(empty, 0x00, wanted - bytes);
    }
  }

  return noErr;
}

static OSStatus converterCallback(AudioConverterRef inAudioConverter,
  UInt32 *ioNumberDataPackets, AudioBufferList *ioData,
  AudioStreamPacketDescription **outDataPacketDescription,
  void *inUserData)
{
  OSStatus err = noErr;
  AudioConverterIO *afio = (AudioConverterIO*)inUserData;

  // figure out how much to read
	if (*ioNumberDataPackets > afio->packets)
    *ioNumberDataPackets = afio->packets;

  // read from the file
  size_t requestedBytes = afio->framesize;
  size_t availableBytes = fread(afio->buffer, 1, requestedBytes, afio->fp);
  NSLog(@"converterCallback requestedBytes %zu, availableBytes %zu", requestedBytes, availableBytes);
  if (availableBytes != requestedBytes)
  {
    if (availableBytes == 0)
    {
      if (feof(afio->fp))
        NSLog(@"Read frame eof");
      else
        NSLog(@"Read frame error: %s", strerror(errno));
    }
    else
    {
      NSLog(@"Read frame underflow");
    }
    *ioNumberDataPackets = 0;
  }
  else
  {
    // put the data pointer into the buffer list
    ioData->mBuffers[0].mData = afio->buffer;
    ioData->mBuffers[0].mDataByteSize = afio->framesize;
    ioData->mBuffers[0].mNumberChannels = afio->stream_format.mChannelsPerFrame;

    if (outDataPacketDescription)
    {
      if (afio->packet_desciption)
      {
        afio->packet_desciption->mStartOffset = 0;
        afio->packet_desciption->mVariableFramesInPacket = *ioNumberDataPackets;
        afio->packet_desciption->mDataByteSize = afio->framesize;
        *outDataPacketDescription = afio->packet_desciption;
      }
      else
        *outDataPacketDescription = NULL;
    }
  }

	return err;
}

#pragma mark - AudioConverterSink

@interface AudioConverterSink ()
@property (nonatomic) AERingBuffer *m_buffer;
@property (nonatomic) AudioStreamBasicDescription m_inputFormat;
@property (nonatomic) AudioStreamBasicDescription m_outputFormat;
@end

@implementation AudioConverterSink

- (void)setupAudioConverter:(id)arg
{
  // must match size between ac3/eac3 sync repeats (0x0b77)
  //int framesize = 1536; // silence.ac3
  //int framesize = 1792; // sample1-5.1.ac3
  int framesize = 1280; // sample1-5.1.eac3
  NSString * const filename = @"sample1-5.1";
  NSString * const filename_extension = @"sample1-5.1.eac3";
  NSString * const extension = @"eac3";

  _m_buffer = NULL;
  _m_inputFormat = {0};
  _m_outputFormat = {0};

  int err;
  NSString *soundFile= [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: filename_extension];
  CFURLRef soundURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)soundFile, kCFURLPOSIXPathStyle, false);

  AudioFileID mAudioFile;
  err = AudioFileOpenURL(soundURL, kAudioFileReadPermission, 0, &mAudioFile);
  //  
  UInt32 size1 = sizeof(_m_inputFormat);
  //    
  err = AudioFileGetProperty(mAudioFile, kAudioFilePropertyDataFormat, &size1, &_m_inputFormat);

  //                  11  d  a  c  3
  //  AC3 -> 00 00 00 0B 64 61 63 33 10 3D 60
  //  AC3 -> 00 00 00 0B 64 61 63 33 10 3D 40
  // mov_write_ac3_tag
  //                  13  d  e  c  3
  // EAC3 -> 00 00 00 0D 64 65 63 33 02 80 20 0F 00
  // mov_write_eac3_tag
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

	_m_outputFormat.mFormatID = kAudioFormatLinearPCM;
	_m_outputFormat.mSampleRate = 48000;
  _m_outputFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked;
  _m_outputFormat.mFramesPerPacket = 1;
	_m_outputFormat.mChannelsPerFrame = _m_inputFormat.mChannelsPerFrame;
	_m_outputFormat.mBitsPerChannel = sizeof(float ) << 3;
  _m_outputFormat.mBytesPerPacket = _m_outputFormat.mChannelsPerFrame * _m_outputFormat.mBitsPerChannel / 8;
	_m_outputFormat.mBytesPerFrame  = _m_outputFormat.mFramesPerPacket  * _m_outputFormat.mBytesPerPacket;

  AudioConverterRef audioconverter;
  err = AudioConverterNew(&_m_inputFormat, &_m_outputFormat, &audioconverter);
  if( err != noErr)
    NSLog(@"AudioConverterNew %d", err);

  // set the decoder magic cookie (not required for ac3/eac3 as info is in frame headers)
  /*
  if (magicCookie) {
    err = AudioConverterSetProperty(audioconverter, kAudioConverterDecompressionMagicCookie, magicCookieSize, magicCookie);
    if( err != noErr)
        NSLog(@"kAudioConverterDecompressionMagicCookie %d", err);
  }
  */

  UInt32 size = sizeof(_m_inputFormat);
	err = AudioConverterGetProperty(audioconverter, kAudioConverterCurrentInputStreamDescription, &size, &_m_inputFormat);
  if( err != noErr)
    NSLog(@"kAudioConverterCurrentInputStreamDescription %d", err);

  size = sizeof(_m_outputFormat);
	err = AudioConverterGetProperty(audioconverter, kAudioConverterCurrentOutputStreamDescription, &size, &_m_outputFormat);
  if( err != noErr)
    NSLog(@"kAudioConverterCurrentOutputStreamDescription %d", err);

  // set up our input context for reading audio
  // from file into input buffers
  AudioConverterIO input_ctx = {0};
  input_ctx.packets = 1;
  input_ctx.framesize = framesize;
	input_ctx.buffersize = input_ctx.framesize * 8;
	input_ctx.buffer = (char*)malloc(input_ctx.buffersize);
	input_ctx.stream_format = _m_inputFormat;
  input_ctx.packet_desciption = (AudioStreamPacketDescription*)malloc(input_ctx.packets);
  //
  NSString * testPath = [[NSBundle mainBundle] pathForResource: filename ofType: extension];
  FILE *fp = fopen(testPath.UTF8String, "rb");
  if (fp)
    input_ctx.fp = fp;

    // set up our output buffers
	uint32_t output_buffersize = 1024 * _m_outputFormat.mBytesPerFrame;
	char *output_buffer = (char*)malloc(output_buffersize);

  unsigned int buffer_size = output_buffersize;
  _m_buffer = new AERingBuffer(buffer_size*2);

  [NSThread detachNewThreadSelector:@selector(setupAudoRenderer:) toTarget:self withObject:nil];

	while (1)
  {
		// set up output buffer list
		AudioBufferList output_bufferlist = {0};
		output_bufferlist.mNumberBuffers = 1;
		output_bufferlist.mBuffers[0].mNumberChannels = _m_inputFormat.mChannelsPerFrame;
		output_bufferlist.mBuffers[0].mDataByteSize = output_buffersize;
		output_bufferlist.mBuffers[0].mData = output_buffer;

    // run the auto converter
    AudioStreamPacketDescription *outputPktDescs = NULL;
		uint32_t ioOutputDataPackets = output_buffersize / _m_outputFormat.mBytesPerPacket;
		err = AudioConverterFillComplexBuffer(audioconverter, converterCallback,
      &input_ctx, &ioOutputDataPackets, &output_bufferlist, outputPktDescs);
    if (err)
      NSLog(@"Error converterDec %d", err);
    if (ioOutputDataPackets == 0)
    {
			// this is the EOF conditon
			break;
		}
		UInt32 inNumBytes = output_bufferlist.mBuffers[0].mDataByteSize;
    NSLog(@"ioOutputDataPackets %d, inNumBytes %d", ioOutputDataPackets, inNumBytes);

    while (_m_buffer->GetWriteSize() < inNumBytes)
    { // no space to write - wait for a bit
      usleep(5 * 1000);
    }

    unsigned int write_frames = std::min(ioOutputDataPackets, _m_buffer->GetWriteSize() / _m_outputFormat.mBytesPerFrame);
    if (write_frames)
      _m_buffer->Write((unsigned char*)output_bufferlist.mBuffers[0].mData, inNumBytes);
  }
}

- (bool)setupAudoRenderer:(id)arg
{
  AudioUnit m_audioUnit;
  OSStatus status = noErr;

  // Audio Unit Setup
  // Describe a default output unit.
  AudioComponentDescription description = {};
  description.componentType = kAudioUnitType_Output;
  description.componentSubType = kAudioUnitSubType_RemoteIO;
  description.componentManufacturer = kAudioUnitManufacturer_Apple;

  // Get component
  AudioComponent component;
  component = AudioComponentFindNext(NULL, &description);
  status = AudioComponentInstanceNew(component, &m_audioUnit);
  if (status != noErr)
  {
    NSLog(@"%s error creating audioUnit (error: %d)", __PRETTY_FUNCTION__, (int)status);
    return false;
  }

  // set the buffer size (in seconds), this affects the number of samples
  // that get rendered every time the audio callback is fired.
  double samplerate = _m_outputFormat.mSampleRate;
  NSTimeInterval bufferseconds = 256 * _m_outputFormat.mChannelsPerFrame / _m_outputFormat.mSampleRate;
  NSLog(@"%s setting samplerate %f", __PRETTY_FUNCTION__, samplerate);
  NSLog(@"%s setting buffer duration to %f", __PRETTY_FUNCTION__, bufferseconds);
  setAVAudioSessionProperties(bufferseconds, samplerate);
 
	// Get the output samplerate for knowing what was setup in reality
  Float64 realisedSampleRate = [[AVAudioSession sharedInstance] sampleRate];
  if (_m_outputFormat.mSampleRate != realisedSampleRate)
  {
    NSLog(@"%s couldn't set requested samplerate %d, coreaudio will resample to %d instead", __PRETTY_FUNCTION__, (int)_m_outputFormat.mSampleRate, (int)realisedSampleRate);
  }

  // Set the output stream format
  UInt32 ioDataSize = sizeof(AudioStreamBasicDescription);
  status = AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat,
    kAudioUnitScope_Input, 0, &_m_outputFormat, ioDataSize);
  if (status != noErr)
  {
    NSLog(@"%s error setting stream format on audioUnit (error: %d)", __PRETTY_FUNCTION__, (int)status);
    return false;
  }

  // Attach a render callback on the unit
  AURenderCallbackStruct callbackStruct = {0};
  callbackStruct.inputProc = renderCallback;
  callbackStruct.inputProcRefCon = _m_buffer;
  status = AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_SetRenderCallback,
    kAudioUnitScope_Input, 0, &callbackStruct, sizeof(callbackStruct));
  if (status != noErr)
  {
    NSLog(@"%s error setting render callback for audioUnit (error: %d)", __PRETTY_FUNCTION__, (int)status);
    return false;
  }

  status = AudioUnitInitialize(m_audioUnit);
	if (status != noErr)
  {
    NSLog(@"%s error initializing audioUnit (error: %d)", __PRETTY_FUNCTION__, (int)status);
    return false;
  }
  
  AudioOutputUnitStart(m_audioUnit);

  return false;
}

- (void)startPlayback
{
  [NSThread detachNewThreadSelector:@selector(setupAudioConverter:) toTarget:self withObject:nil];
}

@end

