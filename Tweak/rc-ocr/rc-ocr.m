// rc-ocr IMAGE [fast]: every line of text Vision finds in IMAGE, one per line:
//   X<TAB>Y<TAB>WIDTH<TAB>HEIGHT<TAB>CONFIDENCE<TAB>TEXT
// in the image's pixels, from its top left. Exit 0 when read (even with no text), 1 on an error
// (printed to stderr), 2 for wrong arguments. RemoteCompanion runs it from SpringBoard where the
// careful read fails there (iOS 15): this separate process is allowed what it needs.
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#import <CoreVideo/CoreVideo.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "Usage: rc-ocr IMAGE [fast]\n"); return 2; }
        BOOL fast = argc > 2 && !strcmp(argv[2], "fast");
        NSData *data = [NSData dataWithContentsOfFile:@(argv[1])];
        CGImageSourceRef src = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
        CGImageRef img = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
        if (src) CFRelease(src);
        if (!img) { fprintf(stderr, "Can't read the image %s\n", argv[1]); return 1; }
        size_t W = CGImageGetWidth(img) & ~(size_t)1, H = CGImageGetHeight(img); // Vision wants an even width
        // Drawn into a BGRA pixel buffer, which Vision takes as it is
        CVPixelBufferRef pb = NULL;
        if (CVPixelBufferCreate(NULL, W, H, kCVPixelFormatType_32BGRA, NULL, &pb) != kCVReturnSuccess || !pb) {
            CGImageRelease(img);
            fprintf(stderr, "Can't make a pixel buffer\n");
            return 1;
        }
        CVPixelBufferLockBaseAddress(pb, 0);
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef cx = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), W, H, 8, CVPixelBufferGetBytesPerRow(pb), rgb,
                                                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(rgb);
        CGContextDrawImage(cx, CGRectMake(0, 0, CGImageGetWidth(img), H), img);
        CGContextRelease(cx);
        CVPixelBufferUnlockBaseAddress(pb, 0);
        CGImageRelease(img);

        VNRecognizeTextRequest *req = [VNRecognizeTextRequest new];
        req.recognitionLevel = fast ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
        req.usesLanguageCorrection = NO;
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pb options:@{}];
        NSError *err = nil;
        [handler performRequests:@[req] error:&err];
        CVPixelBufferRelease(pb);
        if (err) { fprintf(stderr, "%s\n", err.localizedDescription.UTF8String); return 1; }
        for (VNRecognizedTextObservation *obs in req.results) {
            VNRecognizedText *best = [obs topCandidates:1].firstObject;
            if (!best) continue;
            CGRect b = obs.boundingBox; // normalized, from the bottom left
            NSString *text = [[best.string componentsSeparatedByCharactersInSet:[NSCharacterSet controlCharacterSet]] componentsJoinedByString:@" "];
            printf("%.1f\t%.1f\t%.1f\t%.1f\t%.2f\t%s\n", b.origin.x * W, (1 - b.origin.y - b.size.height) * H,
                   b.size.width * W, b.size.height * H, best.confidence, text.UTF8String);
        }
        return 0;
    }
}
