#import "A3ToggleManager.h"
#import "A3ToggleManagerMain.h"
#import "A3ToggleService.h"
#import "A3Toggle.h"

#import <dlfcn.h>
#import <UIKit/UIKit2.h>
#import "LightMessaging/LightMessaging.h"

static LMConnection connection = {
	MACH_PORT_NULL,
	kA3ToggleServiceName
};

NSString * const A3ToggleManagerTogglesChangedNotification = @"A3ToggleManagerTogglesChangedNotification";

NSString * const A3ToggleManagerToggleStateChangedNotification = @"A3ToggleManagerToggleStateChangedNotification";
NSString * const A3ToggleManagerToggleIdentifierKey = @"toggleIdentifier";


static A3ToggleManager *_toggleManager;

@implementation A3ToggleManager

static void TogglesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	[[NSNotificationCenter defaultCenter] postNotificationName:A3ToggleManagerTogglesChangedNotification object:_toggleManager userInfo:nil];
}

+ (void)initialize
{
	if (self == [A3ToggleManager class]) {
		if (objc_getClass("SpringBoard")) {
			_toggleManager = [[A3ToggleManagerMain alloc] init];
		} else {
			_toggleManager = [[self alloc] init];
			CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), self, TogglesChangedCallback, (CFStringRef)A3ToggleManagerTogglesChangedNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
		}
	}
}

+ (A3ToggleManager *)sharedToggleManager
{
    return _toggleManager;
}

- (NSArray *)toggleIdentifiers
{
	LMResponseBuffer responseBuffer;
	if (LMConnectionSendTwoWay(&connection, A3ToggleServiceMessageGetIdentifiers, NULL, 0, &responseBuffer)) {
		return nil;
	}
	return LMResponseConsumePropertyList(&responseBuffer);
}

- (NSString *)titleForToggleIdentifier:(NSString *)toggleIdentifier
{
	LMResponseBuffer responseBuffer;
	if (LMConnectionSendTwoWayPropertyList(&connection, A3ToggleServiceMessageGetTitleForIdentifier, toggleIdentifier, &responseBuffer)) {
		return nil;
	}
	return LMResponseConsumePropertyList(&responseBuffer);
}

- (id)glyphImageIdentifierForToggleIdentifier:(NSString *)toggleIdentifier controlState:(UIControlState)controlState size:(CGFloat)size scale:(CGFloat)scale
{
 	NSDictionary *args = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:toggleIdentifier, [NSNumber numberWithFloat:size], [NSNumber numberWithFloat:scale], [NSNumber numberWithInteger:controlState], nil] forKeys:[NSArray arrayWithObjects:@"toggleIdentifier", @"size", @"scale", @"controlState", nil]];

	LMResponseBuffer responseBuffer;
	if (LMConnectionSendTwoWayPropertyList(&connection, A3ToggleServiceMessageGetImageIdentifierForToggle, args, &responseBuffer)) {
		return nil;
	}
	return LMResponseConsumePropertyList(&responseBuffer);
}

static UIColor *ColorWithHexString(NSString *stringToConvert)
{
	NSString *noHashString = [stringToConvert stringByReplacingOccurrencesOfString:@"#" withString:@""]; // remove the #
	NSScanner *scanner = [NSScanner scannerWithString:noHashString];
	[scanner setCharactersToBeSkipped:[NSCharacterSet symbolCharacterSet]]; // remove + and $

	unsigned hex;
	if (![scanner scanHexInt:&hex]) return nil;
	int r = (hex >> 16) & 0xFF;
	int g = (hex >> 8) & 0xFF;
	int b = (hex) & 0xFF;

	return [UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1.0f];
}

- (void)drawGlyphImageIdentifier:(id)identifier toSize:(CGFloat)glyphSize atPosition:(CGPoint)position color:(CGColorRef)color blur:(CGFloat)blur inContext:(CGContextRef)context ofSize:(CGSize)contextSize
{
	CGContextTranslateCTM(context, position.x, position.y);
	if ([identifier isKindOfClass:[NSString class]]) {
		UIImage *image;
		if ([identifier hasSuffix:@".pdf"]) {
			CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((CFURLRef)[NSURL fileURLWithPath:identifier]);
			if (pdf) {
				CGContextTranslateCTM(context, 0.0f, contextSize.height);
				CGContextScaleCTM(context, 1.0f, -1.0f);
				CGContextTranslateCTM(context, 0, -glyphSize);
				CGPDFPageRef firstPage = CGPDFDocumentGetPage(pdf, 1);
				CGRect rect = CGPDFPageGetBoxRect(firstPage, kCGPDFCropBox);
				CGFloat scale = rect.size.height / glyphSize;
				CGContextScaleCTM(context, glyphSize / rect.size.width, glyphSize / rect.size.height);
				CGContextTranslateCTM(context, -rect.origin.x, -rect.origin.y);
				// Shadows are always in the current CTM. whiskey. tango. foxtrot.
				CGContextSetShadowWithColor(context, CGSizeMake(0.0f, contextSize.height * scale), blur * scale, color);
				CGContextDrawPDFPage(context, firstPage);
				CGPDFDocumentRelease(pdf);
			}
		} else if ((image = [UIImage imageWithContentsOfFile:identifier])) {
			identifier = image;
		}
	}
	if ([identifier isKindOfClass:[UIImage class]]) {
		CGContextSetShadowWithColor(context, CGSizeMake(0.0f, contextSize.height), blur, color);
		CGContextTranslateCTM(context, 0.0f, -contextSize.height);
		[identifier drawInRect:CGRectMake(0.0f, 0.0f, glyphSize, glyphSize)];
	}
}

- (UIImage *)toggleImageForToggleIdentifier:(NSString *)toggleIdentifier controlState:(UIControlState)controlState scale:(CGFloat)scale usingTemplateBundle:(NSBundle *)template
{
	CGSize size;
	size.width = [[template objectForInfoDictionaryKey:@"width"] floatValue];
	if (size.width == 0.0f)
		return nil;
	size.height = [[template objectForInfoDictionaryKey:@"height"] floatValue];
	if (size.height == 0.0f)
		return nil;
	if (&UIGraphicsBeginImageContextWithOptions != NULL) {
		UIGraphicsBeginImageContextWithOptions(size, NO, scale);
	} else {
		UIGraphicsBeginImageContext(size);
		scale = 1.0f;
	}
	size_t maskWidth = size.width * scale;
	size_t maskHeight = size.height * scale * 2;
	void *maskData = NULL;
	void *secondMaskData = NULL;
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(context, [UIColor redColor].CGColor);
	CGContextFillRect(context, CGRectMake(0.0f, 0.0f, size.width, size.height));
	for (NSDictionary *layer in [template objectForInfoDictionaryKey:@"layers"]) {
		CGContextSaveGState(context);
		id temp = [layer objectForKey:@"opacity"];
		if (temp) {
			CGContextSetAlpha(context, [temp floatValue]);
		}
		CGPoint position = CGPointMake([[layer objectForKey:@"x"] floatValue], [[layer objectForKey:@"y"] floatValue]);
		NSString *type = [layer objectForKey:@"type"];
		if (!type || [type isEqualToString:@"image"]) {
			NSString *fileName = [layer objectForKey:@"fileName"];
			if (fileName) {
				UIImage *image = [UIImage imageNamed:fileName inBundle:template];
				[image drawAtPoint:position];
			}
		} else if ([type isEqualToString:@"glyph"]) {
			CGFloat blur = [[layer objectForKey:@"blur"] floatValue];
			CGFloat glyphSize = [[layer objectForKey:@"size"] floatValue];
			id identifier = [self glyphImageIdentifierForToggleIdentifier:toggleIdentifier controlState:controlState size:glyphSize scale:scale];
			NSString *fileName = [layer objectForKey:@"fileName"];
			BOOL hasCutout = [[layer objectForKey:@"cutout"] boolValue];
			if (hasCutout) {
				CGFloat cutoutX = [[layer objectForKey:@"cutoutX"] floatValue];
				CGFloat cutoutY = [[layer objectForKey:@"cutoutY"] floatValue];
				CGFloat cutoutBlur = [[layer objectForKey:@"cutoutBlur"] floatValue];
				if (!maskData)
					maskData = malloc(maskWidth * maskHeight);
				memset(maskData, '\0', maskWidth * maskHeight);
				CGContextRef maskContext = CGBitmapContextCreate(maskData, maskWidth, maskHeight, 8, maskWidth, NULL, kCGImageAlphaOnly);
				CGContextScaleCTM(maskContext, scale, scale);
				CGContextSetBlendMode(maskContext, kCGBlendModeCopy);
				[self drawGlyphImageIdentifier:identifier toSize:glyphSize atPosition:CGPointMake(position.x + cutoutX, position.y + cutoutY) color:[UIColor whiteColor].CGColor blur:cutoutBlur inContext:maskContext ofSize:size];
				CGContextRelease(maskContext);
				CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)[NSData dataWithBytesNoCopy:maskData length:maskWidth * maskHeight freeWhenDone:NO]);
				CGImageRef maskImage = CGImageMaskCreate(maskWidth, maskHeight, 8, 8, maskWidth, dataProvider, NULL, TRUE);
				CGDataProviderRelease(dataProvider);
				CGContextClipToMask(context, CGRectMake(0.0f, 0.0f, size.width, size.height + size.height), maskImage);
				CGImageRelease(maskImage);
			}
			UIImage *image;
			if (fileName && (image = [UIImage imageNamed:fileName inBundle:template])) {
				// Slow path to draw an image
				void *localMaskData;
				if (hasCutout) {
					if (!secondMaskData)
						secondMaskData = malloc(maskWidth * maskHeight);
					localMaskData = secondMaskData;
				} else {
					// Reuse a single buffer if possible
					if (!maskData)
						maskData = malloc(maskWidth * maskHeight);
					localMaskData = maskData;
				}
				memset(localMaskData, '\0', maskWidth * maskHeight);
				CGContextRef maskContext = CGBitmapContextCreate(localMaskData, maskWidth, maskHeight, 8, maskWidth, NULL, kCGImageAlphaOnly);
				CGContextSetBlendMode(maskContext, kCGBlendModeCopy);
				CGContextScaleCTM(maskContext, scale, scale);
				[self drawGlyphImageIdentifier:identifier toSize:glyphSize atPosition:position color:[UIColor whiteColor].CGColor blur:blur inContext:maskContext ofSize:size];
				CGImageRef maskImage = CGBitmapContextCreateImage(maskContext);
				CGContextRelease(maskContext);
				CGContextClipToMask(context, CGRectMake(0.0f, 0.0f, size.width, size.height + size.height), maskImage);
				CGImageRelease(maskImage);
				[image drawInRect:CGRectMake(position.x - blur, position.y - blur, glyphSize + blur + blur, glyphSize + blur + blur)];
			} else {
				// Fast path for a solid color
				CGColorRef color = (ColorWithHexString([layer objectForKey:@"color"]) ?: [UIColor blackColor]).CGColor;
				[self drawGlyphImageIdentifier:identifier toSize:glyphSize atPosition:position color:color blur:blur inContext:context ofSize:size];
			}
		}
		CGContextRestoreGState(context);
	}
	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (maskData)
		free(maskData);
	if (secondMaskData)
		free(secondMaskData);
	return result;
}

- (UIImage *)toggleImageForToggleIdentifier:(NSString *)toggleIdentifier controlState:(UIControlState)controlState usingTemplateBundle:(NSBundle *)templateBundle;
{
	CGFloat scale = [UIScreen instancesRespondToSelector:@selector(scale)] ? [UIScreen mainScreen].scale : 1.0f;
	return [self toggleImageForToggleIdentifier:toggleIdentifier controlState:controlState scale:scale usingTemplateBundle:templateBundle];
}

- (A3ToggleState)toggleStateForToggleIdentifier:(NSString *)toggleIdentifier
{
	LMResponseBuffer responseBuffer;
	if (LMConnectionSendTwoWayPropertyList(&connection, A3ToggleServiceMessageGetStateForIdentifier, toggleIdentifier, &responseBuffer)) {
		return NO;
	}
	return LMResponseConsumeInteger(&responseBuffer);
}

- (void)applyActionForToggleIdentifier:(NSString *)toggleIdentifier
{
	LMConnectionSendOneWayData(&connection, A3ToggleServiceMessageApplyActionForIdentifier, (CFDataRef)[NSPropertyListSerialization dataFromPropertyList:toggleIdentifier format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL]);
}

- (void)setToggleState:(A3ToggleState)state onToggleIdentifier:(NSString *)toggleIdentifier
{
	NSArray *propertyList = [NSArray arrayWithObjects:[NSNumber numberWithBool:state], toggleIdentifier, nil];
	LMConnectionSendOneWayData(&connection, A3ToggleServiceMessageSetStateForIdentifier, (CFDataRef)[NSPropertyListSerialization dataFromPropertyList:propertyList format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL]);
}


- (BOOL)hasAlternateActionForToggleIdentifier:(NSString *)toggleIdentifier
{
	LMResponseBuffer responseBuffer;
	if (LMConnectionSendTwoWayPropertyList(&connection, A3ToggleServiceMessageHasAlternateActionForIdentifier, toggleIdentifier, &responseBuffer)) {
		return NO;
	}
	return LMResponseConsumeInteger(&responseBuffer);
}

- (void)applyAlternateActionForToggleIdentifier:(NSString *)toggleIdentifier
{
	LMConnectionSendOneWayData(&connection, A3ToggleServiceMessageApplyAlternateActionForIdentifier, (CFDataRef)[NSPropertyListSerialization dataFromPropertyList:toggleIdentifier format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL]);
}

@end

@implementation A3ToggleManager (SpringBoard)

- (void)registerToggle:(id<A3Toggle>)toggle forIdentifier:(NSString *)toggleIdentifier
{
	[NSException raise:NSInternalInconsistencyException format:@"Cannot register toggles outside of SpringBoard!"];
}

- (void)unregisterToggleIdentifier:(NSString *)toggleIdentifier;
{
	[NSException raise:NSInternalInconsistencyException format:@"Cannot unregister toggles outside of SpringBoard!"];
}

- (void)stateDidChangeForToggleIdentifier:(NSString *)toggleIdentifier
{
	[NSException raise:NSInternalInconsistencyException format:@"Cannot update toggle state from outside of SpringBoard!"];
}

@end

