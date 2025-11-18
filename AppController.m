/**
 *  AppController.m
 *  SSHFS Manager
 *
 *  Created by Tomek Wójcik on 7/15/10.
 *  Copyright 2010 Tomek Wójcik. All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification, are
 *  permitted provided that the following conditions are met:
 *  
 *  1. Redistributions of source code must retain the above copyright notice, this list of
 *  conditions and the following disclaimer.
 *  
 *  2. Redistributions in binary form must reproduce the above copyright notice, this list
 *  of conditions and the following disclaimer in the documentation and/or other materials
 *  provided with the distribution.
 *  
 *  THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ``AS IS'' AND ANY EXPRESS OR IMPLIED
 *  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 *  FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> OR
 *  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 *  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 *   SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 *  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 *  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *  The views and conclusions contained in the software and documentation are those of the
 *  authors and should not be interpreted as representing official policies, either expressed
 *  or implied, of Tomek Wójcik.
 */

#import "AppController.h"
#import "BTHMenuItem.h"
#import <objc/runtime.h>

@implementation AppController
-(id)init {
	if ((self = [super init])) {
		statusItem = nil;
		statusItemImage = nil;
		currentTab = nil;
		hasSshfs = NO;
		isWorking = NO;
		sshfsFinderPID = 0;
		shareMounterPID = 0;
		lastMountedLocalPath = nil;
		autoUpdateTimer = nil;
		currentTask = nil;
	} // eof if()
	
	return self;
} // eof init

- (BOOL)isMacFUSEInstalled {
    NSArray *paths = @[
        @"/usr/local/lib/libfuse.dylib",
        @"/usr/local/lib/libfuse.2.dylib",
        @"/Library/Filesystems/macfuse.fs"
    ];

    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *path in paths) {
        if (![fm fileExistsAtPath:path]) {
            // mindestens eine fehlt → macFUSE nicht vollständig installiert
            return NO;
        }
    }
    // alle existieren
    return YES;
}

- (void)openFUSEDownloadLink:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://github.com/macfuse/macfuse/releases"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

-(void)dealloc {
	[self removeObserver:self forKeyPath:@"currentTab"];
	[sharesController removeObserver:self forKeyPath:@"selectionIndex"];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSTaskDidTerminateNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:nil];
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"sshfsPath"];
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"autoUpdate"];
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"autoUpdateInterval"];
	
	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
	
	[statusItem release]; statusItem = nil;
	[statusItemImage release]; statusItemImage = nil;
	[currentTab release]; currentTab = nil;
	[lastMountedLocalPath release]; lastMountedLocalPath = nil;
	
	if (autoUpdateTimer != nil) {
		[autoUpdateTimer invalidate]; [autoUpdateTimer release]; autoUpdateTimer = nil;
	} // eof if()
	
	[currentTask release]; currentTask = nil;
	
	[super dealloc];
} // eof dealloc

-(void)awakeFromNib {
	NSBundle *mainBundle = [NSBundle mainBundle];
	
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString *defaultsPath = [mainBundle pathForResource:@"userDefaults" ofType:@"plist"];
    
    if (defaultsPath != nil) {
        NSDictionary *defaultsDictionary = [[NSDictionary alloc] initWithContentsOfFile:defaultsPath];
        [preferences registerDefaults:defaultsDictionary];
        [defaultsDictionary release];
    } // eof if()
	[preferences synchronize];	
	
	[self addObserver:self forKeyPath:@"currentTab" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:@selector(tabChangedFrom:to:)];
	[sharesController addObserver:self forKeyPath:@"selectionIndex" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:@selector(sharesSelectionChangedFrom:to:)];
	[preferences addObserver:self forKeyPath:@"sshfsPath" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:@selector(sshfsPathChangedFrom:to:)];
	[preferences addObserver:self forKeyPath:@"autoUpdate" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:@selector(autoUpdateChangedFrom:to:)];
	[preferences addObserver:self forKeyPath:@"autoUpdateInterval" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:@selector(autoUpdateIntervalChangedFrom:to:)];
	
	NSSortDescriptor *sharesSortDescriptor = [[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES] autorelease];
	[sharesController setSortDescriptors:[NSArray arrayWithObject:sharesSortDescriptor]];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(checkATaskStatus:)
												 name:NSTaskDidTerminateNotification
											   object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];
	
    NSString *sshfsPath = [[NSBundle mainBundle] pathForResource:@"sshfs" ofType:@"" inDirectory:@"bin"];
    
    
    

    
    //NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSString *bundleSshfs = [[NSBundle mainBundle] pathForResource:@"sshfs" ofType:@"" inDirectory:@"bin"];

    if ([[NSFileManager defaultManager] isExecutableFileAtPath:bundleSshfs]) {
        [preferences setValue:bundleSshfs forKey:@"sshfsPath"];
        [preferences synchronize];
        [self setHasSshfs:YES];
    } else {
        NSLog(@"SSHFS binary not found or not executable at path: %@", bundleSshfs);
        [self setHasSshfs:NO];
    }
	
    NSImage *statusItemImage = [NSImage imageNamed:@"drive_web"];
	
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:[self statusItemMenu]];
    statusItem.button.image = statusItemImage;
    statusItem.button.appearsDisabled = NO;
    // Optional: Menu-Highlight, z. B. durch Wechsel der Bilder, oder wie folgt:
    //statusItem.button.highlighted = YES; // Gibt's nur lesend, nicht schreibend!
    // Alternativ: Button-Highlighting wie folgt setzen (empfohlen):
    //statusItem.button.cell.highlighted = NSContentsCellMask | NSPushInCellMask;
    [statusItem setLength:25.0];
    [statusItem retain];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hideDockIcon = [defaults boolForKey:@"HideDockIcon"];
    NSApplicationActivationPolicy policy = hideDockIcon ?
        NSApplicationActivationPolicyAccessory :
        NSApplicationActivationPolicyRegular;
    [[NSApplication sharedApplication] setActivationPolicy:policy];
    
    self.appVersion = [NSString stringWithFormat:@"v %@",[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]];
    NSUserDefaults *sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"sshfs-manager.slsoft.de"];
    NSDate *lastCheck = [[NSUserDefaults standardUserDefaults] objectForKey:@"SULastCheckTime"];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    [formatter setTimeStyle:NSDateFormatterShortStyle];

    NSString *lastCheckString = lastCheck ? [formatter stringFromDate:lastCheck] : @"Nie";

    self.lastUpdateCheck = lastCheckString;
    
	if ([preferences boolForKey:@"autoUpdate"] == YES) {
		[self setUpAutoUpdateTimer];
	} // eof if()
} // eof awakeFromNib

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)selector {
	[self performSelector:(SEL)selector withObject:[change objectForKey:@"old"] withObject:[change objectForKey:@"new"]];
} // eof observeValueForKeyPath:ofObject:change:context:

@synthesize currentTab;
@synthesize hasSshfs;
@synthesize isWorking;
@synthesize lastMountedLocalPath;

-(void)tabChangedFrom:(NSString *)oldTab to:(NSString *)newTab {
    if ([newTab isEqualToString:@"Shares"]) {
        // Setze die Breite des Drawers auf 300 Punkte
        NSSize drawerSize = NSMakeSize(400, [shareDrawer contentSize].height);
        [shareDrawer setContentSize:drawerSize];
        [shareDrawer open];
        [self sharesSelectionChangedFrom:nil to:nil];
    } else {
        [shareDrawer close];
    } // eof if()
} // tabChangedFrom:to:

-(void)sharesSelectionChangedFrom:(id)oldIndex to:(id)newIndex {
	if ([preferencesWindow isVisible]) {
		if ([sharesController selectionIndex] != NSNotFound) {
			[shareDrawer open];
		} else {
			[shareDrawer close];
		} // eof if()
	} // eof if()
} // eof sharesSelectionChanged:

-(void)sshfsPathChangedFrom:(NSString *)oldPath to:(NSString *)newPath {
	if ((newPath != nil) && ([newPath isEqualToString:@""] == NO)) {
		[self setHasSshfs:YES];
	} else {
		[self setHasSshfs:NO];
	} // eof if()
	
	//[self refreshStatusItemMenu];
} // eof sshfsPathChangedFrom:to:

- (void)localPathBrowseSheetDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode contextInfo:(void *)contextInfo {
    if (returnCode == NSModalResponseOK) {
        NSArray<NSURL *> *urls = [panel URLs];
        if ([urls count] > 0) {
            NSString *filename = [[urls objectAtIndex:0] path];
            NSManagedObject *currentShare = [[sharesController selectedObjects] objectAtIndex:0];
            [currentShare setValue:filename forKey:@"localPath"];
        }
    }
}

-(NSMenu *)statusItemMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    [menu setAutoenablesItems:NO];

    BOOL fuseInstalled = [self isMacFUSEInstalled];

    if (!fuseInstalled) {
        NSMenuItem *fuseMissingItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"macFUSE is missing!", nil)
                                                                  action:nil
                                                           keyEquivalent:@""];
        NSDictionary *attrs = @{NSForegroundColorAttributeName: [NSColor redColor]};
        NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"macFUSE is missing!", nil)
                                                                        attributes:attrs];
        [fuseMissingItem setAttributedTitle:attrTitle];
        [fuseMissingItem setEnabled:NO];
        [menu addItem:fuseMissingItem];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *downloadFUSE = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Download macFUSE", nil)
                                                              action:@selector(openFUSEDownloadLink:)
                                                       keyEquivalent:@""];
        [downloadFUSE setTarget:self];
        [menu addItem:downloadFUSE];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *prefs = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Preferences", nil)
                                                       action:@selector(showPreferences:)
                                                keyEquivalent:@","];
        [prefs setTarget:self];
        [menu addItem:prefs];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Quit", nil)
                                                      action:@selector(doQuit:)
                                               keyEquivalent:@"q"];
        [quit setTarget:self];
        [menu addItem:quit];

        return menu;
    }

    // --- FUSE installiert: Share Items ---
    NSManagedObjectContext *sharesContext = [appDelegate managedObjectContext];
    NSManagedObjectModel *shareModel = [appDelegate managedObjectModel];
    NSEntityDescription *shareEntity = [[shareModel entities] objectAtIndex:0];

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:shareEntity];
    [fetchRequest setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES]]];

    NSError *error = nil;
    NSArray *shares = [sharesContext executeFetchRequest:fetchRequest error:&error];
    if (error) {
        [[NSApplication sharedApplication] presentError:error];
        [[NSApplication sharedApplication] terminate:nil];
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSURL *> *mountedVolumeURLs = [fileManager mountedVolumeURLsIncludingResourceValuesForKeys:nil options:0];
    NSMutableArray<NSString *> *mountedFileSystems = [NSMutableArray array];
    for (NSURL *volumeURL in mountedVolumeURLs) {
        NSString *path = [volumeURL path];
        if (path) [mountedFileSystems addObject:path];
    }

    if (shares.count == 0) {
        NSMenuItem *noVolumes = [[NSMenuItem alloc] initWithTitle:@"No volumes" action:nil keyEquivalent:@""];
        [noVolumes setEnabled:NO];
        [menu addItem:noVolumes];
    } else {
        for (NSManagedObject *share in shares) {
            BTHMenuItem *item = [[BTHMenuItem alloc] initWithTitle:[share valueForKey:@"name"]
                                                            action:nil
                                                     keyEquivalent:@""];
            [item setTarget:self];

            NSString *localPath = [share valueForKey:@"localPath"];
            BOOL isMounted = [mountedFileSystems containsObject:localPath] ||
                             [localPath isEqualToString:[self lastMountedLocalPath]];

            // Action je nach Status
            [item setAction:(isMounted ? @selector(doUnmountShare:) : @selector(doMountShare:))];

            // Item-Daten
            NSMutableDictionary *itemData = [NSMutableDictionary dictionary];
            [itemData setObject:[share valueForKey:@"host"] forKey:@"host"];
            [itemData setObject:[share valueForKey:@"login"] forKey:@"login"];
            [itemData setObject:[share valueForKey:@"options"] forKey:@"options"];
            [itemData setObject:[share valueForKey:@"port"] forKey:@"port"];
            NSString *remotePath = [share valueForKey:@"remotePath"];
            if (remotePath) [itemData setObject:remotePath forKey:@"remotePath"];
            [itemData setObject:[share valueForKey:@"volumeName"] forKey:@"volumeName"];
            if (localPath) [itemData setObject:localPath forKey:@"localPath"];
            [item setItemData:itemData];

            // Icons
            NSImage *greenDot = [NSImage imageNamed:NSImageNameStatusAvailable];
            NSImage *redDot   = [NSImage imageNamed:NSImageNameStatusUnavailable];
            NSImage *ejectIcon = [NSImage imageNamed:@"eject"];

            if (isMounted) {
                // Kombiniertes Icon: grün + eject rechts
                NSImage *composite = [[NSImage alloc] initWithSize:NSMakeSize(28, 16)]; // Gesamtbreite 18+10
                [composite lockFocus];
                
                // Grüner Punkt links 16x16
                [greenDot drawInRect:NSMakeRect(0, 0, 16, 16)
                            fromRect:NSZeroRect
                           operation:NSCompositingOperationSourceOver
                            fraction:1.0];
                
                // Eject-Icon rechts 10x10, zentriert vertikal
                [ejectIcon drawInRect:NSMakeRect(18, 3, 10, 10) // y=3 um vertikal zu zentrieren
                             fromRect:NSZeroRect
                            operation:NSCompositingOperationSourceOver
                             fraction:1.0];
                
                [composite unlockFocus];
                [item setImage:composite];
            } else {
                [item setImage:redDot];
            }

            // Bindings
            [item bind:@"enabled" toObject:self withKeyPath:@"hasSshfs" options:nil];
            [item bind:@"enabled2"
               toObject:self
            withKeyPath:@"isWorking"
                options:@{NSValueTransformerNameBindingOption: NSNegateBooleanTransformerName}];

            [menu addItem:item];
        }
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *prefs = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Preferences", nil)
                                                   action:@selector(showPreferences:)
                                            keyEquivalent:@","];
    [prefs setTarget:self];
    [menu addItem:prefs];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Quit", nil)
                                                  action:@selector(doQuit:)
                                           keyEquivalent:@"q"];
    [quit setTarget:self];
    [menu addItem:quit];

    return menu;
}// eof buildStatusItemMenu

-(void)refreshStatusItemMenu {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->statusItem setMenu:[self statusItemMenu]];
        [self setLastMountedLocalPath:nil];
    });
} // eof refreshStatusItemMenu

-(void)findSshfs {
    // Pfad zur gebündelten Binary im Bundle
    NSString *sshfsPath = [[NSBundle mainBundle] pathForResource:@"sshfs" ofType:@"" inDirectory:@"bin"];

    if (sshfsPath == nil || ![[NSFileManager defaultManager] isExecutableFileAtPath:sshfsPath]) {
        NSLog(@"SSHFS binary not found or not executable at path: %@", sshfsPath);
        [self setHasSshfs:NO];
        return;
    }

    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    [preferences setValue:sshfsPath forKey:@"sshfsPath"];
    [preferences synchronize];
    
    [self setHasSshfs:YES];
}// eof findSshfs

-(void)checkATaskStatus:(NSNotification *)aNotification {
	if ([[aNotification object] processIdentifier] == sshfsFinderPID) {
		[self retrieveSshfsPathFromTask:[aNotification object]];
	} else if ([[aNotification object] processIdentifier] == shareMounterPID) {
		if ([[aNotification object] terminationStatus] != 0) {
            NSError *error = [NSError errorWithDomain:@"SSHFSManagerError"
                                                 code:-2
                                             userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Could not mount the selected share.", @"Fehlermeldung beim Mounten eines Shares")}];
			[[NSApplication sharedApplication] presentError:error];
			[self setLastMountedLocalPath:nil];
		} else {
			[self refreshStatusItemMenu];
		} // eof if()
		
		shareMounterPID = 0;
		[currentTask release];
		currentTask = nil;
		[self setIsWorking:NO];
	} // eof if()
} // eof checkATaskStatus:

- (void)retrieveSshfsPathFromTask:(NSTask *)aTask {
    if ([aTask terminationStatus] != 0) {
        // Auskommentierte Fehlerbehandlung und Logging ist nicht aktiv
        // ggf. hier wieder aktivieren, falls Fehlerbehandlung erwünscht
    } else {
        NSPipe *taskPipe = [aTask standardOutput];
        NSFileHandle *taskPipeFileHandle = [taskPipe fileHandleForReading];
        NSData *taskData = [taskPipeFileHandle availableData];
        NSString *sshfsBinaryPath = [[[NSString alloc] initWithData:taskData encoding:NSUTF8StringEncoding] autorelease];

        if ((sshfsBinaryPath != nil) && ([sshfsBinaryPath isEqualToString:@""] == NO)) {
            NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
            [preferences setValue:[sshfsBinaryPath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:@"sshfsPath"];
            [preferences synchronize];
        } else {
            // Auskommentierte Fehlerbehandlung
        } // eof if()
    } // eof if()
    sshfsFinderPID = 0;
    [self setIsWorking:NO];
} // eof retrieveSshfsPathFromTask:

-(void)managedObjectContextDidSave:(NSNotification *)aNotification {
	[self refreshStatusItemMenu];
} // eof managedObjectContextDidSave:

-(void)autoUpdateChangedFrom:(id)oldValue to:(id)newValue {
	if ((CFBooleanRef)newValue == kCFBooleanTrue) {
		[self setUpAutoUpdateTimer];
	} else if (((CFBooleanRef)newValue == kCFBooleanFalse) && (autoUpdateTimer != nil)) {
		[autoUpdateTimer invalidate];
		[autoUpdateTimer release];
		autoUpdateTimer = nil;
	} // eof if()
} // eof autoUpdateChangedFrom:to:

-(void)autoUpdateIntervalChangedFrom:(NSNumber *)oldInterval to:(NSNumber *)newInterval {
	[self setUpAutoUpdateTimer];
} // eof autoUpdateIntervalChangedFrom:to:
	
-(void)setUpAutoUpdateTimer {
	if (autoUpdateTimer != nil) {
		[autoUpdateTimer invalidate];
		[autoUpdateTimer release];
		autoUpdateTimer = nil;
	} // eof if()
	NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
	NSTimeInterval timerInterval = [preferences integerForKey:@"autoUpdateInterval"] * 60;
	NSDate *startDate = [NSDate dateWithTimeIntervalSinceNow:timerInterval];
	NSLog(@"Initializing timer...");
	autoUpdateTimer = [[NSTimer alloc] initWithFireDate:startDate interval:timerInterval target:self selector:@selector(fireTimer:) userInfo:nil repeats:YES];
	NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
	[runLoop addTimer:autoUpdateTimer forMode:NSDefaultRunLoopMode];
} // eof autoUpdateTimer

-(void)fireTimer:(NSTimer *)aTimer {
	[self refreshStatusItemMenu];
} // eof testTimer

-(IBAction)doMountShare:(id)sender {
    if ([sender state] == NSControlStateValueOn) return;

        NSDictionary *itemData = [sender itemData];
        if (!itemData) return;

        NSString *remotePath = [itemData objectForKey:@"remotePath"] ?: @"";
        NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
        NSString *sshfsPath = [preferences valueForKey:@"sshfsPath"];

        // Sicherheit: Pfad muss existieren und ausführbar sein
        if (sshfsPath == nil || ![[NSFileManager defaultManager] isExecutableFileAtPath:sshfsPath]) {
            NSLog(@"SSHFS binary not found or not executable at path: %@", sshfsPath);
            [self setHasSshfs:NO];
            return;
        }

        if (currentTask != nil) {
            [currentTask release];
            currentTask = nil;
        }

        currentTask = [[NSTask alloc] init];
        [currentTask setCurrentDirectoryPath:[@"~" stringByExpandingTildeInPath]];
        [currentTask setLaunchPath:sshfsPath];

        NSMutableArray *args = [NSMutableArray array];
        [args addObject:@"-p"];
        [args addObject:[NSString stringWithFormat:@"%d", [[itemData objectForKey:@"port"] intValue]]];
        [args addObject:[NSString stringWithFormat:@"%@@%@:%@",
                         [itemData objectForKey:@"login"],
                         [itemData objectForKey:@"host"],
                         remotePath]];
        [args addObject:[itemData objectForKey:@"localPath"]];
        [args addObject:[NSString stringWithFormat:@"-o%@,volname=%@",
                         [itemData objectForKey:@"options"],
                         [itemData objectForKey:@"volumeName"]]];

        [currentTask setArguments:args];

        @try {
            [currentTask launch];
        } @catch (NSException *exception) {
            NSLog(@"Failed to launch SSHFS: %@, reason: %@", sshfsPath, exception.reason);
            [self setHasSshfs:NO];
            return;
        }

        if ([currentTask isRunning]) {
            shareMounterPID = [currentTask processIdentifier];
            [self setIsWorking:YES];
            [self setLastMountedLocalPath:[itemData objectForKey:@"localPath"]];
        } // eof if()
} // eof doMountShare:

#pragma mark - Unmount Share

- (IBAction)doUnmountShare:(id)sender {
    if (![sender isKindOfClass:[BTHMenuItem class]]) return; // Sicherheit

    BTHMenuItem *item = (BTHMenuItem *)sender;
    NSDictionary *itemData = [item itemData];

    if (!itemData) return;

    NSString *localPath = itemData[@"localPath"];
    if (!localPath) return;

    // Unmount-Task starten
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/diskutil"];
    [task setArguments:@[@"unmount", localPath]];

    @try {
        [task launch];
    } @catch (NSException *exception) {
        NSLog(@"Failed to unmount %@: %@", localPath, exception.reason);
    }

    [task release];
    [self refreshStatusItemMenu];
}

- (void)unmountAtPath:(NSString *)path completion:(void (^)(BOOL success, NSError *error))completion {

    if (path == nil || [path length] == 0) {
        NSError *err = [NSError errorWithDomain:@"SSHFSManagerError"
                                           code:-10
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                   @"Unmount failed: localPath is empty."}];
        completion(NO, err);
        return;
    }

    // 1) diskutil (sanfter Unmount)
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/diskutil"];
    [task setArguments:@[@"unmount", path]];
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];

    __block pid_t pid = 0;

    [[NSNotificationCenter defaultCenter] addObserverForName:NSTaskDidTerminateNotification
                                                      object:task
                                                       queue:nil
                                                  usingBlock:^(NSNotification *note)
    {
        int status = [task terminationStatus];

        if (status == 0) {
            // Erfolg
            [[NSNotificationCenter defaultCenter] removeObserver:self];
            [task release];
            completion(YES, nil);
            return;
        }

        // 2) Fallback: "umount -f"
        NSTask *force = [[NSTask alloc] init];
        [force setLaunchPath:@"/sbin/umount"];
        [force setArguments:@[@"-f", path]];
        [force setStandardOutput:[NSPipe pipe]];
        [force setStandardError:[NSPipe pipe]];
        pid = [force processIdentifier];

        [[NSNotificationCenter defaultCenter] addObserverForName:NSTaskDidTerminateNotification
                                                          object:force
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note2)
        {
            int forceStatus = [force terminationStatus];
            [[NSNotificationCenter defaultCenter] removeObserver:self];
            [force release];

            if (forceStatus == 0) {
                completion(YES, nil);
            } else {
                NSError *err = [NSError errorWithDomain:@"SSHFSManagerError"
                                                   code:-11
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:@"Unable to unmount %@.", path]}];
                completion(NO, err);
            }
        }];

        [force launch];
    }];

    [task launch];
}

- (IBAction)doBrowseLocalPath:(id)sender {
    NSOpenPanel *localPathPanel = [NSOpenPanel openPanel];
    [localPathPanel setCanChooseFiles:NO];
    [localPathPanel setCanChooseDirectories:YES];
    [localPathPanel setAllowsMultipleSelection:NO];

    // Start-Verzeichnis setzen
    localPathPanel.directoryURL = [NSURL fileURLWithPath:[@"~" stringByExpandingTildeInPath]];

    [localPathPanel beginSheetModalForWindow:preferencesWindow completionHandler:^(NSInteger result) {
        // Cast von NSInteger auf int, um Konvertierungswarnungen zu vermeiden
        [self localPathBrowseSheetDidEnd:localPathPanel returnCode:(int)result contextInfo:NULL];
    }];
}

-(IBAction)doAddShare:(id)sender {
	[sharesController add:sender];
	[[shareNameField window] performSelector:@selector(makeFirstResponder:) withObject:shareNameField afterDelay:0.0];
} // eof doAddShare:

-(IBAction)showPreferences:(id)sender {
    // App in den Vordergrund holen
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    // Preferences-Fenster in den Vordergrund holen
    [preferencesWindow makeKeyAndOrderFront:sender];
} // eof showPreferences:

- (IBAction)toggleDockIcon:(NSButton *)sender {
    BOOL hideInDock = (sender.state == NSControlStateValueOn);

    // Aktivierungs-Policy setzen
    NSApplicationActivationPolicy policy = hideInDock ?
        NSApplicationActivationPolicyAccessory :
        NSApplicationActivationPolicyRegular;
    [[NSApplication sharedApplication] setActivationPolicy:policy];

    // UserDefaults speichern
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:hideInDock forKey:@"HideDockIcon"];
    [defaults synchronize];

    // Preferences-Fenster in den Vordergrund holen
    if ([preferencesWindow isVisible]) {
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        [preferencesWindow makeKeyAndOrderFront:self];
    }
}

-(IBAction)showAbout:(id)sender {
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
	[[NSApplication sharedApplication] orderFrontStandardAboutPanel:sender];
} // eof showAbout:

-(IBAction)doQuit:(id)sender {
	[[NSApplication sharedApplication] terminate:sender];
} // eof doQuit:
@end
