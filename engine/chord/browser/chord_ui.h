// Copyright 2026 The Chord Authors
// ChordUI's Objective-C surface, as Chromium sees it.
//
// ChordUI is a Swift framework built by Xcode (app/ChordUI). Chromium does not link
// against it: //chord loads it at run time and reaches it through the Objective-C
// runtime. These declarations mirror app/ChordUI/Engine/ChordWebEngine.swift and
// app/ChordUI/ChordUIHost.swift, whose Objective-C names are fixed for that purpose;
// keep both sides in step.

#ifndef CHORD_BROWSER_CHORD_UI_H_
#define CHORD_BROWSER_CHORD_UI_H_

#import <AppKit/AppKit.h>

@protocol ChordWebPage;

@protocol ChordExtensionPopup <NSObject>
@property(nonatomic, readonly, strong) NSView* view;
@property(nonatomic, readonly) NSSize preferredSize;
@property(nonatomic, copy) void (^onResize)(void);
@property(nonatomic, copy) void (^onClose)(void);
- (void)close;
@end

@protocol ChordWebPageDelegate <NSObject>
- (void)pageDidUpdate:(id<ChordWebPage>)page;
- (void)page:(id<ChordWebPage>)page wantsNewTabWith:(NSURL*)url;
@optional
- (BOOL)page:(id<ChordWebPage>)page
    shouldFollowLinkTo:(NSURL*)url
             modifiers:(NSEventModifierFlags)modifiers;
- (void)page:(id<ChordWebPage>)page
    didStartDownload:(NSString*)downloadID
         destination:(NSURL*)destination;
- (void)page:(id<ChordWebPage>)page
       download:(NSString*)downloadID
    didProgress:(double)fraction;
- (void)page:(id<ChordWebPage>)page
       download:(NSString*)downloadID
    didFinishAt:(NSURL*)fileURL;
- (void)page:(id<ChordWebPage>)page
         download:(NSString*)downloadID
    needsApproval:(NSString*)warning;
- (void)page:(id<ChordWebPage>)page
    didFindMatches:(NSInteger)count
       activeMatch:(NSInteger)activeMatch
           isFinal:(BOOL)isFinal;
@end

@protocol ChordWebPage <NSObject>
@property(nonatomic, readonly, strong) NSView* view;
@property(nonatomic, readonly, copy) NSURL* url;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly) BOOL isLoading;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
@property(nonatomic, weak) id<ChordWebPageDelegate> delegate;
- (void)load:(NSURL*)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
@optional
@property(nonatomic, readonly, copy) NSData* faviconData;
- (void)reloadIgnoringCache;
- (void)didBecomeActive;
- (void)toggleDevTools;
@property(nonatomic, readonly, strong) NSView* devToolsView;
- (NSRect)pageFrameWithDevToolsIn:(NSSize)size;
- (void)enterPictureInPictureIfPlaying;
- (void)exitPictureInPicture;
- (void)togglePictureInPicture;
- (NSString*)permissionState:(NSString*)permission;
- (void)setPermission:(NSString*)permission state:(NSString*)state;
- (NSArray<NSDictionary<NSString*, NSString*>*>*)sitePermissions;
@property(nonatomic, readonly, copy)
    NSArray<NSDictionary<NSString*, id>*>* extensions;
- (id<ChordExtensionPopup>)runExtension:(NSString*)extensionID;
- (void)setExtension:(NSString*)extensionID pinned:(BOOL)pinned;
- (void)uninstallExtension:(NSString*)extensionID;
- (void)find:(NSString*)text forward:(BOOL)forward;
- (void)stopFinding;
- (void)zoom:(NSInteger)direction;
@property(nonatomic, readonly) NSInteger zoomPercent;
- (void)printPage;
@property(nonatomic, readonly) BOOL isAudible;
@property(nonatomic, readonly) BOOL isMuted;
- (void)setMuted:(BOOL)muted;
@property(nonatomic, readonly) BOOL isCapturingMedia;
@property(nonatomic, readonly) BOOL isSharingScreen;
@property(nonatomic, readonly) BOOL isBeingShared;
- (void)stopSharing;
@property(nonatomic, readonly, copy) NSString* securityState;
@property(nonatomic, readonly) BOOL isCrashed;
@property(nonatomic, readonly) BOOL isFullscreen;
@property(nonatomic, readonly) BOOL hasMedia;
@property(nonatomic, readonly) BOOL isPlayingMedia;
- (void)toggleMediaPlayback;
- (BOOL)sleep;
@property(nonatomic, readonly) BOOL isAsleep;
- (void)wake;
@end

@protocol ChordPermissionRequest <NSObject>
@property(nonatomic, readonly, copy) NSString* site;
@property(nonatomic, readonly, copy) NSArray<NSString*>* asks;
@property(nonatomic, readonly, copy) NSString* symbol;
@property(nonatomic, copy) void (^onCancel)(void);
@optional
@property(nonatomic, readonly, copy) NSString* question;
@property(nonatomic, readonly, copy) NSString* detail;
@property(nonatomic, readonly, copy) NSString* allowTitle;
@property(nonatomic, readonly, copy) NSString* blockTitle;
@property(nonatomic, readonly, copy) NSString* dismissTitle;
@required
- (void)allow;
- (void)block;
- (void)dismiss;
@end

@protocol ChordWebEngine;

@protocol ChordWebEngineDelegate <NSObject>
- (void)engine:(id<ChordWebEngine>)engine
        didOpen:(id<ChordWebPage>)page
         opener:(id<ChordWebPage>)opener
    inBackground:(BOOL)inBackground;
- (void)engine:(id<ChordWebEngine>)engine didClose:(id<ChordWebPage>)page;
@optional
- (void)engine:(id<ChordWebEngine>)engine wantsToShow:(id<ChordWebPage>)page;
- (void)engine:(id<ChordWebEngine>)engine
          page:(id<ChordWebPage>)page
      requests:(id<ChordPermissionRequest>)request;
- (void)engineExtensionsDidChange:(id<ChordWebEngine>)engine;
@end

@protocol ChordWebEngine <NSObject>
- (id<ChordWebPage>)makePage;
@optional
- (void)cancelDownload:(NSString*)downloadID;
- (void)keepDownload:(NSString*)downloadID;
- (void)setDelegate:(id<ChordWebEngineDelegate>)delegate;
- (id<ChordWebEngine>)makePrivateEngine;
- (id<ChordWebEngine>)engineForProfile:(NSString*)profileID;
- (void)deleteProfile:(NSString*)profileID;
- (void)deleteProfilesExcept:(NSArray<NSString*>*)profileIDs;
- (void)resetAllDataAndRelaunch;
- (BOOL)ownsPage:(id<ChordWebPage>)page;
- (void)importFromArc:(NSString*)arcProfile
           completion:
               (void (^)(NSDictionary<NSString*, NSNumber*>*))completion;
- (void)importFromBrowser:(NSString*)name
            keychainService:(NSString*)service
            keychainAccount:(NSString*)account
                    profile:(NSString*)profilePath
                 completion:
                     (void (^)(NSDictionary<NSString*, NSNumber*>*))completion;
- (void)addHistory:(NSArray<NSDictionary<NSString*, id>*>*)pages;
- (void)suggest:(NSString*)text
     completion:
         (void (^)(NSArray<NSDictionary<NSString*, NSString*>*>*))completion;
@end

// The class methods of ChordUIHost, reached with NSClassFromString(@"ChordUIHost").
@protocol ChordUIHostInterface
+ (void)startWithEngine:(id<ChordWebEngine>)engine
                appName:(NSString*)appName
       supportDirectory:(NSURL*)supportDirectory;
+ (void)openURLs:(NSArray<NSURL*>*)urls;
+ (void)reopen;
+ (NSMenu*)mainMenu;
+ (NSWindow*)mainWindow;
+ (void)saveNow;
@optional
// A page went full screen or took the pointer or the keyboard: `text` says how to get
// out ("Press esc to exit full screen"), shown at the top of the page for a moment.
+ (void)showNotice:(NSString*)text inWindow:(NSWindow*)window;
@end

#endif  // CHORD_BROWSER_CHORD_UI_H_
