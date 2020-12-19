//
//  VideoTrimmerPlugin.m
//  Runner
//
//  Created by Onyemaechi Okafor on 2/5/19.
//  Copyright © 2019 The Chromium Authors. All rights reserved.
//

#import <Photos/Photos.h>
#import "VideoTrimmerPlugin.h"

@interface NSError (FlutterError)
@property(readonly, nonatomic) FlutterError *flutterError;
@end

@implementation NSError (FlutterError)
- (FlutterError *)flutterError {
    return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %d", (int)self.code]
                               message:self.domain
                               details:self.localizedDescription];
}
@end

@interface UIImage (BitmapData)
- (NSData *)bitmapData;
- (NSData *)bitmapFileHeaderData;
- (NSData *)bitmapDataWithFileHeader;
@end



# pragma pack(push, 1)
typedef struct s_bitmap_header
{
    // Bitmap file header
    UInt16 fileType;
    UInt32 fileSize;
    UInt16 reserved1;
    UInt16 reserved2;
    UInt32 bitmapOffset;
    
    // DIB Header
    UInt32 headerSize;
    UInt32 width;
    UInt32 height;
    UInt16 colorPlanes;
    UInt16 bitsPerPixel;
    UInt32 compression;
    UInt32 bitmapSize;
    UInt32 horizontalResolution;
    UInt32 verticalResolution;
    UInt32 colorsUsed;
    UInt32 colorsImportant;
} t_bitmap_header;
#pragma pack(pop)

@implementation UIImage (BitmapData)

- (NSData *)bitmapData
{
    NSData          *bitmapData = nil;
    CGImageRef      image = self.CGImage;
    CGContextRef    context = NULL;
    CGColorSpaceRef colorSpace;
    UInt8           *rawData;
    
    size_t bitsPerPixel = 32;
    size_t bitsPerComponent = 8;
    size_t bytesPerPixel = bitsPerPixel / bitsPerComponent;
    
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    
    size_t bytesPerRow = width * bytesPerPixel;
    size_t bufferLength = bytesPerRow * height;
    
    colorSpace = CGColorSpaceCreateDeviceRGB();
    
    if (colorSpace)
    {
        // Allocate memory for raw image data
        rawData = (UInt8 *)calloc(bufferLength, sizeof(UInt8));
        
        if (rawData)
        {
            CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
            context = CGBitmapContextCreate(rawData,
                                            width,
                                            height,
                                            bitsPerComponent,
                                            bytesPerRow,
                                            colorSpace,
                                            bitmapInfo);
            
            if (context)
            {
                CGRect rect = CGRectMake(0, 0, width, height);
                
                CGContextTranslateCTM(context, 0, height);
                CGContextScaleCTM(context, 1.0, -1.0);
                CGContextDrawImage(context, rect, image);
                
                bitmapData = [NSData dataWithBytes:rawData length:bufferLength];
                
                CGContextRelease(context);
            }
            
            free(rawData);
        }
        
        CGColorSpaceRelease(colorSpace);
    }
    
    return bitmapData;
}

- (NSData *)bitmapFileHeaderData
{
    CGImageRef image = self.CGImage;
    UInt32     width = (UInt32)CGImageGetWidth(image);
    UInt32     height = (UInt32)CGImageGetHeight(image);
    
    t_bitmap_header header;
    
    header.fileType = 0x4D42;
    header.fileSize = (height * width * 4) + 54;
    header.reserved1 = 0x0000;
    header.reserved2 = 0x0000;
    header.bitmapOffset = 0x00000036;
    header.headerSize = 0x00000028;
    header.width = width;
    header.height = height;
    header.colorPlanes = 0x0001;
    header.bitsPerPixel = 0x0020;
    header.compression = 0x00000000;
    header.bitmapSize = height * width * 4;
    header.horizontalResolution = 0x00000B13;
    header.verticalResolution = 0x00000B13;
    header.colorsUsed = 0x00000000;
    header.colorsImportant = 0x00000000;
    
    return [NSData dataWithBytes:&header length:sizeof(t_bitmap_header)];
}

- (NSData *)bitmapDataWithFileHeader
{
    NSMutableData *data = [NSMutableData dataWithData:[self bitmapFileHeaderData]];
    [data appendData:[self bitmapData]];
    
    return [NSData dataWithData:data];
}

@end

@interface ThumbnailStreamHandler : NSObject <FlutterStreamHandler>
@property FlutterEventSink eventSink;
@end

@implementation ThumbnailStreamHandler

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    return nil;
}
@end

@interface FetchVideoThumbnail : NSObject
@property(readonly, nonatomic) NSString *path;
@property(readonly, nonatomic) BOOL started;
@property(nonatomic) FlutterEventChannel *eventChannel;
@property(readonly, nonatomic) AVAssetImageGenerator *generator;
@property(nonatomic) ThumbnailStreamHandler *thumbnailStreamHandler;

- (instancetype)initWithPath:(NSString *)filename requestId:(NSNumber *)requestId messenger:(NSObject<FlutterBinaryMessenger> *)messenger;
- (void)startAt:(CGFloat)start endAt:(CGFloat)end totalThumbsCount:(int64_t) int64_t size:(CGSize)size queue:(dispatch_queue_t)queue;
- (void)cancel;
+ (void)extractThumbnailWithResult:(FlutterResult)result file:(NSString *)filename size:(CGSize)size queue:(dispatch_queue_t)queue;
@end

@implementation FetchVideoThumbnail{
}
- (instancetype)initWithPath:(NSString *)filename requestId:(NSNumber *)requestId messenger:(NSObject<FlutterBinaryMessenger> *)messenger{
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _path = filename;
    NSURL *videoUrl = [NSURL fileURLWithPath:filename];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoUrl options:nil];
    _generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    FlutterEventChannel *eventChannel =
    [FlutterEventChannel eventChannelWithName:[NSString stringWithFormat:@"github.com/peerwaya/gotok/video_trimmer/thumbnailStream/%@", requestId]
                              binaryMessenger:messenger];
    
    _thumbnailStreamHandler = [[ThumbnailStreamHandler alloc] init];
    [eventChannel setStreamHandler:_thumbnailStreamHandler];
    return self;
}

- (void)startAt:(CGFloat)start endAt:(CGFloat)end totalThumbsCount:(int64_t)totalThumbsCount size:(CGSize)size queue:(dispatch_queue_t)queue{
    if (_started) {
        return;
    }
    __weak FetchVideoThumbnail *weakSelf = self;
    dispatch_async(queue, ^{
        FetchVideoThumbnail *strongSelf = weakSelf;
        CGFloat interval = (end - start) / (totalThumbsCount - 1);
        NSMutableArray *array = [[NSMutableArray alloc]init]; //alloc
        for (int64_t i=0; i < totalThumbsCount; ++i) {
            CGFloat frameTime = start + interval * i;
            CMTime time = CMTimeMakeWithSeconds(frameTime, 600);
            [array addObject:[NSValue valueWithCMTime:time]];
        }
        strongSelf.generator.appliesPreferredTrackTransform = true;
        strongSelf.generator.requestedTimeToleranceBefore = kCMTimeZero;
        strongSelf.generator.requestedTimeToleranceAfter = kCMTimeZero;
        //Can set this to improve performance if target size is known before hand
        strongSelf.generator.maximumSize = size;
        [strongSelf.generator generateCGImagesAsynchronouslyForTimes:array completionHandler:^(CMTime requestedTime, CGImageRef image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error) {
            if (!image) {
                return;
            }
            UIImage *generatedImage=[UIImage imageWithCGImage:image];
            // CGDataProviderRef dataProviderRef = CGImageGetDataProvider(image);
            // NSData *data = UIImagePNGRepresentation(generatedImage);
            NSData *data = [generatedImage bitmapDataWithFileHeader];//UIImageJPEGRepresentation(generatedImage, 1.0);
            if (!data) {
                return;
            }
            FlutterStandardTypedData *flutterBytes = [FlutterStandardTypedData typedDataWithBytes: data];
            NSMutableDictionary *imageBuffer = [NSMutableDictionary dictionary];
            imageBuffer[@"eventType"] = @"result";
            imageBuffer[@"width"] = [NSNumber numberWithUnsignedLong:generatedImage.size.width];
            imageBuffer[@"height"] = [NSNumber numberWithUnsignedLong:generatedImage.size.height];
            imageBuffer[@"data"] = flutterBytes;
            strongSelf.thumbnailStreamHandler.eventSink(imageBuffer);
            /**
             NSImage *image = [[NSImage alloc] initWithCGImage:img size:NSSizeFromCGSize(CGSizeMake(100, 100))];
             NSBitmapImageRep *imgRep = (NSBitmapImageRep *)[[image representations] objectAtIndex: 0];
             NSData *data = [imgRep representationUsingType: NSPNGFileType properties: @{}];
             **/
        }];
    });

    _started = YES;
}

+ (void)extractThumbnailWithResult:(FlutterResult)result file:(NSString *)filename size:(CGSize)size queue:(dispatch_queue_t)queue{
    NSURL *videoUrl = [NSURL fileURLWithPath:filename];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoUrl options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    dispatch_async(queue, ^{
        generator.appliesPreferredTrackTransform = true;
        //Can set this to improve performance if target size is known before hand
        generator.maximumSize = size;
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        generator.requestedTimeToleranceAfter = kCMTimeZero;
        CMTime time = CMTimeMakeWithSeconds(1.0, 600);
        CMTime actualTime = CMTimeMake(0, 0);
        NSError* error;
        CGImageRef image = [generator copyCGImageAtTime:time actualTime:&actualTime error:&error];
        if (error) {
            result(error.flutterError);
            return;
        }
        if (!image) {
            result([FlutterError errorWithCode:@"image_not_found"
                                       message:@"Could not generate thumbnail"
                                       details:nil]);
            return;
        }
        UIImage *generatedImage=[UIImage imageWithCGImage:image];
        // CGDataProviderRef dataProviderRef = CGImageGetDataProvider(image);
        // NSData *data = UIImagePNGRepresentation(generatedImage);
        NSData *data = [generatedImage bitmapDataWithFileHeader];//UIImageJPEGRepresentation(generatedImage, 1.0);
        if (!data) {
            result([FlutterError errorWithCode:@"invalid_data"
                                       message:@"Could not generate thumbnail data"
                                       details:nil]);
            return;
        }
        FlutterStandardTypedData *flutterBytes = [FlutterStandardTypedData typedDataWithBytes: data];
        NSMutableDictionary *imageBuffer = [NSMutableDictionary dictionary];
        imageBuffer[@"width"] = [NSNumber numberWithUnsignedLong:generatedImage.size.width];
        imageBuffer[@"height"] = [NSNumber numberWithUnsignedLong:generatedImage.size.height];
        imageBuffer[@"data"] = flutterBytes;
        result(imageBuffer);
    });
}

+ (void)extractThumbnailsWithResult:(FlutterResult)flutterResult file:(NSString *)filename startAt:(CGFloat)start endAt:(CGFloat)end totalThumbsCount:(int64_t)totalThumbsCount size:(CGSize)size queue:(dispatch_queue_t)queue{
    NSURL *videoUrl = [NSURL fileURLWithPath:filename];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoUrl options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    dispatch_async(queue, ^{
        CGFloat interval = (end - start) / (totalThumbsCount - 1);
        NSMutableArray<NSValue*> *array = [[NSMutableArray alloc]init];
        CGFloat durationSeconds = CMTimeGetSeconds(asset.duration);
        NSLog(@"DURATION IN SECS:%f", durationSeconds);
        for (int64_t i=0; i < totalThumbsCount; ++i) {
            CGFloat frameTime = start + interval * i;
            NSLog(@"SECONDS AT INDEX:%lld = %f", i, frameTime);
            CMTime time = CMTimeMakeWithSeconds(frameTime, 600);
            [array addObject:[NSValue valueWithCMTime:time]];
        }
        generator.appliesPreferredTrackTransform = true;
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        generator.requestedTimeToleranceAfter = kCMTimeZero;
        //Can set this to improve performance if target size is known before hand
        NSMutableArray *ret = [[NSMutableArray alloc]init]; //alloc
        generator.maximumSize = size;
        [generator generateCGImagesAsynchronouslyForTimes:array completionHandler:^(CMTime requestedTime, CGImageRef image, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error) {
            NSValue* value = [NSValue valueWithCMTime:requestedTime];
            BOOL isLast = [value isEqualToValue:[array objectAtIndex:array.count - 1]];
            if (!image) {
                if (isLast) {
                    flutterResult(ret);
                }
                return;
            }
            UIImage *generatedImage=[UIImage imageWithCGImage:image];
            // CGDataProviderRef dataProviderRef = CGImageGetDataProvider(image);
            // NSData *data = UIImagePNGRepresentation(generatedImage);
            NSData *data = [generatedImage bitmapDataWithFileHeader];//UIImageJPEGRepresentation(generatedImage, 1.0);
            if (!data) {
                if (isLast) {
                    flutterResult(ret);
                }
                return;
            }
            FlutterStandardTypedData *flutterBytes = [FlutterStandardTypedData typedDataWithBytes: data];
            NSMutableDictionary *imageBuffer = [NSMutableDictionary dictionary];
            imageBuffer[@"eventType"] = @"result";
            imageBuffer[@"width"] = [NSNumber numberWithUnsignedLong:generatedImage.size.width];
            imageBuffer[@"height"] = [NSNumber numberWithUnsignedLong:generatedImage.size.height];
            imageBuffer[@"data"] = flutterBytes;
            [ret addObject:imageBuffer];
            if (isLast) {
                flutterResult(ret);
            }
        }];
    });
}

- (void)cancel {
    [self.generator cancelAllCGImageGeneration];
    _started = NO;
}

- (void)dealloc
{
    
    NSLog(@"dealloc called for FetchVideoThumbnail");
}


@end


@interface VideoTrimmerPlugin ()
@property(nonatomic, retain) FlutterMethodChannel *channel;
-(void)writeVideoToPhotoLibrary:(NSURL *)url result:(FlutterResult)result;
@end

@implementation VideoTrimmerPlugin {
    NSMutableDictionary<NSNumber *, FetchVideoThumbnail *> *_listeners;
    NSObject<FlutterBinaryMessenger> *_messenger;
    int _nextListenerHandle;
    dispatch_queue_t _processingQueue;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _messenger = messenger;
    _listeners = [NSMutableDictionary<NSNumber *, FetchVideoThumbnail *> dictionary];
    return self;
}

+ (void)registerWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
                                     methodChannelWithName:@"github.com/peerwaya/gotok/video_trimmer"
                                     binaryMessenger:[registrar messenger]];
    VideoTrimmerPlugin *instance = [[VideoTrimmerPlugin alloc] initWithMessenger:[registrar messenger]];
    instance.channel = channel;
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"trimVideo"]) {
        NSDictionary* argsMap = call.arguments;
        NSString *inputFile = argsMap[@"inputFile"];
        NSURL *inputUrl = [NSURL fileURLWithPath:inputFile];
        NSString *outputFile = argsMap[@"outputFile"];
        NSURL *outputUrl = [NSURL fileURLWithPath:outputFile];
        CGFloat start = [argsMap[@"startMs"] floatValue]/1000;
        CGFloat end = [argsMap[@"endMs"] floatValue]/1000;
        [self trimVideo:inputUrl outputUrl:outputUrl startTime:start endTime:end result:result];
    } else if ([call.method isEqualToString:@"initVideoThumbsRequest"]) {
        NSNumber *handle = [NSNumber numberWithInt:_nextListenerHandle++];
        NSDictionary* argsMap = call.arguments;
        NSString *videoFile = argsMap[@"videoFile"];
        FetchVideoThumbnail *thumnailTask = [[FetchVideoThumbnail alloc] initWithPath:videoFile requestId:handle messenger:_messenger];
        _listeners[handle] = thumnailTask;
        result(handle);
    }else if ([call.method isEqualToString:@"startVideoThumbsRequest"]) {
        NSDictionary* argsMap = call.arguments;
        NSNumber *handle = call.arguments[@"handle"];
        FetchVideoThumbnail *thumnailTask = [_listeners objectForKey:handle];
        if (!thumnailTask) {
            result(@NO);
            return;
        }
        CGFloat width = [argsMap[@"width"] floatValue];
        CGFloat height = [argsMap[@"height"] floatValue];
        int64_t totalThumbsCount = [argsMap[@"totalThumbsCount"] intValue];
        CGFloat start = [argsMap[@"startMs"] floatValue] / 1000;
        CGFloat end = [argsMap[@"endMs"] floatValue] / 1000;
        [thumnailTask startAt:start endAt:end totalThumbsCount:totalThumbsCount size:CGSizeMake(width, height) queue:self.processingQueue];
        result([NSNumber numberWithBool:thumnailTask.started]);
    }else if ([call.method isEqualToString:@"extractThumbnail"]) {
        NSDictionary* argsMap = call.arguments;
        NSString *path = call.arguments[@"inputFile"];
        CGFloat width = [argsMap[@"width"] floatValue];
        CGFloat height = [argsMap[@"height"] floatValue];
        [FetchVideoThumbnail extractThumbnailWithResult:result file:path size:CGSizeMake(width, height) queue:self.processingQueue];
    }else if ([call.method isEqualToString:@"extractThumbnails"]) {
        NSDictionary* argsMap = call.arguments;
        NSString *path = call.arguments[@"inputFile"];
        CGFloat width = [argsMap[@"width"] floatValue];
        CGFloat height = [argsMap[@"height"] floatValue];
        CGFloat start = [argsMap[@"startMs"] floatValue] /1000;
        CGFloat end = [argsMap[@"endMs"] floatValue] /1000;
        int64_t totalThumbsCount = [argsMap[@"totalThumbsCount"] intValue];
        [FetchVideoThumbnail extractThumbnailsWithResult:result file:path startAt:start endAt:end totalThumbsCount:totalThumbsCount size:CGSizeMake(width, height) queue:self.processingQueue ];
    }else if ([call.method isEqualToString:@"stopVideoThumbsRequest"]) {
        NSNumber *handle = call.arguments[@"handle"];
        [[_listeners objectForKey:handle] cancel];
        result(nil);
    }else if ([call.method isEqualToString:@"removeVideoThumbsRequest"]) {
        NSNumber *handle = call.arguments[@"handle"];
        [[_listeners objectForKey:handle] cancel];
        [_listeners removeObjectForKey:handle];
        result(nil);
    }else if ([call.method isEqualToString:@"dispose"]) {
        [self releaseListeners];
        result(nil);
    }else if([@"saveToLibrary" isEqualToString:call.method]){
        NSDictionary* argsMap = call.arguments;
        NSString *path = argsMap[@"inputFile"];
        NSURL *outputUrl = [NSURL fileURLWithPath:path];
        dispatch_async(self.processingQueue, ^{
            [self writeVideoToPhotoLibrary:outputUrl result:result];
        });
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void) releaseListeners {
    for (NSNumber *handle in _listeners) {
        FetchVideoThumbnail *thumnailTask = _listeners[handle];
        [thumnailTask cancel];
    }
    [_listeners removeAllObjects];
}

- (void)dealloc
{
    [self releaseListeners];
    NSLog(@"dealloc called for VideoTrimmerPlugin");
}

- (dispatch_queue_t)processingQueue {
    if (!_processingQueue) {
        _processingQueue =
        dispatch_queue_create("github.com/peerwaya/gotok/video_trimmer", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_processingQueue,
                                  dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    }
    return _processingQueue;
}

-(void)trimVideo:(NSURL*)inputUrl outputUrl:(NSURL*)outputUrl startTime:(CGFloat)startTime endTime:(CGFloat)endTime result:(FlutterResult)result{
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:inputUrl options:nil];
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
    
    exportSession.outputURL = outputUrl;
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.outputFileType = AVFileTypeMPEG4;
    CMTime start = CMTimeMakeWithSeconds(startTime, 600);
    CMTime duration = CMTimeSubtract(CMTimeMakeWithSeconds(endTime, 600), start);
    CMTimeRange range = CMTimeRangeMake(start, duration);
    exportSession.timeRange = range;
    [exportSession exportAsynchronouslyWithCompletionHandler:^(void)
     {
         switch (exportSession.status) {
             case AVAssetExportSessionStatusCompleted:
                 result([NSNumber numberWithInt:0]);
                 break;
             case AVAssetExportSessionStatusFailed:
                 NSLog(@"Failed:%@",exportSession.error);
                 result([FlutterError errorWithCode:[NSString stringWithFormat:@"trimVideo Failed"]
                                            message:exportSession.error.domain
                                            details:exportSession.error.localizedDescription]);
                 break;
             case AVAssetExportSessionStatusCancelled:
                 NSLog(@"Canceled:%@",exportSession.error);
                 result([FlutterError errorWithCode:[NSString stringWithFormat:@"trimVideo Canceled"]
                                            message:exportSession.error.domain
                                            details:exportSession.error.localizedDescription]);
                 break;
             default:
                 break;
         }
     }];
}

-(void)writeVideoToPhotoLibrary:(NSURL *)url result:(FlutterResult)result{
    PHPhotoLibrary *library = [PHPhotoLibrary sharedPhotoLibrary];
    [library performChanges:^{
        PHAssetCreationRequest *request =  [PHAssetCreationRequest creationRequestForAsset];
        [request addResourceWithType: PHAssetResourceTypeVideo fileURL:url options:nil];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        NSString *file = [url path];
        result(file);
    }];
    
}
@end
