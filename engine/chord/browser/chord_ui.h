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
@property(nonatomic, readonly, copy) NSURL* faviconURL;
- (void)reloadIgnoringCache;
- (void)didBecomeActive;
- (void)toggleDevTools;
@property(nonatomic, readonly, strong) NSView* devToolsView;
- (NSRect)pageFrameWithDevToolsIn:(NSSize)size;
- (void)enterPictureInPictureIfPlaying;
- (void)exitPictureInPicture;
- (void)togglePictureInPicture;
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
@end

@protocol ChordWebEngine <NSObject>
- (id<ChordWebPage>)makePage;
@optional
- (void)cancelDownload:(NSString*)downloadID;
- (void)setDelegate:(id<ChordWebEngineDelegate>)delegate;
- (id<ChordWebEngine>)makePrivateEngine;
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
@end

#endif  // CHORD_BROWSER_CHORD_UI_H_
