//
//  AppDelegate.m
//
//  Created by andrian7 on 06.11.16.
//  Copyright © 2016 andrian7. All rights reserved.
//

#import "AppDelegate.h"

@interface BackgroundColorView: NSView
@property NSColor *color;
@end

@implementation BackgroundColorView
- (void)drawRect:(NSRect)dirtyRect {
    [self.color setFill];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
}
@end


@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate{
    NSStatusItem *_statusItem;
    NSButton *_statusItemButton;
    AuthorizationRef _authorizationRef;
    BackgroundColorView *_bgView;
    NSInteger _selectedInterfaceIndex;
    NSArray *_interfaces;
    NSArray *_interfaceMenuItems;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [self setupStatusItem];
    
    [self authorize];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (void)setupStatusItem {
    _statusItem =[[NSStatusBar systemStatusBar] statusItemWithLength:130];
    
    CGFloat menuBarHeight = [[[NSApplication sharedApplication] mainMenu] menuBarHeight];
    
    _bgView = [BackgroundColorView new];
    _bgView.frame = CGRectMake(0, 0, 130, menuBarHeight);
    [_statusItem.button addSubview:_bgView];
    
    NSButton *button = [NSButton new];
    button.target = self;
    button.tag = 0;
    button.action = @selector(statusItemClicked:);
    button.frame = CGRectMake(2, 2, 100, menuBarHeight - 4);
    _statusItemButton = button;
    
    [_statusItem.button addSubview:button];
    
    NSMenu *menu = [[NSMenu alloc] init];
    
    _interfaces = [self getListOfInterfaces];
    if(_interfaces.count == 0) {
        [self exit];
    }
    
    NSInteger i = 0;
    NSMutableArray* menuItems = [NSMutableArray new];
    for (NSDictionary *interface in _interfaces) {
        NSString *name = interface[@"name"];
        NSMenuItem *menuItem = [menu addItemWithTitle:name action:@selector(selectMenuItemInterface:) keyEquivalent:@""];
        menuItem.state = 0;
        menuItem.tag = i++;
        [menuItems addObject:menuItem];
    }
    _interfaceMenuItems = [menuItems copy];
    
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"by andrian7" action:nil keyEquivalent:@""];
    [menu addItemWithTitle:@"Quit" action:@selector(exit) keyEquivalent:@""];
    
    _statusItem.menu = menu;
    
    [self selectInterfaceAtIndex:0];
}

- (void)selectMenuItemInterface:(NSMenuItem *)sender {
    [self selectInterfaceAtIndex:sender.tag];
}

- (void)selectInterfaceAtIndex:(NSInteger)index {
    for(NSMenuItem *menuItem in _interfaceMenuItems) {
        menuItem.state = menuItem.tag == index ? 1 : 0;
    }
    _selectedInterfaceIndex = index;
    
    NSInteger interfaceIndex = _selectedInterfaceIndex;
    NSDictionary *interface = _interfaces[interfaceIndex];
    NSString *interfaceName = interface[@"name"];
    BOOL enabled = [self isInterfaceEnabled:interfaceName];
    
    [self invalidateStatusItem:enabled];
}

- (void)invalidateStatusItem:(BOOL)enabled {
    NSInteger interfaceIndex = _selectedInterfaceIndex;
    NSDictionary *interface = _interfaces[interfaceIndex];
    NSString *interfaceName = interface[@"name"];
    
    NSMutableArray *mutInterfaces = [_interfaces mutableCopy];
    NSMutableDictionary *mutInterface = [interface mutableCopy];
    mutInterface[@"enabled"] = @(enabled);
    mutInterfaces[interfaceIndex] = mutInterface;
    _interfaces = [mutInterfaces copy];
    
    if (enabled) {
        _statusItemButton.title = [NSString stringWithFormat:@"Disable %@", interfaceName];
        _bgView.color = [NSColor colorWithRed:0 green:0.9 blue:0 alpha:0.5];
    } else {
        _statusItemButton.title = [NSString stringWithFormat:@"Enable %@", interfaceName];
        _bgView.color = [NSColor colorWithRed:0.9 green:0 blue:0 alpha:0.5];
    }
}

- (void)exit {
    
    [NSApp terminate:self];
}

- (void)statusItemClicked:(NSButton *)sender {
    NSInteger interfaceIndex = _selectedInterfaceIndex;
    NSDictionary *interface = _interfaces[interfaceIndex];
    BOOL interfaceState = [interface[@"enabled"] boolValue];
    [self toggleInternet:!interfaceState];
    [_bgView setNeedsDisplay:YES];
}

- (void)toggleInternet:(BOOL)active {
    NSInteger interfaceIndex = _selectedInterfaceIndex;
    NSDictionary *interface = _interfaces[interfaceIndex];
    NSString *interfaceName = interface[@"name"];
    
    char *tool = "/usr/sbin/networksetup";
    const char *cname = [interfaceName UTF8String];
    
    char *cnameMutable = calloc([interfaceName length]+1, 1);
    strncpy(cnameMutable, cname, [interfaceName length]);
    
    char *args[] = { "-setnetworkserviceenabled", cnameMutable, active ? "on" : "off", NULL };
    FILE *pipe = NULL;
    
    OSStatus status = AuthorizationExecuteWithPrivileges(_authorizationRef, tool,
                                                         kAuthorizationFlagDefaults, args, &pipe);
    
    free(cnameMutable);
    if (status != errAuthorizationSuccess)
        NSLog(@"Error: %d", status);
    
    [self invalidateStatusItem:active];
}

- (BOOL)isInterfaceEnabled:(NSString *)interfaceName {
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *file = pipe.fileHandleForReading;
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/sbin/networksetup";
    task.arguments = @[@"-getnetworkserviceenabled", interfaceName];
    task.standardOutput = pipe;
    
    [task launch];
    
    NSData *data = [file readDataToEndOfFile];
    [file closeFile];
    
    NSString *output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    
    __block BOOL enabled = NO;
    [lines enumerateObjectsUsingBlock:^(NSString * obj, NSUInteger index, BOOL *stop) {
        if ([obj isEqualToString:@"Enabled"]) {
            enabled = YES;
        }
    }];
    
    return enabled;
}

- (NSArray *)getListOfInterfaces {
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *file = pipe.fileHandleForReading;
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/sbin/networksetup";
    task.arguments = @[@"-listallnetworkservices"];
    task.standardOutput = pipe;
    
    [task launch];
    
    NSData *data = [file readDataToEndOfFile];
    [file closeFile];
    
    NSString *output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    
    NSMutableArray *interfaces = [NSMutableArray new];
    [lines enumerateObjectsUsingBlock:^(NSString * obj, NSUInteger index, BOOL *stop) {
        if (index == 0) return;
        if (index == [lines count] - 1) return;
        
        NSString *nobj = obj;
        BOOL enabled = YES;
        
        if (obj.length > 0 && [obj characterAtIndex:0] == '*') {
            nobj = [obj stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
            enabled = NO;
        }
        
        [interfaces addObject:@{ @"name": nobj, @"enabled": @(enabled) }];
    }];
    
    return [interfaces copy];
}

- (void)authorize {
    
    OSStatus status;
    
    
    // AuthorizationCreate and pass NULL as the initial
    // AuthorizationRights set so that the AuthorizationRef gets created
    // successfully, and then later call AuthorizationCopyRights to
    // determine or extend the allowable rights.
    // http://developer.apple.com/qa/qa2001/qa1172.html
    status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                 kAuthorizationFlagDefaults, &_authorizationRef);
    if (status != errAuthorizationSuccess) {
        NSLog(@"Error Creating Initial Authorization: %d", status);
        
    }
    
    // kAuthorizationRightExecute == "system.privilege.admin"
    AuthorizationItem right = {kAuthorizationRightExecute, 0, NULL, 0};
    AuthorizationRights rights = {1, &right};
    AuthorizationFlags flags = kAuthorizationFlagDefaults |
    kAuthorizationFlagInteractionAllowed |
    kAuthorizationFlagPreAuthorize |
    kAuthorizationFlagExtendRights;
    
    // Call AuthorizationCopyRights to determine or extend the allowable rights.
    status = AuthorizationCopyRights(_authorizationRef, &rights, NULL, flags, NULL);
    if (status != errAuthorizationSuccess) {
        NSLog(@"Copy Rights Unsuccessful: %d", status);
        [NSApp terminate:self];
    }
    
    // The only way to guarantee that a credential acquired when you
    // request a right is not shared with other authorization instances is
    // to destroy the credential.  To do so, call the AuthorizationFree
    // function with the flag kAuthorizationFlagDestroyRights.
    // http://developer.apple.com/documentation/Security/Conceptual/authorization_concepts/02authconcepts/chapter_2_section_7.html
    //status = AuthorizationFree(authorizationRef, kAuthorizationFlagDestroyRights);
}



@end
