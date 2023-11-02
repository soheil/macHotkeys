file=$(basename "$0")
LO=$(grep -n -- "--==--" $file | tail -1 | cut -d ':' -f1)
LO=$(($LO + 2))
sed -n -e "$LO,$ p" $file > /tmp/$file
clang /tmp/$file -framework Cocoa -o /usr/local/bin/"${file%.*}"
exit

--==--

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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}

- (void)statusItemClicked:(id)sender {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    if (argc > 1) {
        const char* filename = argv[0];
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@"/bin/sh"];
        NSString *command = [NSString stringWithFormat:@"kill $(ps aux | grep '%s' | grep -v grep | awk '{print $2}')", filename];
        [task setArguments:@[@"-c", command]];
        [task launch];
        return 0;
    }

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
