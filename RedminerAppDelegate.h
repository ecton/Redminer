//
//  RedminerAppDelegate.h
//  Redminer
//
//  Created by Jonathan Johnson on 3/22/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface RedminerAppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *window;
	WebView *webView;
	
	NSWindow *preferencesWindow;
	NSTextField *redmineUrlField;
	NSTextField *usernameField;
	NSTextField *passwordField;
	NSPopUpButton *updateFrequencyBtn;
	NSButton *notifyWithGrowlBtn;
	NSProgressIndicator *prefsIndicator;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet WebView *webView;

@property (assign) IBOutlet NSWindow *preferencesWindow;
@property (assign) IBOutlet NSTextField *redmineUrlField;
@property (assign) IBOutlet NSTextField *usernameField;
@property (assign) IBOutlet NSTextField *passwordField;
@property (assign) IBOutlet NSPopUpButton *updateFrequencyBtn;
@property (assign) IBOutlet NSButton *notifyWithGrowlBtn;

- (IBAction)showPreferences:(id)sender;
- (IBAction)updateFrequencyChanged:(id)sender;
- (IBAction)notifyWithGrowlChanged:(id)sender;

@end
