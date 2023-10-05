#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSRunningApplication *chatProcess;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSButton *statusBarButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 4, 18, 18)];
    
    NSProgressIndicator *progressIndicator = [[NSProgressIndicator alloc] initWithFrame:statusBarButton.frame];
    progressIndicator.style = NSProgressIndicatorSpinningStyle;
    progressIndicator.controlTint = NSClearControlTint;
    progressIndicator.indeterminate = YES;
    [progressIndicator startAnimation:nil];

    statusBarButton.bordered = NO;
    statusBarButton.imagePosition = NSImageOnly;
    [statusBarButton addSubview:progressIndicator];
    [statusBarButton setAction:@selector(statusItemClicked:)];
    [statusBarButton setTarget:self];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.view = statusBarButton;

   // Schedule a check for the "chat/run" process every 2 seconds using GCD
    [self checkProcessName];
}

- (void)statusItemClicked:(id)sender {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:@[@"-c", @"kill $(ps aux | grep 'chat/run' | grep -v grep | awk '{print $2}')"]];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task launch];
    
    [task waitUntilExit];
    [NSApp terminate:nil];
}

- (void)checkProcessName {
    // Check if the "chat/run" process is running
    BOOL isRunning = NO;
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:@[@"-c", @"ps aux | grep -E 'chat/run|/up' | grep -v 'grep'"]];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task launch];
    
    // Wait for the task to complete and read the output
    [task waitUntilExit];
    NSData *outputData = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *outputStr = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    
    // Check if the output contains the process ID of the running process
    if ([outputStr length] != 0) {
        // If there is no process named "chat/run" running, terminate the application
        isRunning = YES;
    }

    // If the process is not running, terminate the app
    if (!isRunning) {
        [NSApp terminate:nil];
    } else {
        // Schedule another check in 2 seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self checkProcessName];
        });
    }
}

@end

int main(int argc, const char * argv[]) {
    // Create the application object
    NSApplication *application = [NSApplication sharedApplication];
    
    // Create the app delegate
    AppDelegate *appDelegate = [[AppDelegate alloc] init];
    
    // Set the app delegate
    [application setDelegate:appDelegate];
    
    // Run the application
    [application run];
    
    return 0;
}
