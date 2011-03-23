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
#import <Growl/Growl.h>
#import <Security/Security.h>

#define REDMINE_URL_KEY @"redmineUrl"
#define REDMINE_USERNAME_KEY @"redmineUsername"
#define UPDATE_FREQUENCY_KEY @"updateFrequency"

#define KEYCHAIN_SERVICE_NAME "Redminer Redmine Password"

@implementation RedminerAppDelegate

@synthesize window, webView;

@synthesize preferencesWindow, redmineUrlField, usernameField, passwordField, 
	updateFrequencyBtn, notifyWithGrowlBtn;

- (NSString *)baseUrl {
	NSString *baseUrl = [[NSUserDefaults standardUserDefaults] stringForKey:REDMINE_URL_KEY];
	if ([baseUrl length] && [baseUrl characterAtIndex:[baseUrl length] - 1] != '/') {
		baseUrl = [baseUrl stringByAppendingString:@"/"];
	}
	return baseUrl;
}
	
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

- (NSDictionary *)projectsById {
	NSXMLDocument *doc = [self loadRedminePath:@"projects.xml"];
	if (!doc) return nil;
	
	NSXMLElement *root = [doc rootElement];
	NSMutableDictionary *projects = [NSMutableDictionary dictionary];
	for (NSXMLElement *project in [root children]) {
		if (![[project name] isEqualToString:@"project"]) continue;
		NSMutableDictionary *proj = [NSMutableDictionary dictionary];
		NSString *projId = nil;
		for (NSXMLElement *elem in [project children]) {
			if ([[elem name] isEqualToString:@"id"]) {
				projId = [elem stringValue];
			} else if ([[elem name] isEqualToString:@"parent"]) {
				[proj setObject:[[elem attributeForName:@"id"] stringValue] forKey:@"parentId"];
			} else {
				[proj setObject:[elem stringValue] forKey:[elem name]];
			}
		}
		[projects setObject:proj forKey:projId];
	}
	return projects;
}

- (void)appendHtmlTo:(NSMutableString *)html forIssue:(NSDictionary *)issue isOverdue:(BOOL)overdue {
	static NSDateFormatter *df;
	if (!df) {
		df = [[NSDateFormatter alloc] init];
		[df setDateStyle:NSDateFormatterMediumStyle];
		[df setTimeStyle:NSDateFormatterNoStyle];
	}
	[html appendFormat:@"<div class=\"issue priority-%@%@\">", [[issue objectForKey:@"priority"] objectForKey:@"id"], (overdue ? @" overdue" : @"")];
	[html appendFormat:@"<div class=\"project\">%@</div>", [[issue objectForKey:@"project"] objectForKey:@"name"]];
	[html appendFormat:@"<div class=\"summary\"><a href=\"%@issues/%@\">%@</a></div>", [self baseUrl], [issue objectForKey:@"id"], [issue objectForKey:@"subject"]];
	if ([issue objectForKey:@"due_date"]) {
		[html appendFormat:@"<div class=\"due\">%@</div>", [df stringFromDate:[issue objectForKey:@"due_date"]]];
	}
	[html appendString:@"</div>"];
}

- (void)reloadDataInBg {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableString *html = [[NSMutableString alloc] init];
	
	[html appendString:@"<html><head><link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/></head><body>"];
	
	NSDictionary *projects = [self projectsById];
	NSDictionary *assignedToMe = [self loadRedminePath:@"issues.json?assigned_to_id=me&limit=100"];
	
	NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
	[df setDateFormat:@"yyyy/MM/dd"];
	[df setDefaultDate:[NSDate dateWithTimeIntervalSince1970:0]];
	[df setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	
	NSMutableArray *overdue = [NSMutableArray array];
	NSMutableArray *theRest = [NSMutableArray array];
	
	for (NSDictionary *issue in [assignedToMe objectForKey:@"issues"]) {
		NSMutableDictionary *newIssue = [NSMutableDictionary dictionaryWithDictionary:issue];
		if ([newIssue objectForKey:@"due_date"]) {
			NSDate *dt = [df dateFromString:[issue objectForKey:@"due_date"]];
			[newIssue setObject:dt forKey:@"due_date"];
		}
	
		
		if ([newIssue objectForKey:@"due_date"] && [[NSDate date] compare:[newIssue objectForKey:@"due_date"]] == NSOrderedDescending) {
			// Find the spot to put it in the overdue array -- make the most overdue float to the top
			BOOL foundSpot = NO;
			for (int i = 0; i < [overdue count]; i++) {
				NSDictionary *otherIssue = [overdue objectAtIndex:i];
				if ([[otherIssue objectForKey:@"due_date"] compare:[newIssue objectForKey:@"due_date"]] == NSOrderedDescending) {
					[overdue insertObject:newIssue atIndex:i];
					foundSpot = YES;
					break;
				}
			}
			if (!foundSpot) {
				[overdue addObject:newIssue];
			}
		} else {
			// Find the spot into the other array. First, sort by due date, then sort by priority id
			BOOL foundSpot = NO;
			for (int i = 0; i < [theRest count]; i++) {
				NSDictionary *otherIssue = [theRest objectAtIndex:i];
				if ([newIssue objectForKey:@"due_date"]) {
					if (![otherIssue objectForKey:@"due_date"] || [[otherIssue objectForKey:@"due_date"] compare:[newIssue objectForKey:@"due_date"]] == NSOrderedDescending) {
						[theRest insertObject:newIssue atIndex:i];
						foundSpot = YES;
						break;
					}
				} else if ([[[newIssue objectForKey:@"priority"] objectForKey:@"id"] compare:[[otherIssue objectForKey:@"priority"] objectForKey:@"id"]] == NSOrderedDescending) {
					[theRest insertObject:newIssue atIndex:i];
					foundSpot = YES;
					break;
				}
			}
			if (!foundSpot) {
				[theRest addObject:newIssue];
			}
		}
	}
	
	for (NSDictionary *issue in overdue) {
		[self appendHtmlTo:html forIssue:issue isOverdue:YES];
	}
	
	for (NSDictionary *issue in theRest) {
		[self appendHtmlTo:html forIssue:issue isOverdue:NO];
	}
	
	
	[html appendString:@"</body></html>"];
	
	
	
	[self performSelectorOnMainThread:@selector(loadHtml:) withObject:html waitUntilDone:YES];
	[html release];
	
	[pool release];
}

- (void)reloadData {
	[NSThread detachNewThreadSelector:@selector(reloadDataInBg) toTarget:self withObject:nil];
	
	int waitPeriod = [[NSUserDefaults standardUserDefaults] integerForKey:UPDATE_FREQUENCY_KEY];
	if (waitPeriod <= 0) waitPeriod = 1;
	[NSTimer scheduledTimerWithTimeInterval:waitPeriod * 60 target:self selector:@selector(reloadData) userInfo:nil repeats:NO];
}

- (void)loadHtml:(NSString *)html {
	//NSLog(@"%@", html);
	WebFrame *frame = [webView mainFrame];
	[frame loadHTMLString:html baseURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"style" ofType:@"css"]]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[redmineUrlField setObjectValue:[[NSUserDefaults standardUserDefaults] stringForKey:REDMINE_URL_KEY]];
	[usernameField setObjectValue:[[NSUserDefaults standardUserDefaults] stringForKey:REDMINE_USERNAME_KEY]];
	[webView setPolicyDelegate:self];
	[self reloadData];
}

- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)actionInformation
                                                           request:(NSURLRequest *)request
                                                             frame:(WebFrame *)frame
                                                  decisionListener:(id<WebPolicyDecisionListener>)listener {
	if ([[actionInformation objectForKey:WebActionNavigationTypeKey] intValue] == WebNavigationTypeLinkClicked) {
		[[NSWorkspace sharedWorkspace] openURL:[request URL]];
		[listener ignore];
	} else {
		[listener use];
	}
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
	int minutes = [updateFrequencyBtn selectedTag];
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:minutes] forKey:UPDATE_FREQUENCY_KEY];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)notifyWithGrowlChanged:(id)sender {

}

@end
