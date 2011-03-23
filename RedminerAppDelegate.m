//
//  RedminerAppDelegate.m
//  Redminer
//
//  Created by Jonathan Johnson on 3/22/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "RedminerAppDelegate.h"
#import "CCJSON.h"
#import "NSData+Base64.h"
#import <Security/Security.h>

#define REDMINE_URL_KEY @"redmineUrl"
#define REDMINE_USERNAME_KEY @"redmineUsername"

#define KEYCHAIN_SERVICE_NAME "Redminer Redmine Password"

@implementation RedminerAppDelegate

@synthesize window, webView;

@synthesize preferencesWindow, redmineUrlField, usernameField, passwordField, 
	updateFrequencyBtn, notifyWithGrowlBtn;
	
- (id)loadRedminePath:(NSString *)path withUsername:(NSString *)username andPassword:(NSString *)password {
	NSString *baseUrl = [[NSUserDefaults standardUserDefaults] stringForKey:REDMINE_URL_KEY];
	if ([baseUrl length] && [baseUrl characterAtIndex:[baseUrl length] - 1] != '/') {
		baseUrl = [baseUrl stringByAppendingString:@"/"];
	}
	baseUrl = [baseUrl stringByAppendingString:path];
	NSURL *url = [NSURL URLWithString:baseUrl];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	NSString *authStr = [NSString stringWithFormat:@"%@:%@", username, password];
	NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
	NSString *digest = [authData base64EncodedString];
	[request setValue:[NSString stringWithFormat:@"Basic %@", digest] forHTTPHeaderField:@"Authorization"];
	
	NSError *error = nil;
	NSURLResponse *response = nil;
	NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	if (responseData) {
		if ([path rangeOfString:@".json"].location != NSNotFound) {
			NSString *jsonStr = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease];
			return [CCJSONParser objectFromJSON:jsonStr useNSNull:NO];
		} else {
			NSXMLDocument *xmlDoc = [[[NSXMLDocument alloc] initWithData:responseData options:NSXMLNodeOptionsNone error:NULL] autorelease];
			return xmlDoc; 
		}
	}
	return nil;
}
	
- (id)loadRedminePath:(NSString *)path {
	
	NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:REDMINE_USERNAME_KEY];
	
	void *password = NULL;
	u_int32_t passwordLen = 0;
	OSStatus status = SecKeychainFindGenericPassword(NULL, 
		strlen(KEYCHAIN_SERVICE_NAME), KEYCHAIN_SERVICE_NAME, 
		[username lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [username UTF8String], 
		&passwordLen, &password, 
		NULL);
	
	if (status == noErr) {
		NSString *passwordStr = [[[NSString alloc] initWithBytes:password length:passwordLen encoding:NSUTF8StringEncoding] autorelease];
		SecKeychainItemFreeContent(NULL, password);
		return [self loadRedminePath:path withUsername:username andPassword:passwordStr];
	}
	return nil;
}

- (void)reloadDataInBg {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableString *html = [[NSMutableString alloc] init];
	
	NSDictionary *assignedToMe = [self loadRedminePath:@"issues.json?assigned_to=me&limit=100"];
	
	[html appendFormat:@"<pre>%@</pre>", assignedToMe];

	[self performSelectorOnMainThread:@selector(loadHtml:) withObject:html waitUntilDone:YES];
	[html release];
	
	[pool release];
}

- (void)reloadData {
	[NSThread detachNewThreadSelector:@selector(reloadDataInBg) toTarget:self withObject:nil];
}

- (void)loadHtml:(NSString *)html {
	WebFrame *frame = [webView mainFrame];
	[frame loadHTMLString:html baseURL:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[redmineUrlField setObjectValue:[[NSUserDefaults standardUserDefaults] stringForKey:REDMINE_URL_KEY]];
	[usernameField setObjectValue:[[NSUserDefaults standardUserDefaults] stringForKey:REDMINE_USERNAME_KEY]];
	[self reloadData];
}

- (IBAction)showPreferences:(id)sender {
	[preferencesWindow makeKeyAndOrderFront:sender];
}

- (void)testAndSaveCredentials {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[prefsIndicator performSelectorOnMainThread:@selector(startAnimation:) withObject:self waitUntilDone:NO];
		
	NSString *username = [usernameField stringValue];
	NSString *password = [passwordField stringValue];
	NSDictionary *result = [self loadRedminePath:@"issues.json?limit=1" withUsername:username andPassword:password];
	
	if (result == nil) {
		[usernameField performSelectorOnMainThread:@selector(setTextColor:) withObject:[NSColor colorWithDeviceRed:1.0 green:0 blue:0 alpha:1.0] waitUntilDone:NO];
	} else {
		[usernameField performSelectorOnMainThread:@selector(setTextColor:) withObject:[NSColor colorWithDeviceRed:0.0 green:1.0 blue:0 alpha:1.0] waitUntilDone:NO];
		
		OSStatus err = SecKeychainAddGenericPassword(NULL, 
			strlen(KEYCHAIN_SERVICE_NAME), KEYCHAIN_SERVICE_NAME, 
			[username lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [username UTF8String], 
			[password lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [password UTF8String], 
			NULL);
		
		NSLog(@"SecKeychainAddGenericPassword returne %i", err);
		
	}
	
	[prefsIndicator performSelectorOnMainThread:@selector(stopAnimation:) withObject:self waitUntilDone:NO];
	[pool release];
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor {
	if (control == redmineUrlField) {
		[[NSUserDefaults standardUserDefaults] setObject:[redmineUrlField stringValue] forKey:REDMINE_URL_KEY];
		[[NSUserDefaults standardUserDefaults] synchronize];
	} else if (control == usernameField) {
		[[NSUserDefaults standardUserDefaults] setObject:[usernameField stringValue] forKey:REDMINE_USERNAME_KEY];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
	
	[NSThread detachNewThreadSelector:@selector(testAndSaveCredentials) toTarget:self withObject:nil];
	
	return YES;
}

- (IBAction)updateFrequencyChanged:(id)sender {

}

- (IBAction)notifyWithGrowlChanged:(id)sender {

}

@end
