//
//  NatShare.m
//  NatShare
//
//  Created by Yusuf Olokoba on 4/14/18.
//  Copyright © 2018 Yusuf Olokoba. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>
#import "UnityInterface.h"

typedef void (*ShareCallback) (bool);

static ShareCallback shareCallback;
static PHAssetCollection* RetrieveAlbumForName (NSString* name);

void NSRegisterCallbacks (ShareCallback share) {
    shareCallback = share;
}

bool NSShareItems(NSArray* shareItems) {
    UIActivityViewController* controller = [[UIActivityViewController alloc] initWithActivityItems:shareItems applicationActivities:nil];
    UIViewController* vc = UnityGetGLViewController();
    controller.modalPresentationStyle = UIModalPresentationPopover;
    controller.popoverPresentationController.sourceView = vc.view;
    // Pause Unity
    UnityPause( true );
    // Register for completion callback (thanks srorke!)
    [controller setCompletionWithItemsHandler:^(UIActivityType activityType, BOOL completed, NSArray* returnedItems, NSError* activityError) {
        // Unpause Unity
        UnityPause( false );
        shareCallback(completed);
    }];
    [vc presentViewController:controller animated:YES completion:nil];
    return true;
}

bool NSShareText (const char* text) {
    NSArray* items=@[[NSString stringWithUTF8String:text]];
    return NSShareItems(items);
}

bool NSShareImageWithText (uint8_t* pngData, int dataSize,const char* text) {
    NSData* data = [NSData dataWithBytes:pngData length:dataSize];
    UIImage* image = [UIImage imageWithData:data];
    NSArray* items=@[image,[NSString stringWithUTF8String:text]];
    return NSShareItems(items);
}

bool NSShareImage (uint8_t* pngData, int dataSize) {
    NSData* data = [NSData dataWithBytes:pngData length:dataSize];
    UIImage* image = [UIImage imageWithData:data];
    NSArray* items=@[image];
    return NSShareItems(items);
}


bool NSShareMedia (const char* mediaPath) {
    NSString* path = [NSString stringWithUTF8String:mediaPath];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSLog(@"NatShare Error: Failed to share media because no file was found at path '%@'", path);
        return false;
    }
    NSArray* items=@[[NSURL fileURLWithPath:path]];
    return NSShareItems(items);
}

bool NSShareMediaWithText (const char* mediaPath,const char* text) {
    NSString* path = [NSString stringWithUTF8String:mediaPath];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSLog(@"NatShare Error: Failed to share media because no file was found at path '%@'", path);
        return false;
    }
    NSArray* items=@[[NSURL fileURLWithPath:path],[NSString stringWithUTF8String:text]];
    return NSShareItems(items);
}

bool NSSaveImageToCameraRoll (uint8_t* pngData, int dataSize, const char* album) {
    NSData* data = [NSData dataWithBytes:pngData length:dataSize];
    NSString* albumName = [NSString stringWithUTF8String:album];
    if (PHPhotoLibrary.authorizationStatus == PHAuthorizationStatusDenied) {
        NSLog(@"NatShare Error: Failed to save image to camera roll because user denied photo library permission");
        return false;
    }
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            NSLog(@"NatShare Error: Failed to save image to camera roll because user denied photo library permission");
            return;
        }
        PHAssetCollection* photoAlbum = albumName.length ? RetrieveAlbumForName(albumName) : nil; // Apparently you can't nest calls to `PHPhotoLibrary::performChanges`
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            PHAssetCreationRequest* creationRequest = [PHAssetCreationRequest creationRequestForAsset];
            [creationRequest addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
            if (photoAlbum) {
                PHObjectPlaceholder* placeholder = creationRequest.placeholderForCreatedAsset;
                PHFetchResult* currentAlbumContents = [PHAsset fetchAssetsInAssetCollection:photoAlbum options:nil];
                PHAssetCollectionChangeRequest* albumAddRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:photoAlbum assets:currentAlbumContents];
                [albumAddRequest addAssets:@[placeholder]];
            }
        } completionHandler:nil];
    }];
    return true;
}

bool NSSaveMediaToCameraRoll (const char* path, const char* album, bool copy) { // INCOMPLETE
    NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    NSString* albumName = [NSString stringWithUTF8String:album];
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        NSLog(@"NatShare Error: Failed to save media to camera roll because no file was found at path: %@", url.path);
        return false;
    }
    if (PHPhotoLibrary.authorizationStatus == PHAuthorizationStatusDenied) {
        NSLog(@"NatShare Error: Failed to save media to camera roll because user denied photo library permission");
        return false;
    }
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            NSLog(@"NatShare Error: Failed to save media to camera roll because user denied photo library permission");
            return;
        }
        PHAssetCollection* photoAlbum = albumName.length ? RetrieveAlbumForName(albumName) : nil; // Apparently you can't nest calls to `PHPhotoLibrary::performChanges`
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            PHAssetResourceCreationOptions* options = [PHAssetResourceCreationOptions new];
            options.shouldMoveFile = !copy;
            PHAssetCreationRequest* creationRequest = [PHAssetCreationRequest creationRequestForAsset];
            CFStringRef fileExtension = (__bridge CFStringRef)url.pathExtension;
            CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
            if (UTTypeConformsTo(fileUTI, kUTTypeImage))
                [creationRequest addResourceWithType:PHAssetResourceTypePhoto fileURL:url options:options];
            else if (UTTypeConformsTo(fileUTI, kUTTypeMovie))
                [creationRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:url options:options];
            else if (UTTypeConformsTo(fileUTI, kUTTypeAudio))
                [creationRequest addResourceWithType:PHAssetResourceTypeAudio fileURL:url options:options];
            else {
                NSLog(@"NatShare Error: Failed to save media to camera roll because media is neither image nor video");
                return;
            }
            if (photoAlbum) {
                PHObjectPlaceholder* placeholder = creationRequest.placeholderForCreatedAsset;
                PHFetchResult* currentAlbumContents = [PHAsset fetchAssetsInAssetCollection:photoAlbum options:nil];
                PHAssetCollectionChangeRequest* albumAddRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:photoAlbum assets:currentAlbumContents];
                [albumAddRequest addAssets:@[placeholder]];
            }
        } completionHandler:nil];
    }];
    return true;
}

bool NSGetThumbnail (const char* videoPath, float time, void** pixelBuffer, int* width, int* height) {
    NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:videoPath]];
    AVAssetImageGenerator* generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset assetWithURL:url]];
    generator.appliesPreferredTrackTransform = true;
    NSError* error = nil;
    CGImageRef image = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(time, 1) actualTime:NULL error:&error];
    if (error) {
        NSLog(@"NatShare Error: Unable to retrieve thumbnail with error: %@", error);
        return false;
    }
    *width = (int)CGImageGetWidth(image);
    *height = (int)CGImageGetHeight(image);
    *pixelBuffer = malloc(*width * *height * 4);
    CFDataRef rawData = CGDataProviderCopyData(CGImageGetDataProvider(image));
    if (!rawData) {
        NSLog(@"NatShare Error: Unable to retrieve thumbnail because its data cannot be accessed");
        return false;
    }
    vImage_Buffer input = {
        (void*)CFDataGetBytePtr(rawData),
        CGImageGetHeight(image),
        CGImageGetWidth(image),
        CGImageGetBytesPerRow(image)
    }, output = {
        *pixelBuffer,
        input.height,
        input.width,
        input.width * 4
    };
    vImageVerticalReflect_ARGB8888(&input, &output, kvImageNoFlags);
    CFRelease(rawData);
    CGImageRelease(image);
    return true;
}

void NSFreeThumbnail (const intptr_t pixelBuffer) {
    free((void*)pixelBuffer);
}

PHAssetCollection* RetrieveAlbumForName (NSString* name) {
    PHFetchOptions* options = [PHFetchOptions new];
    options.predicate = [NSPredicate predicateWithFormat:@"title = %@", name];
    PHFetchResult* collection = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:options];
    if (collection.firstObject)
        return collection.firstObject;
    NSError* creationError;
    __block PHObjectPlaceholder* albumPlaceholder;
    [PHPhotoLibrary.sharedPhotoLibrary performChangesAndWait:^{
        PHAssetCollectionChangeRequest* creationRequest = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:name];
        albumPlaceholder = creationRequest.placeholderForCreatedAssetCollection;
    } error: &creationError];
    if (creationError) {
        NSLog(@"NatShare Error: Failed to create album for saving media. Media will not be added to an album");
        return nil;
    }
    collection = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[albumPlaceholder.localIdentifier] options:nil];
    return collection.firstObject;
}
