// Compiled into Telegram's own gallery view. No dylib injection or runtime hooking.
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>

static NSMutableDictionary<NSString *, NSDictionary *> *vgConvertedItems;
static const void *vgNoteKey = &vgNoteKey;
static const void *vgVoiceKey = &vgVoiceKey;
static const void *vgBusyKey = &vgBusyKey;

NSDictionary *VGPreparedVideoForIdentifier(NSString *identifier) {
    if (!identifier.length) return nil;
    @synchronized ([TGMediaPickerGalleryInterfaceView class]) {
        NSDictionary *item = vgConvertedItems[identifier];
        NSURL *file = item[@"url"];
        if (item && ![[NSFileManager defaultManager] fileExistsAtPath:file.path]) {
            [vgConvertedItems removeObjectForKey:identifier];
            return nil;
        }
        return item;
    }
}
static void VGStoreConversion(NSString *identifier, NSDictionary *item) {
    if (!identifier.length) return;
    @synchronized ([TGMediaPickerGalleryInterfaceView class]) {
        if (!vgConvertedItems) vgConvertedItems = [NSMutableDictionary dictionary];
        if (item) vgConvertedItems[identifier] = item;
        else [vgConvertedItems removeObjectForKey:identifier];
    }
}

// A circular image viewport represents the actual center crop of every frame.
// Pinch and pan change the same normalized transform used in AVFoundation export.
@interface VGVideoCropScreen : UIViewController
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) void (^didApply)(CGFloat zoom, CGPoint pan);
@end

@implementation VGVideoCropScreen {
    UIView *_circle;
    UIImageView *_imageView;
    CGFloat _zoom;
    CGFloat _pinchBase;
    CGPoint _offset;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _zoom = _pinchBase = 1;
    self.view.backgroundColor = UIColor.blackColor;
    _circle = [UIView new]; _circle.clipsToBounds = YES;
    [self.view addSubview:_circle];
    _imageView = [[UIImageView alloc] initWithImage:self.image];
    [_circle addSubview:_imageView];
    [_circle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(vgPan:)]];
    [_circle addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(vgPinch:)]];
    UILabel *tip = [UILabel new]; tip.tag = 9001;
    tip.text = @"حرّك الصورة بإصبعك وكبّر بإصبعين";
    tip.textColor = UIColor.whiteColor; tip.textAlignment = NSTextAlignmentCenter;
    tip.adjustsFontSizeToFitWidth = YES; [self.view addSubview:tip];
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem]; cancel.tag = 9002;
    [cancel setTitle:@"إلغاء" forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(vgCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cancel];
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem]; reset.tag = 9003;
    [reset setTitle:@"إعادة ضبط" forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(vgReset) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:reset];
    UIButton *apply = [UIButton buttonWithType:UIButtonTypeSystem]; apply.tag = 9004;
    [apply setTitle:@"اعتماد الفيديو نوت" forState:UIControlStateNormal];
    apply.backgroundColor = UIColor.systemBlueColor; apply.tintColor = UIColor.whiteColor;
    apply.layer.cornerRadius = 12;
    [apply addTarget:self action:@selector(vgApply) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:apply];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat s = MIN(320, MIN(w - 32, h * 0.5));
    _circle.frame = CGRectMake((w - s) / 2, (h - s) / 2 - 24, s, s);
    _circle.layer.cornerRadius = s / 2;
    [self.view viewWithTag:9001].frame = CGRectMake(16, CGRectGetMaxY(_circle.frame) + 12, w - 32, 28);
    CGFloat y = h - MAX(24, self.view.safeAreaInsets.bottom) - 56;
    [self.view viewWithTag:9002].frame = CGRectMake(16, y, 90, 48);
    [self.view viewWithTag:9003].frame = CGRectMake(w / 2 - 50, y, 100, 48);
    [self.view viewWithTag:9004].frame = CGRectMake(w - 174, y, 162, 48);
    [self vgUpdateCrop];
}
- (void)vgUpdateCrop {
    if (!self.image || _circle.bounds.size.width < 1) return;
    CGFloat side = _circle.bounds.size.width, w = self.image.size.width, h = self.image.size.height;
    if (w < 1 || h < 1) return;
    CGFloat scale = MAX(side / w, side / h) * _zoom;
    w *= scale; h *= scale;
    CGFloat maxX = (w - side) / 2, maxY = (h - side) / 2;
    _offset.x = MAX(-maxX, MIN(maxX, _offset.x));
    _offset.y = MAX(-maxY, MIN(maxY, _offset.y));
    _imageView.frame = CGRectMake((side - w) / 2 + _offset.x,
                                (side - h) / 2 + _offset.y, w, h);
}
- (void)vgPan:(UIPanGestureRecognizer *)gesture {
    CGPoint d = [gesture translationInView:_circle];
    _offset.x += d.x; _offset.y += d.y;
    [gesture setTranslation:CGPointZero inView:_circle];
    [self vgUpdateCrop];
}
- (void)vgPinch:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) _pinchBase = _zoom;
    _zoom = MAX(1, MIN(4, _pinchBase * gesture.scale));
    [self vgUpdateCrop];
}
- (void)vgCancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)vgReset { _zoom = 1; _offset = CGPointZero; [self vgUpdateCrop]; }
- (void)vgApply {
    CGFloat sx = (_imageView.bounds.size.width - _circle.bounds.size.width) / 2;
    CGFloat sy = (_imageView.bounds.size.height - _circle.bounds.size.height) / 2;
    CGPoint pan = CGPointMake(sx > 0.01 ? _offset.x / sx : 0,
                               sy > 0.01 ? _offset.y / sy : 0);
    CGFloat zoom = _zoom;
    void (^done)(CGFloat, CGPoint) = self.didApply;
    [self dismissViewControllerAnimated:YES completion:^{
        if (done) done(zoom, pan);
    }];
}
@end

@implementation TGMediaPickerGalleryInterfaceView (VGMediaConversion)
- (TGMediaAsset *)vgVideoAsset {
    id item = [self valueForKey:@"_currentItem"];
    id asset = [item respondsToSelector:@selector(asset)] ? [item valueForKey:@"asset"] : nil;
    if ([asset isKindOfClass:[TGCameraCapturedVideo class]])
        asset = ((TGCameraCapturedVideo *)asset).originalAsset;
    if (![asset isKindOfClass:[TGMediaAsset class]]) return nil;
    return ((TGMediaAsset *)asset).type == TGMediaAssetVideoType ? asset : nil;
}
- (BOOL)vgExportInProgress {
    return [objc_getAssociatedObject(self, vgBusyKey) boolValue];
}
- (void)vgAlert:(NSString *)message {
    UIViewController *controller = self.controller ? self.controller() : nil;
    if (!controller) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"VoidGram"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
- (void)vgShowProcessingAlert {
    [self vgAlert:@"الفيديو قيد التحويل. انتظر اكتمال المعالجة قبل الإرسال."];
}
- (void)vgInstallConversionControls {
    if (objc_getAssociatedObject(self, vgNoteKey)) return;
    UIButton *note = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButton *voice = [UIButton buttonWithType:UIButtonTypeSystem];
    [note setTitle:@"◉ Video Note" forState:UIControlStateNormal];
    [voice setTitle:@"♫ Voice" forState:UIControlStateNormal];
    for (UIButton *button in @[note, voice]) {
        button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        button.layer.cornerRadius = 18;
        button.tintColor = UIColor.whiteColor;
        button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
        button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        button.layer.borderWidth = 1;
        [self addSubview:button];
    }
    [note addTarget:self action:@selector(vgNoteTapped) forControlEvents:UIControlEventTouchUpInside];
    [voice addTarget:self action:@selector(vgVoiceTapped) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(self, vgNoteKey, note, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, vgVoiceKey, voice, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self vgUpdateConversionControls];
}
- (void)vgUpdateConversionControls {
    UIButton *note = objc_getAssociatedObject(self, vgNoteKey);
    UIButton *voice = objc_getAssociatedObject(self, vgVoiceKey);
    if (!note || !voice) return;
    TGMediaAsset *asset = [self vgVideoAsset];
    note.hidden = voice.hidden = (asset == nil);
    if (!asset) return;
    NSString *mode = VGPreparedVideoForIdentifier(asset.identifier)[@"mode"];
    UIColor *plain = [UIColor colorWithWhite:0.15 alpha:0.85];
    note.backgroundColor = [mode isEqualToString:@"note"] ? UIColor.systemBlueColor : plain;
    voice.backgroundColor = [mode isEqualToString:@"voice"] ? UIColor.systemBlueColor : plain;
    CGFloat x = MAX(8, self.safeAreaInsets.left + 8);
    CGFloat y = MAX(64, self.safeAreaInsets.top + 72);
    note.frame = CGRectMake(x, y, 104, 36);
    voice.frame = CGRectMake(x, y + 44, 104, 36);
    [self bringSubviewToFront:note];
    [self bringSubviewToFront:voice];
}
- (void)vgLoadAsset:(TGMediaAsset *)asset completion:(void (^)(AVAsset *))completion {
    PHVideoRequestOptions *opts = [PHVideoRequestOptions new];
    opts.networkAccessAllowed = YES;
    [[PHImageManager defaultManager] requestAVAssetForVideo:asset.backingAsset options:opts
        resultHandler:^(AVAsset *avAsset, AVAudioMix *mix, NSDictionary *info) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(avAsset); });
        }];
}
- (void)vgExport:(AVAsset *)source forAsset:(TGMediaAsset *)asset
           mode:(NSString *)mode zoom:(CGFloat)zoom pan:(CGPoint)pan {
    if (!asset.identifier.length || [self vgExportInProgress]) return;
    objc_setAssociatedObject(self, vgBusyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    VGStoreConversion(asset.identifier, nil);
    BOOL round = [mode isEqualToString:@"note"];
    AVAssetTrack *track = [source tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!track || (!round && [source tracksWithMediaType:AVMediaTypeAudio].count == 0)) {
        objc_setAssociatedObject(self, vgBusyKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self vgAlert:@"الفيديو ما يحتوي مسار صوتي أو فيديو صالح."];
        return;
    }
    NSTimeInterval originalDuration = CMTimeGetSeconds(source.duration);
    if (!isfinite(originalDuration) || originalDuration <= 0) originalDuration = 1;
    TGMediaEditingContext *editing = [self valueForKey:@"_editingContext"];
    id item = [self valueForKey:@"_currentItem"];
    id editable = [item respondsToSelector:@selector(asset)] ? [item valueForKey:@"asset"] : asset;
    TGVideoEditAdjustments *adjustments = (TGVideoEditAdjustments *)[editing adjustmentsForItem:editable];
    NSTimeInterval start = adjustments.trimApplied ? MAX(0, adjustments.trimStartValue) : 0;
    NSTimeInterval end = adjustments.trimApplied ? MIN(originalDuration, adjustments.trimEndValue) : originalDuration;
    NSTimeInterval length = MAX(0.1, end - start);
    if (round) length = MIN(60, length);
    NSString *fileName = [NSString stringWithFormat:@"vg%@_%ld_%@.%@",
         round ? @"note" : @"voice", (long)MAX(1, lround(length)), [NSUUID UUID].UUIDString,
         round ? @"mp4" : @"m4a"];
    NSURL *output = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:source
        presetName:round ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A];
    if (!export) {
        objc_setAssociatedObject(self, vgBusyKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self vgAlert:@"ما نكدر نحول هذا الفيديو."];
        return;
    }
    export.outputURL = output;
    export.outputFileType = round ? AVFileTypeMPEG4 : AVFileTypeAppleM4A;
    export.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(start, 600), CMTimeMakeWithSeconds(length, 600));
    if (round) {
        CGRect rect = CGRectApplyAffineTransform(CGRectMake(0, 0,
            track.naturalSize.width, track.naturalSize.height), track.preferredTransform);
        CGFloat width = fabs(rect.size.width), height = fabs(rect.size.height);
        if (width < 1 || height < 1) {
            objc_setAssociatedObject(self, vgBusyKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self vgAlert:@"أبعاد الفيديو غير صالحة."];
            return;
        }
        CGFloat scale = MAX(640.0 / width, 640.0 / height) * MAX(1, MIN(4, zoom));
        CGFloat resultWidth = width * scale, resultHeight = height * scale;
        CGFloat dx = -(resultWidth - 640) / 2 + pan.x * (resultWidth - 640) / 2;
        CGFloat dy = -(resultHeight - 640) / 2 + pan.y * (resultHeight - 640) / 2;
        CGAffineTransform correction = CGAffineTransformConcat(track.preferredTransform,
            CGAffineTransformMakeTranslation(-rect.origin.x, -rect.origin.y));
        CGAffineTransform t = CGAffineTransformConcat(
            CGAffineTransformConcat(correction, CGAffineTransformMakeScale(scale, scale)),
            CGAffineTransformMakeTranslation(dx, dy));
        AVMutableVideoCompositionLayerInstruction *layer =
            [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
        [layer setTransform:t atTime:kCMTimeZero];
        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, source.duration);
        instruction.layerInstructions = @[layer];
        AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
        composition.renderSize = CGSizeMake(640, 640);
        composition.frameDuration = CMTimeMake(1, 30);
        composition.instructions = @[instruction];
        export.videoComposition = composition;
    }
    __weak TGMediaPickerGalleryInterfaceView *weakSelf = self;
    [export exportAsynchronouslyWithCompletionHandler:^{
        BOOL ok = export.status == AVAssetExportSessionStatusCompleted &&
                  [[NSFileManager defaultManager] fileExistsAtPath:output.path];
        dispatch_async(dispatch_get_main_queue(), ^{
            TGMediaPickerGalleryInterfaceView *view = weakSelf;
            if (!view) return;
            objc_setAssociatedObject(view, vgBusyKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (ok) VGStoreConversion(asset.identifier, @{
                @"url":output, @"mode":mode, @"duration":@(length), @"fileName":fileName
            });
            else [view vgAlert:export.error.localizedDescription ?: @"فشل تحويل الفيديو."];
            [view vgUpdateConversionControls];
        });
    }];
}
- (void)vgVoiceTapped {
    TGMediaAsset *asset = [self vgVideoAsset];
    if (!asset || [self vgExportInProgress]) return;
    if ([VGPreparedVideoForIdentifier(asset.identifier)[@"mode"] isEqualToString:@"voice"]) {
        VGStoreConversion(asset.identifier, nil); [self vgUpdateConversionControls]; return;
    }
    [self vgLoadAsset:asset completion:^(AVAsset *source) {
        if (source) [self vgExport:source forAsset:asset mode:@"voice" zoom:1 pan:CGPointZero];
        else [self vgAlert:@"تعذر فتح الفيديو."];
    }];
}
- (void)vgNoteTapped {
    TGMediaAsset *asset = [self vgVideoAsset];
    if (!asset || [self vgExportInProgress]) return;
    if ([VGPreparedVideoForIdentifier(asset.identifier)[@"mode"] isEqualToString:@"note"]) {
        VGStoreConversion(asset.identifier, nil); [self vgUpdateConversionControls]; return;
    }
    [self vgLoadAsset:asset completion:^(AVAsset *source) {
        if (!source) { [self vgAlert:@"تعذر فتح الفيديو."]; return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:source];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(640, 640);
            CGImageRef frame = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:NULL];
            UIImage *image = frame ? [UIImage imageWithCGImage:frame] : nil;
            if (frame) CGImageRelease(frame);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!image) { [self vgAlert:@"تعذر قراءة إطار الفيديو."]; return; }
                VGVideoCropScreen *screen = [VGVideoCropScreen new];
                screen.image = image;
                screen.modalPresentationStyle = UIModalPresentationFullScreen;
                screen.didApply = ^(CGFloat zoom, CGPoint pan) {
                    [self vgExport:source forAsset:asset mode:@"note" zoom:zoom pan:pan];
                };
                UIViewController *host = self.controller ? self.controller() : nil;
                if (host) [host presentViewController:screen animated:YES completion:nil];
            });
        });
    }];
}
@end
