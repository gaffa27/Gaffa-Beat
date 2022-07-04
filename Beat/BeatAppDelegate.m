//
//  ApplicationDelegate.m
//  Beat
//
//  Copyright © 2019 Lauri-Matti Parppei. All rights reserved.
//  Copyright © 2016 Hendrik Noeller. All rights reserved.
//	Released under GPL license


#ifdef ADHOC
#import <Sparkle/Sparkle.h>
#endif

#import <os/log.h>
#import <StoreKit/StoreKit.h>

#import "BeatAppDelegate.h"
#import "RecentFiles.h"
#import "BeatFileImport.h"
#import "BeatPluginManager.h"
#import "BeatBrowserView.h"
#import "BeatAboutScreen.h"
#import "BeatEpisodePrinter.h"
#import "BeatPlugin.h"
#import "BeatPluginManager.h"
#import "BeatNotifications.h"
#import "BeatModalInput.h"
#import "Document.h"
#import "BeatPreferencesPanel.h"
#import "BeatPluginLibrary.h"

#ifndef QUICKLOOK
#import "Beat-Swift.h"
#endif

#import "BeatTest.h"

#define APPNAME @"Beat"

@interface BeatAppDelegate ()
@property (weak) IBOutlet NSMenuItem *checkForUpdatesItem;
@property (weak) IBOutlet NSMenuItem *menuManual;
@property (nonatomic) IBOutlet BeatPluginManager *pluginManager; // Set main ownership to avoid leaks

@property (nonatomic) BeatNotifications *notifications;

@property (nonatomic) BeatLaunchScreen *welcomeWindow;
@property (nonatomic) BeatBrowserView *browser;
@property (nonatomic) BeatPreferencesPanel *preferencesPanel;
@property (nonatomic) BeatAboutScreen *about;

// New plugin library
@property (nonatomic) BeatPluginLibrary *pluginLibrary;

@property (nonatomic) BeatEpisodePrinter *episodePrinter;

@property (nonatomic) NSPanel *console;
@property (nonatomic) NSTextView *consoleTextView;

@property (nonatomic) BeatTest *tests;

#ifdef ADHOC
// I'm supporting ad hoc distribution for now
@property (nonatomic) IBOutlet SPUUpdater *updater;
@property (nonatomic) IBOutlet SPUStandardUserDriver *userDriver;
#endif

@end

@implementation BeatAppDelegate

#define DEVELOPMENT NO
#define DARKMODE_KEY @"Dark Mode"
#define LATEST_VERSION_KEY @"Latest Version"

#pragma mark - Help

+(void)load {
	[super load];
}

- (instancetype) init {
	self = [super init];
	
	// Use these to reset any user defaults (for debugging purposes)
	//[NSUserDefaults.standardUserDefaults removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
	//[NSUserDefaults.standardUserDefaults removeObjectForKey:@"AppleLanguages"];
	
	return self;
}

- (void) awakeFromNib {
	// [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints"];
	
#ifdef ADHOC
	// Ad hoc vector
	NSLog(@"# ADHOC");

	// Init Sparkle
	self.userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:NSBundle.mainBundle delegate:nil];
	self.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle applicationBundle:[NSBundle mainBundle] userDriver:self.userDriver delegate:nil];
	
	NSError *error;
	[self.updater startUpdater:&error];
	if (error) NSLog(@"sparkle error: %@", error);
	
	// Add selector to check updates item
	_checkForUpdatesItem.action = @selector(checkForUpdates:);
#else
	// App store vector
	NSLog(@"# APPSTORE");
	
	// Remove "Check For Updates" menu item
	[_checkForUpdatesItem.menu removeItem:_checkForUpdatesItem];
	_checkForUpdatesItem = nil;
#endif
		
	// Show welcome screen
	[self showLaunchScreen];
	
	// Populate plugin menu
	[self.pluginManager setupPluginMenus];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
	// if (!(NSEvent.modifierFlags & NSEventModifierFlagShift)) [self checkAutosavedFiles];
	
	if (@available(macOS 10.14, *)) {
		UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
		[center requestAuthorizationWithOptions:UNAuthorizationOptionBadge | UNAuthorizationOptionAlert completionHandler:^(BOOL granted, NSError * _Nullable error) {
		}];
	}
	
#ifdef ADHOC
	// Run Sparkle if this is an ad hoc distribution
	//if (self.updater.) [self.updater checkForUpdatesInBackground];
	if (self.updater.automaticallyChecksForUpdates) [self.updater checkForUpdatesInBackground];
#endif
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[self setupDocumentOpenListener];
	[self checkDarkMode];

	// Show launch screen
	[self showLaunchScreen];
	
	// Lastly, open patch notes if the app was recently updated
	[self checkVersion];
	
	// Add to launch count
	NSInteger timesLaunched = [NSUserDefaults.standardUserDefaults integerForKey:@"LaunchCount"];
	timesLaunched++;
	[NSUserDefaults.standardUserDefaults setInteger:timesLaunched forKey:@"LaunchCount"];
}

-(void)checkForUpdates:(id)sender {
#ifdef ADHOC
	// Only allow this in ad hoc distribution
	[self.updater checkForUpdates];
#endif
}

-(void)checkDarkMode {
	_darkMode = [NSUserDefaults.standardUserDefaults boolForKey:DARKMODE_KEY];
	
	// If the OS is set to dark mode, we'll force it
	if (@available(macOS 10.14, *)) {
		NSAppearance *appearance = NSAppearance.currentAppearance ?: NSApp.effectiveAppearance;
		NSAppearanceName appearanceName = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
		if ([appearanceName isEqualToString:NSAppearanceNameDarkAqua]) {
			_darkMode = true;
		} else {
			if (_darkMode) _forceDarkMode = YES;
		}
	}
}

-(void)checkVersion {
	NSInteger latestVersion = [[[NSUserDefaults standardUserDefaults] objectForKey:LATEST_VERSION_KEY] integerValue];
	NSInteger currentVersion = [[NSBundle.mainBundle.infoDictionary objectForKey:@"CFBundleVersion"] integerValue];
	
	// Show patch notes if it's the first time running Beat
	if (latestVersion == 0 || currentVersion > latestVersion) {
		[[NSUserDefaults standardUserDefaults] setValue:[NSString stringWithFormat:@"%lu", currentVersion] forKey:LATEST_VERSION_KEY];
		if (!DEVELOPMENT) [self showPatchNotes:nil];
	}
}

-(void)setupDocumentOpenListener {
	// Let's close the welcome screen if any sort of document has been opened
	[[NSNotificationCenter defaultCenter] addObserverForName:@"Document open" object:nil queue:nil usingBlock:^(NSNotification *note) {
		[self closeLaunchScreen];
	}];
	
	// And show modal if all documents were closed
	[NSNotificationCenter.defaultCenter addObserverForName:@"Document close" object:nil queue:nil usingBlock:^(NSNotification *note) {
		NSArray* openDocuments = NSApplication.sharedApplication.orderedDocuments;
		
		if (openDocuments.count == 1 && !self.welcomeWindow) {
			[self showLaunchScreen];
		}
		
		[self requestAppReview];
	}];
}

- (void)requestAppReview {
	// The user has either clicked that they never want to review the app
	bool dontShowReviewPrompt = [NSUserDefaults.standardUserDefaults boolForKey:@"DontAskForReview"];
	if (dontShowReviewPrompt) return;
	
	// So, we'll see if the user has launched the app at least 50 times before requesting a review,
	// and _never_ again for the same version.
	NSInteger timesLaunched = [NSUserDefaults.standardUserDefaults integerForKey:@"LaunchCount"];
	NSString *lastVersionPrompted = [NSUserDefaults.standardUserDefaults valueForKey:@"LastVersionPromptedForReview"];
	NSString *currentVersion = [NSBundle.mainBundle.infoDictionary valueForKey:(NSString*)kCFBundleVersionKey];
	
	if (timesLaunched  % 51 == 50 && ![currentVersion isEqualToString:lastVersionPrompted]) {
		[NSUserDefaults.standardUserDefaults setValue:currentVersion forKey:@"LastVersionPromptedForReview"];
		
		if (@available(macOS 10.14, *)) [SKStoreReviewController requestReview];
	}
	
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
	return NO;
}

#pragma mark - Autosave Recovery

- (void)checkAutosavedFiles {
	// We will run this operation in another thread, so that the app can start and opening recovered documents won't mess up any other logic built into the app.
	
	dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
		__block NSFileManager *fileManager = NSFileManager.defaultManager;
		
		NSString *appName = [NSBundle.mainBundle.infoDictionary objectForKey:(id)kCFBundleNameKey];
		NSArray<NSString*>* searchPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
		NSString* appSupportDir = [searchPaths firstObject];
		appSupportDir = [appSupportDir stringByAppendingPathComponent:appName];
		appSupportDir = [appSupportDir stringByAppendingPathComponent:@"Autosave"];
		
		NSArray *files = [fileManager contentsOfDirectoryAtPath:appSupportDir error:nil];
		
		for (NSString *file in files) {
			if (![file.pathExtension isEqualToString:@"fountain"]) continue;
			
			__block NSString *filename = [NSString stringWithString:file];
			
			dispatch_async(dispatch_get_main_queue(), ^(void){
				
				NSAlert *alert = NSAlert.new;
				alert.messageText = [NSString stringWithFormat:@"%@", filename];
				alert.informativeText = @"An unsaved script was found. Do you want to open the latest autosaved version of this file?";
				[alert addButtonWithTitle:@"Open"];
				[alert addButtonWithTitle:@"Cancel"];

				NSModalResponse response = [alert runModal];

				if (response == NSAlertFirstButtonReturn) {
					NSString *contents = [NSString stringWithContentsOfFile:[appSupportDir stringByAppendingPathComponent:file] encoding:NSUTF8StringEncoding error:nil];
					[self newDocumentWithContents:contents];
					
					/*
					NSString *recoveredFilename = [[[filename stringByDeletingPathExtension] stringByAppendingString:@" (Recovered)"] stringByAppendingString:@".fountain"];
					
					NSSavePanel *saveDialog = [NSSavePanel savePanel];
					[saveDialog setAllowedFileTypes:@[@"Fountain"]];
					[saveDialog setNameFieldStringValue:recoveredFilename];
					
					[saveDialog beginWithCompletionHandler:^(NSInteger result) {
						if (result == NSFileHandlingPanelOKButton) {

							NSError *error;
							@try {
								[fileManager moveItemAtPath:[appSupportDir stringByAppendingPathComponent:file] toPath:saveDialog.URL.path error:&error];
								
								[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:saveDialog.URL display:YES completionHandler:^(NSDocument * _Nullable document, BOOL documentWasAlreadyOpen, NSError * _Nullable error) {
								}];
								if (error) {
									NSAlert *alert = [[NSAlert alloc] init];
									alert.messageText = [NSString stringWithFormat:@"Error recovering %@", filename];
									alert.informativeText = @"The file could not be recovered, but don't worry, it is still safe. Restart Beat and try to recover into another location.";
									alert.alertStyle = NSAlertStyleWarning;
									[alert runModal];
								}
							} @catch (NSException *exception) {
							} @finally {
							}
						} else {
							// If the user really doesn't want to spare this file, let's fucking delete it FOREVER!!!
							[self deleteAutosaveFile:[appSupportDir stringByAppendingPathComponent:filename]];
						}
					}];
					 */
				} else {
					[self deleteAutosaveFile:[appSupportDir stringByAppendingPathComponent:filename]];
				}
				
			});
		}
	});
}

- (void)deleteAutosaveFile:(NSString*)filename {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	@try {
		[fileManager removeItemAtPath:filename error:nil];
	} @catch (NSException *exception) {
		NSAlert *alert = [NSAlert.alloc init];
		alert.messageText = [NSString stringWithFormat:@"Error removing autosave file %@", filename];
		alert.informativeText = @"Beat doesn't have write permissions to access its Application Support folder. You need to remove the autosave file manually to avoid seeing this error in the future.\n\n\
		In Finder, press cmd-shift-G and type in ~/Library/Application Support/Beat/Autosave/ and delete any files in that folder. Sorry for any inconvenience.";
		alert.alertStyle = NSAlertStyleWarning;
		[alert runModal];
	} @finally {
	}
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	if (flag) return NO; else return YES;
}


#pragma mark - Dark mode stuff

// At all times, we have to check if OS is set to dark AND if the user has forced either mode
// This is horribly dated, but seems to work ---- for now.

- (bool)isForcedDarkMode {
	if (![self OSisDark]) return _forceDarkMode;
	return NO;
}
- (bool)isForcedLightMode {
	if ([self OSisDark]) return _forceLightMode;
	return NO;
}

- (bool)isDark {
	if ([self OSisDark]) {
		// OS in dark mode
		if (_forceLightMode) return NO;
		else return YES;
	} else {
		// OS in light mode
		if (_forceDarkMode) return YES;
		else return NO;
	}
}

- (bool)OSisDark {
	if (@available(macOS 10.14, *)) {
		NSAppearance *appearance = [NSApp effectiveAppearance];
		if (!appearance) appearance = [NSAppearance currentAppearance];
		
		NSAppearanceName appearanceName = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
		if ([appearanceName isEqualToString:NSAppearanceNameDarkAqua]) {
			return YES;
		}
	}
	return NO;
}

- (void)toggleDarkMode {
	_darkMode = ![self isDark];
	
	// OS is in dark mode, so we need to force the light mode
	if ([self OSisDark]) {
		if (!_darkMode) _forceLightMode = YES;
		else _forceLightMode = NO;
	}
	// And vice versa
	else if (![self OSisDark]) {
		if (_darkMode) _forceDarkMode = YES;
		else _forceDarkMode = NO;
	}
	
	[NSUserDefaults.standardUserDefaults setBool:_darkMode forKey:DARKMODE_KEY];
}

#pragma mark - Tutorial and templates

- (IBAction)showReference:(id)sender
{
	[self showTemplate:@"Tutorial"];
}

- (IBAction)templateBeatSheet:(id)sender {
	[self showTemplate:@"Beat Sheet"];
}

- (void)showTemplate:(NSString*)name {
	NSURL *url = [NSBundle.mainBundle URLForResource:name withExtension:@"fountain"];
	
	if (url) [[NSDocumentController sharedDocumentController] duplicateDocumentWithContentsOfURL:url copying:YES displayName:name error:nil];
	else NSLog(@"ERROR: Can't find template");
}

#pragma mark - Fountain syntax references & help

-(void)windowWillClose:(NSNotification *)notification {
	// Dealloc window controllers on close
	
	NSWindow* window = notification.object;
	
	if (window == _browser.window) {
		[_browser resetWebView]; // Avoid retain cycle
		_browser = nil;
	}
	else if (window == _episodePrinter.window) {
		[NSApp stopModal];
		_episodePrinter = nil;
	}
	else if (window == _preferencesPanel.window) {
		_preferencesPanel = nil;
	}
	else if (window == _pluginLibrary.window) {
		[_pluginLibrary clearWebView];
		_pluginLibrary = nil;
	}
}

- (IBAction)showPatchNotes:(id)sender {
	if (!_browser) {
		_browser = BeatBrowserView.new;
		_browser.window.delegate = self;
	}
	
	NSURL *url = [NSBundle.mainBundle URLForResource:@"Patch Notes" withExtension:@"html"];
	[_browser showBrowser:url withTitle:NSLocalizedString(@"app.patchNotes", nil) width:550 height:640];
}

- (IBAction)showManual:(id)sender {
	if (!_browser) {
		_browser = BeatBrowserView.new;
		_browser.window.delegate = self;
	}
	
	NSURL *url = [NSBundle.mainBundle URLForResource:@"beat_manual" withExtension:@"html"];
	[_browser showBrowser:url withTitle:NSLocalizedString(@"app.manual", nil) width:850 height:600];
}

- (IBAction)showFountainSyntax:(id)sender
{
    [self openURLInWebBrowser:@"http://www.fountain.io/syntax#section-overview"];
}
- (IBAction)showSupport:(id)sender
{
    [self openURLInWebBrowser:@"http://www.kapitan.fi/beat/support.html"];
}


- (IBAction)showFountainWebsite:(id)sender
{
    [self openURLInWebBrowser:@"http://www.fountain.io"];
}

- (IBAction)showBeatWebsite:(id)sender
{
    [self openURLInWebBrowser:@"https://kapitan.fi/beat/"];
}
- (IBAction)showBeatSource:(id)sender
{
    [self openURLInWebBrowser:@"https://github.com/lmparppei/beat/"];
}
- (IBAction)openDiscord:(id)sender
{
	[self openURLInWebBrowser:@"http://discord.gg/FPHjfH7ms3"];
}

- (void)openURLInWebBrowser:(NSString*)urlString
{
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:urlString]];
}

#pragma mark - Misc UI

-(void)showLaunchScreen {
	if (!self.welcomeWindow) self.welcomeWindow = BeatLaunchScreen.alloc.init;
	[self.welcomeWindow.window makeKeyAndOrderFront:nil];
}

- (void)closeLaunchScreen
{
	[self.welcomeWindow close];
	_welcomeWindow = nil;
}

- (IBAction)showAboutScreen:(id) sender {
	if (!_about) _about = BeatAboutScreen.new;
	[_about show];
}

- (IBAction)openPreferences:(id)sender {
	if (!_preferencesPanel) {
		_preferencesPanel = BeatPreferencesPanel.new;
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:_preferencesPanel.window];
	}
	[_preferencesPanel show];
}

#pragma mark - File Import

- (IBAction)importFDX:(id)sender
{
	BeatFileImport *import = BeatFileImport.new;
	[import fdx];
}
- (IBAction)importCeltx:(id)sender
{
	BeatFileImport *import = BeatFileImport.new;
	[import celtx];
}
- (IBAction)importHighland:(id)sender
{
	BeatFileImport *import = BeatFileImport.new;
	[import highland];
}
- (IBAction)importFadeIn:(id)sender
{
	BeatFileImport *import = BeatFileImport.new;
	[import fadeIn];
}

#pragma mark - Generic methods for opening a plain-text file

- (id)newDocumentWithContents:(NSString*)string {
	NSURL *tempURL = [self URLForTemporaryFileWithPrefix:@"fountain"];
	NSError *error;
	
	[string writeToURL:tempURL atomically:NO encoding:NSUTF8StringEncoding error:&error];
	id document = [NSDocumentController.sharedDocumentController duplicateDocumentWithContentsOfURL:tempURL copying:YES displayName:@"Untitled" error:nil];
	return document;
}

- (NSURL *)URLForTemporaryFileWithPrefix:(NSString *)prefix
{
    NSURL  *  result;
    CFUUIDRef   uuid;
    CFStringRef uuidStr;

    uuid = CFUUIDCreate(NULL);
    assert(uuid != NULL);

    uuidStr = CFUUIDCreateString(NULL, uuid);
    assert(uuidStr != NULL);
	result = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.%@", prefix, uuidStr, prefix]]];
    
    assert(result != nil);

    CFRelease(uuidStr);
    CFRelease(uuid);

    return result;
}

- (IBAction)newDocument:(id)sender {
	[NSDocumentController.sharedDocumentController newDocument:sender];
}

#pragma mark - Menu delegation

-(void)menuWillOpen:(NSMenu *)menu {
	//if (menu == _pluginMenu || menu == _exportMenu || menu == _importMenu) [self setupPlugins:menu];
	
	if (menu == _versionMenu) {
		[self versionMenuItems];
	}
}

#pragma mark - Version control

// NOTE: This is not in use currently, because of weird autosave errors
// To put it back, you need a REVERT menu, set its outlet to _versionMenu and
// set this class as the delegate.

- (void)versionMenuItems {
	[_versionMenu removeAllItems];
	
	NSDocument *doc = NSDocumentController.sharedDocumentController.currentDocument;
	NSURL *url = doc.fileURL;
	
	if (url) {
		NSArray *versions = [BeatBackup backupsWithName:url.lastPathComponent.stringByDeletingPathExtension];
		
		NSDateFormatter* df = NSDateFormatter.new;
		[df setDateStyle:NSDateFormatterShortStyle];
		[df setTimeStyle:NSDateFormatterShortStyle];
		
		BeatMenuItemWithURL *toSaved = [BeatMenuItemWithURL.alloc initWithTitle:NSLocalizedString(@"backup.revertToSaved", nil) action:@selector(revertTo:) keyEquivalent:@""];
		toSaved.url = doc.fileURL;
		
		[_versionMenu addItem:toSaved];
		[_versionMenu addItem:NSMenuItem.separatorItem];
		
		for (BeatBackupFile *version in versions) {
			NSString *modificationTime = [df stringFromDate:version.date];
			BeatMenuItemWithURL *item = [BeatMenuItemWithURL.alloc initWithTitle:modificationTime action:@selector(revertTo:) keyEquivalent:@""];
			item.url = [NSURL fileURLWithPath:version.path];
			[_versionMenu addItem:item];
		}
		
		if (versions.count) {
			[_versionMenu addItem:NSMenuItem.separatorItem];
		}
	}
	
	NSMenuItem *backupVault = [NSMenuItem.alloc initWithTitle:[BeatLocalization localizedStringForKey:@"backup.backupVault"] action:@selector(openBackupFolder:) keyEquivalent:@""];
	[_versionMenu addItem:backupVault];
}

- (IBAction)revertTo:(id)sender {
	
	BeatModalInput *input = BeatModalInput.alloc.init;
	[input confirmBoxWithMessage:[BeatLocalization localizedStringForKey:@"backup.reverting.title"]
							text:[BeatLocalization localizedStringForKey:@"backup.reverting.message"] forWindow:NSDocumentController.sharedDocumentController.currentDocument.windowForSheet completion:^(bool result) {
		if (!result) return;
		else {
			BeatMenuItemWithURL *item = sender;
			
			NSError *error;
			if (item.url == NSDocumentController.sharedDocumentController.currentDocument.fileURL) {
				// Revert to saved
				[NSDocumentController.sharedDocumentController.currentDocument revertDocumentToSaved:nil];
				return;
			}
			
			if (item.url == nil) NSLog(@"ERROR, no URL found");
			
			[NSDocumentController.sharedDocumentController.currentDocument revertToContentsOfURL:item.url ofType:NSPlainTextDocumentType error:&error];
			if (error) NSLog(@"Error: %@", error);
		}
	}];
}

- (IBAction)openBackupFolder:(id)sender {
	[BeatBackup openBackupFolder];
}

/*
- (void)versionMenuItems {
	[_versionMenu removeAllItems];
	
	NSDocument *doc = NSDocumentController.sharedDocumentController.currentDocument;
	NSURL *url = doc.fileURL;
	if (!url) return;
	
	// Get available versions
	NSArray *versions = [NSFileVersion otherVersionsOfItemAtURL:url];
	
	NSDateFormatter* df = NSDateFormatter.new;
	[df setDateStyle:NSDateFormatterShortStyle];
	[df setTimeStyle:NSDateFormatterShortStyle];
	
	// Add revert to saved
	NSMenuItem *toSaved = [[NSMenuItem alloc] initWithTitle:@"Saved" action:@selector(revertTo:) keyEquivalent:@""];
	toSaved.tag = NSNotFound;
	if (!doc.isDocumentEdited) toSaved.state = NSOnState;
	
	[_versionMenu addItem:toSaved];
	[_versionMenu addItem:NSMenuItem.separatorItem];
	
	// Only allow 10
	NSInteger count = 0;
	
	for (NSInteger i = versions.count - 1; i >= 0; i--) {
		// Don't allow more than 10 versions
		if (count > 10) break;
		
		NSFileVersion *version = versions[i];
		NSString *modificationTime = [df stringFromDate:version.modificationDate];
		
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:modificationTime action:@selector(revertTo:) keyEquivalent:@""];
		item.tag = i;
		
		if ([[(Document*)doc revertedTo] isEqualTo:version.URL]) item.state = NSOnState;
		
		[_versionMenu addItem:item];
		
		count++;
	}
	
	[_versionMenu addItem:NSMenuItem.separatorItem];
	[_versionMenu addItemWithTitle:@"Browse Versions..." action:@selector(browseVersions:) keyEquivalent:@""];
}

- (void)browseVersions:(id)sender {
	[NSDocumentController.sharedDocumentController.currentDocument browseDocumentVersions:self];
}

- (void)revertTo:(id)sender {
	BeatModalInput *input = BeatModalInput.alloc.init;
	[input confirmBoxWithMessage:@"Revert File" text:@"Any unsaved changes will be lost when reverting to an earlier version." forWindow:NSDocumentController.sharedDocumentController.currentDocument.windowForSheet completion:^(bool result) {
		if (!result) return;
		else {
			NSMenuItem *item = sender;
			
			NSError *error;
			
			if (item.tag == NSNotFound) {
				// Revert to saved
				[NSDocumentController.sharedDocumentController.currentDocument revertDocumentToSaved:nil];
				return;
			}
			
			NSArray *versions = [NSFileVersion otherVersionsOfItemAtURL:NSDocumentController.sharedDocumentController.currentDocument.fileURL];
			NSFileVersion *version = versions[item.tag];
			
			[NSDocumentController.sharedDocumentController.currentDocument revertToContentsOfURL:version.URL ofType:NSPlainTextDocumentType error:&error];
			if (error) NSLog(@"Error: %@", error);
		}
	} buttons:@[@"Revert", @"Cancel"]];
}
*/
 
#pragma mark - Plugin support

- (IBAction)openPluginLibrary:(id)sender {
	_pluginLibrary = BeatPluginLibrary.alloc.init;
	_pluginLibrary.window.delegate = self;
	[_pluginLibrary show];
}

- (IBAction)runStandalonePlugin:(id)sender {
	// This runs a plugin which is NOT tied to the document
	NSMenuItem *item = sender;
	NSString *pluginName = item.title;
	
	BeatPlugin *parser = BeatPlugin.new;
	BeatPluginData *plugin = [BeatPluginManager.sharedManager pluginWithName:pluginName];
	[parser loadPlugin:plugin];
	parser = nil;
}

#pragma mark - Plugin developer console

-(void)openConsole {
	// This is written very quickly on a train and is VERY hacky and shady. Works for now, though.
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		if (!self.console) {
			NSArray *objects = [NSArray array];
			[NSBundle.mainBundle loadNibNamed:@"BeatConsole" owner:self.console topLevelObjects:&objects];
			self.console = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 450, 100) styleMask:NSWindowStyleMaskClosable | NSWindowStyleMaskHUDWindow | NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow backing:NSBackingStoreBuffered defer:NO];
			
			NSPanel *panel;
			for (id item in objects) { if ([item isKindOfClass:NSPanel.class]) panel = item; }
			self.console.contentView = panel.contentView;
			self.consoleTextView = [(NSScrollView*)self.console.contentView.subviews[0] documentView];
		}

		[self.console makeKeyAndOrderFront:nil];
	});
	
	//[NSDocumentController.sharedDocumentController.currentDocument.windowControllers[0] showWindow:_console];
}
-(void)logToConsole:(NSString*)string pluginName:(NSString*)pluginName {
	if (!_console) return;
	
	NSString *consoleValue = [NSString stringWithFormat:@"%@: %@\n", pluginName, string];
	os_log(OS_LOG_DEFAULT, "[plugin] %@: %@", pluginName, string);
	
	// Ensure main thread
	if (!NSThread.isMainThread) {
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			[self logMessage:consoleValue];
		});
	} else {
		[self logMessage:consoleValue];
	}
}
- (void)logMessage:(NSString*)consoleValue {
	[self.consoleTextView.textStorage replaceCharactersInRange:NSMakeRange(self.consoleTextView.string.length, 0) withString:consoleValue];
	[self.consoleTextView.textStorage addAttribute:NSForegroundColorAttributeName value:NSColor.textColor range:(NSRange){ self.consoleTextView.string.length - consoleValue.length, consoleValue.length }];

	[self.consoleTextView.layoutManager ensureLayoutForTextContainer:self.consoleTextView.textContainer];
	self.consoleTextView.frame = [self.consoleTextView.layoutManager usedRectForTextContainer:self.consoleTextView.textContainer];
	
	// Get clip view
	NSClipView *clipView = self.consoleTextView.enclosingScrollView.contentView;

	// Calculate the y position by subtracting clip view height from total document height
	CGFloat scrollTo = self.consoleTextView.frame.size.height - clipView.frame.size.height;

	// Animate bounds
	[clipView setBoundsOrigin:NSMakePoint(0, scrollTo)];
}

-(void)clearConsole {
	if (!_console) return;
	
	[_consoleTextView.textStorage replaceCharactersInRange:(NSRange){0, _consoleTextView.string.length} withString:@""];
	[_consoleTextView setTextColor:NSColor.whiteColor];
}


#pragma mark - Episode Printing
// Sorry, I don't know how to work with window controllers, so this is here :-(

- (IBAction)printEpisodes:(id)sender {
	if (!_episodePrinter) {
		_episodePrinter = BeatEpisodePrinter.new;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:_episodePrinter.window];
	}
	//[_episodePrinter showWindow:_episodePrinter.window];
	[NSApp runModalForWindow:_episodePrinter.window];
}


#pragma mark - Clear user defaults

- (void)removeUserDefaults
{
	NSUserDefaults * userDefaults = [NSUserDefaults standardUserDefaults];
	NSDictionary * dict = [userDefaults dictionaryRepresentation];
	for (id key in dict)
	{
		[userDefaults removeObjectForKey:key];
	}
	[userDefaults synchronize];
}

#pragma mark - Show notifications

- (void)showNotification:(NSString*)title body:(NSString*)body identifier:(NSString*)identifier oneTime:(BOOL)showOnce interval:(CGFloat)interval {
	if (!_notifications) _notifications = BeatNotifications.new;
	[_notifications showNotification:title body:body identifier:identifier oneTime:showOnce interval:interval];
}

#pragma mark - Supporting methods

- (NSURL*)appDataPath:(NSString*)subPath {
	return [BeatAppDelegate appDataPath:subPath];
}
+ (NSURL*)appDataPath:(NSString*)subPath {
	NSString* pathComponent = APPNAME;
	
	if ([subPath length] > 0) pathComponent = [pathComponent stringByAppendingPathComponent:subPath];
	
	NSArray<NSString*>* searchPaths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
																		  NSUserDomainMask,
																		  YES);
	NSString* appSupportDir = [searchPaths firstObject];
	appSupportDir = [appSupportDir stringByAppendingPathComponent:pathComponent];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if (![fileManager fileExistsAtPath:appSupportDir]) {
		[fileManager createDirectoryAtPath:appSupportDir withIntermediateDirectories:YES attributes:nil error:nil];
	}
	
	return [NSURL fileURLWithPath:appSupportDir isDirectory:YES];
}

- (NSString *)pathForTemporaryFileWithPrefix:(NSString *)prefix
{
	return [BeatAppDelegate pathForTemporaryFileWithPrefix:prefix];
}
+ (NSString *)pathForTemporaryFileWithPrefix:(NSString *)prefix
{
	NSString *  result;
	CFUUIDRef   uuid;
	CFStringRef uuidStr;

	uuid = CFUUIDCreate(NULL);
	assert(uuid != NULL);

	uuidStr = CFUUIDCreateString(NULL, uuid);
	assert(uuidStr != NULL);

	result = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", prefix, uuidStr]];
	assert(result != nil);

	CFRelease(uuidStr);
	CFRelease(uuid);

	return result;
}

@end
