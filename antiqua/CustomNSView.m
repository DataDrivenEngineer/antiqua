//

#import <AppKit/NSScreen.h>
#import <AppKit/NSGraphicsContext.h>
#import <CoreVideo/CVDisplayLink.h>
#import <AppKit/NSApplication.h>
#import <QuartzCore/CALayer.h>
#import <mach/mach_time.h>
#import <math.h>

#import "osx_audio.h"
#import "types.h"
#import "CustomNSView.h"
#import "CustomCALayer.h"
#import "antiqua.h"

struct GameOffscreenBuffer framebuffer;

static struct mach_timebase_info mti;
static CustomCALayer *layer;
static CVDisplayLinkRef displayLink;
static u8 shouldStopDL = 0;

static void initTimebaseInfo(void)
{
  kern_return_t result;
  if ((result = mach_timebase_info(&mti)) != KERN_SUCCESS) printf("Failed to initialize timebase info. Error code: %d", result);
}

static void logFrameTime(const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime)
{
  static u64 previousNowNs = 0;
  u64 currentNowNs = inNow->hostTime * mti.numer / mti.denom;
  u64 inNowDiff = currentNowNs - previousNowNs;
  previousNowNs = currentNowNs;
  // Divide by 1000000 to convert from ns to ms
  NSLog(@"inNow frame time: %f ms", (r32)inNowDiff / 1000000);

  u64 processingWindowNs = (inOutputTime->hostTime - inNow->hostTime) * mti.numer / mti.denom;
  NSLog(@"processingWindow: %f ms", (r32)processingWindowNs / 1000000);
}

static CVReturn renderCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext)
{
  logFrameTime(inNow, inOutputTime);
  CVReturn error = [(__bridge CustomNSView *) displayLinkContext displayFrame:inOutputTime];
  return error;
}

@implementation CustomNSView

-(void) resumeDisplayLink
{
  shouldStopDL = 0;
  if (!CVDisplayLinkIsRunning(displayLink)) CVDisplayLinkStart(displayLink);

}

-(void) doStop
{
  if (CVDisplayLinkIsRunning(displayLink)) {
    CVDisplayLinkStop(displayLink);
  }
}

-(void) stopDisplayLink
{
  shouldStopDL = 1;
}

- (CVReturn)displayFrame:(const CVTimeStamp *)inOutputTime {
  if (shouldStopDL)
  {
    [self doStop];
  }
  else
  {
    updateGameAndRender(&framebuffer);

    dispatch_sync(dispatch_get_main_queue(), ^{
      [self setNeedsDisplay:YES];
    });
  }
  return kCVReturnSuccess;
}


- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  
  layer = [[CustomCALayer alloc] init];
  NSLog(@"layerw x h: %f x %f", layer.bounds.size.width, layer.bounds.size.height);
  self.wantsLayer = YES;
  self.layer = layer;
  self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;

  CGDirectDisplayID displayID = CGMainDisplayID();
  CVReturn error = kCVReturnSuccess;
  error = CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink);
  if (error)
  {
    NSLog(@"DisplayLink created with error:%d", error);
    displayLink = NULL;
  }
  CVDisplayLinkSetOutputCallback(displayLink, renderCallback, (__bridge void *)self);
  CVDisplayLinkStart(displayLink);
  
  initTimebaseInfo();

  // init game specific state
  framebuffer.width = 1024;
  framebuffer.height = 640;
  framebuffer.sizeBytes = sizeof(u8) * framebuffer.width * 4 * framebuffer.height;
  framebuffer.memory = malloc(framebuffer.sizeBytes);
  
  return self;
}

- (BOOL) wantsUpdateLayer
{
  return YES;
}

- (void)updateLayer {
  NSLog(@"updateLayer - never called!");
}

@end
