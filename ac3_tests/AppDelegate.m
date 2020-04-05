//
//  AppDelegate.m
//  ac3_tests
//
//  Created by Scott D. Davilla on 3/22/16.
//  Copyright © 2016 RootCoder, LLC. All rights reserved.
//

#import "AppDelegate.h"
#import "AVPlayerSink.h"
#import "AudioConverterSink.h"
#import "AudioConverterSink.h"
#import "AVSampleBufferAudioRendererSink.h"
#import <AVFoundation/AVFoundation.h>

void DumpAudioDescriptions(const char *why)
{
  if (strlen(why) > 0)
    NSLog(@"DumpAudioDescriptions: %s", why);

  AVAudioSession *myAudioSession = [AVAudioSession sharedInstance];

  NSArray *currentInputs = myAudioSession.currentRoute.inputs;
  unsigned long count_in = [currentInputs count];
  NSLog(@"DumpAudioDescriptions: input count = %lu", count_in);
  for (int k = 0; k < count_in; ++k)
  {
    AVAudioSessionPortDescription *portDesc = [currentInputs objectAtIndex:k];
    NSLog(@"DumpAudioDescriptions: portName, %s", [portDesc.portName UTF8String]);
    for (AVAudioSessionChannelDescription *channel in portDesc.channels)
    {
      NSLog(@"DumpAudioDescriptions: channelLabel, %d", channel.channelLabel);
      NSLog(@"DumpAudioDescriptions: channelName , %s", [channel.channelName UTF8String]);
    }
  }

  NSArray *currentOutputs = myAudioSession.currentRoute.outputs;
  unsigned long  count_out = [currentOutputs count];
  NSLog(@"DumpAudioDescriptions: output count = %lu", count_out);
  for (int k = 0; k < count_out; ++k)
  {
    AVAudioSessionPortDescription *portDesc = [currentOutputs objectAtIndex:k];
    NSLog(@"DumpAudioDescriptions : portName, %s", [portDesc.portName UTF8String]);
    for (AVAudioSessionChannelDescription *channel in portDesc.channels)
    {
      NSLog(@"DumpAudioDescriptions: channelLabel, %d", channel.channelLabel);
      NSLog(@"DumpAudioDescriptions: channelName , %s", [channel.channelName UTF8String]);
    }
  }
}

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  // Override point for customization after application launch.
  [self registerAudioRouteNotifications];

  NSError *err = NULL;
  [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault routeSharingPolicy:AVAudioSessionRouteSharingPolicyLongFormAudio options:0 error:nil];

  //if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&err])
  //{
  //  NSLog(@"AVAudioSession setCategory failed: %ld", (long)err.code);
  //}
  err = nil;
  if (![[AVAudioSession sharedInstance] setMode:AVAudioSessionModeMoviePlayback error:&err])
  {
    NSLog(@"AVAudioSession setMode failed: %ld", (long)err.code);
  }
  err = nil;

  // need to fetch maximumOutputNumberOfChannels when active
  long channels = [[AVAudioSession sharedInstance] maximumOutputNumberOfChannels];
  channels = 8;
  [[AVAudioSession sharedInstance] setPreferredOutputNumberOfChannels: channels error: &err];

  if (![[AVAudioSession sharedInstance] setActive: YES error: &err])
  {
    NSLog(@"AVAudioSession setActive YES failed: %ld", (long)err.code);
  }

  // check that we got the number of channels what we asked for
  if (channels != [[AVAudioSession sharedInstance] outputNumberOfChannels])
    NSLog(@"number of channels do not match: asked %ld, is %ld", channels, (long)[[AVAudioSession sharedInstance] outputNumberOfChannels]);

  return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
  // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
  // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
  // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
  // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
  // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
  [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
  // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
  [NSThread detachNewThreadSelector:@selector(enterForegroundDelayed:) toTarget:self withObject:nil];
}

- (void)applicationWillTerminate:(UIApplication *)application {
  // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
  // Saves changes in the application's managed object context before the application terminates.
  [self saveContext];
}

- (void)enterForegroundDelayed:(id)arg
{
  //AVPlayerSink *mSink = [AVPlayerSink alloc];
  //AudioConverterSink *mSink = [AudioConverterSink alloc];
  AVSampleBufferAudioRendererSink *mSink = [AVSampleBufferAudioRendererSink alloc];
  [mSink startPlayback];
}

#pragma mark - Core Data stack

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

- (NSURL *)applicationCachesDirectory {
    // The directory the application uses to store the Core Data store file. This code uses a directory named "com.mrmc.ac3_tests" in the application's caches directory.
    return [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
}

- (NSManagedObjectModel *)managedObjectModel {
    // The managed object model for the application. It is a fatal error for the application not to be able to find and load its model.
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"ac3_tests" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    // The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it.
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    
    // Create the coordinator and store
    
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    NSURL *storeURL = [[self applicationCachesDirectory] URLByAppendingPathComponent:@"ac3_tests.sqlite"];
    NSError *error = nil;
    NSString *failureReason = @"There was an error creating or loading the application's saved data.";
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        // Report any error we got.
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[NSLocalizedDescriptionKey] = @"Failed to initialize the application's saved data";
        dict[NSLocalizedFailureReasonErrorKey] = failureReason;
        dict[NSUnderlyingErrorKey] = error;
        error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:9999 userInfo:dict];
        // Replace this with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    
    return _persistentStoreCoordinator;
}


- (NSManagedObjectContext *)managedObjectContext {
    // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.)
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (!coordinator) {
        return nil;
    }
    _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    return _managedObjectContext;
}

#pragma mark - Core Data Saving support

- (void)saveContext {
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        NSError *error = nil;
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
}

- (void)registerAudioRouteNotifications
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  //register to audio route notifications
  [nc addObserver:self selector:@selector(handleAudioRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
  [nc addObserver:self selector:@selector(handleAudioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
}

- (void)unregisterAudioRouteNotifications
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  //unregister faudio route notifications
  [nc removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
  [nc removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
}

- (void)handleAudioRouteChange:(NSNotification *)notification
{
  // Your tests on the Audio Output changes will go here
  NSInteger routeChangeReason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue];
  switch (routeChangeReason)
  {
    case AVAudioSessionRouteChangeReasonUnknown:
        NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonUnknown");
        break;
    case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
        // an audio device was added
        NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonNewDeviceAvailable");
        DumpAudioDescriptions("AVAudioSessionRouteChangeReasonNewDeviceAvailable");
        break;
    case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
        // a audio device was removed
        NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonOldDeviceUnavailable");
        DumpAudioDescriptions("AVAudioSessionRouteChangeReasonOldDeviceUnavailable");
        break;
    case AVAudioSessionRouteChangeReasonCategoryChange:
        // called at start - also when other audio wants to play
        NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonCategoryChange");
        DumpAudioDescriptions("AVAudioSessionRouteChangeReasonCategoryChange");
        break;
    case AVAudioSessionRouteChangeReasonOverride:
        NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonOverride");
        break;
    case AVAudioSessionRouteChangeReasonWakeFromSleep:
        NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonWakeFromSleep");
        break;
    case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
        NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory");
        break;
    case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
        NSLog(@"routeChangeReason : AVAudioSessionRouteChangeReasonRouteConfigurationChange");
        DumpAudioDescriptions("AVAudioSessionRouteChangeReasonRouteConfigurationChange");
        break;
    default:
        NSLog(@"routeChangeReason : unknown notification %ld", (long)routeChangeReason);
        break;
  }
}
- (void)handleAudioInterrupted:(NSNotification *)notification
{
  NSNumber *interruptionType = notification.userInfo[AVAudioSessionInterruptionTypeKey];
  switch (interruptionType.integerValue)
  {
    case AVAudioSessionInterruptionTypeBegan:
      // • Audio has stopped, already inactive
      // • Change state of UI, etc., to reflect non-playing state
      NSLog(@"audioInterrupted : AVAudioSessionInterruptionTypeBegan");
      // pausedForAudioSessionInterruption = YES;
      break;
    case AVAudioSessionInterruptionTypeEnded:
      {
        // • Make session active
        // • Update user interface
        NSNumber *interruptionOption = notification.userInfo[AVAudioSessionInterruptionOptionKey];
        BOOL shouldResume = interruptionOption.integerValue == AVAudioSessionInterruptionOptionShouldResume;
        if (shouldResume == YES)
        {
          // if shouldResume you should continue playback.
          NSLog(@"audioInterrupted : AVAudioSessionInterruptionTypeEnded: resume=yes");
        }
        else
        {
          NSLog(@"audioInterrupted : AVAudioSessionInterruptionTypeEnded: resume=no");
        }
        // pausedForAudioSessionInterruption = NO;
      }
      break;
    default:
      break;
  }
}

@end
