//
//  BeatNotepad.m
//  Beat
//
//  Created by Lauri-Matti Parppei on 21.10.2021.
//  Copyright © 2021 Lauri-Matti Parppei. All rights reserved.
//
/**
 
 Saved notepad content format:
 <beatColorName>text</beatColorName>
 
 Notepad uses `BeatMarkdownTextStorage` which has a *very* bare-bones markdown parser and automatically stylizes text.
 
 */

#import <BeatParsing/BeatParsing.h>
#import <QuartzCore/QuartzCore.h>
#import <BeatThemes/BeatThemes.h>
#import <BeatPlugins/BeatPlugins.h>
#import <BeatCore/BeatCore-Swift.h>

#import "BeatNotepad.h"
#import "Beat-Swift.h"
#import "ColorCheckbox.h"

@interface BeatNotepad ()
@property (nonatomic) NSString *currentColorName;
@property (nonatomic) NSColor *currentColor;

@property (nonatomic) NSArray<ColorCheckbox*> *buttons;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonDefault;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonRed;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonBlue;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonBrown;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonOrange;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonGreen;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonPink;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonCyan;
@property (nonatomic, weak) IBOutlet ColorCheckbox *buttonMagenta;
@property (nonatomic) DynamicColor* defaultColor;
@property (nonatomic) BeatMarkdownTextStorageDelegate* mdDelegate;
@property (nonatomic) NSMutableArray* observers;

@end
@implementation BeatNotepad

-(instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	
	if (self) {
		// Create a default color
		self.defaultColor = [DynamicColor.alloc initWithLightColor:[NSColor colorWithWhite:0.1 alpha:1.0] darkColor:[NSColor colorWithWhite:0.9 alpha:1.0]];
		
		self.wantsLayer = YES;
		self.layer.cornerRadius = 10.0;
		self.layer.backgroundColor = [NSColor.darkGrayColor colorWithAlphaComponent:0.3].CGColor;
		self.textColor = self.defaultColor;
		
		[self setTextContainerInset:(NSSize){ 5, 5 }];
	}
	
	return self;
}

-(void)awakeFromNib {
	self.buttons = @[self.buttonDefault, self.buttonRed, self.buttonGreen, self.buttonBlue, self.buttonPink, self.buttonOrange, self.buttonBrown, self.buttonCyan, self.buttonMagenta];
	
	self.buttonDefault.state = NSOnState;
	
	[self setColor:@"default"];
	self.textColor = self.currentColor;
	self.buttonDefault.itemColor = self.defaultColor;
	
	self.mdDelegate = BeatMarkdownTextStorageDelegate.new;
	self.mdDelegate.textStorage = self.textStorage;
	self.textStorage.delegate = self.mdDelegate;
	
	[self.textStorage setAttributedString:[self coloredRanges:self.string]];
	
	[self setTypingAttributes:@{
		NSForegroundColorAttributeName: _currentColor
	}];
}

- (void)setup
{
	NSString* notes = [self.editorDelegate.documentSettings getString:@"Notes"];
	if (notes.length > 0) [self loadString:notes];
}

- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
}

- (void)scrollWheel:(NSEvent *)event
{
	// For some reason we need to do this on macOS Sonoma.
	// No events are registered in the scroll view when another scroll view is earlier in responder chain in this window. No idea.
	if (@available(macOS 14.0, *)) {
		CGPoint p = [self convertPoint:event.locationInWindow fromView:nil];
		
		if ([self mouse:p inRect:self.bounds]) {
			[self.enclosingScrollView scrollWheel:event];
			return;
		}
	}
	[super scrollWheel:event];
}


#pragma mark - Loading and storing text

-(void)loadString:(NSString*)string
{
	[self.textStorage setAttributedString:[self coloredRanges:string]];
}

- (NSAttributedString*)coloredRanges:(NSString*)fullString
{
	// Iterate through <colorName>...</colorName>, add colors to tagged ranges,
	// and afterwards remove the tags enumerating the index set which contains ranges for tags.
	
	NSMutableAttributedString *attrStr = [NSMutableAttributedString.alloc initWithString:fullString];
	[attrStr addAttribute:NSForegroundColorAttributeName value:self.currentColor range:(NSRange){ 0, attrStr.length }];
	
	NSMutableIndexSet *keyRanges = NSMutableIndexSet.new;
	
	for (NSString *color in BeatColors.colors.allKeys) {
		NSColor* colorObj = [BeatColors color:color];
		
		NSString *open = [NSString stringWithFormat:@"<%@>", color];
		NSString *close = [NSString stringWithFormat:@"</%@>", color];
		
		NSInteger prevLoc = 0;
		NSRange openRange;
		NSRange closeRange = NSMakeRange(0, 0);
		
		do {
			openRange = [attrStr.string rangeOfString:open options:0 range:NSMakeRange(prevLoc, attrStr.length - prevLoc)];
			if (openRange.location == NSNotFound) continue;
			
			closeRange = [attrStr.string rangeOfString:close options:0 range:NSMakeRange(prevLoc, attrStr.length - prevLoc)];
			if (closeRange.location == NSNotFound) continue;
			
			[attrStr addAttribute:NSForegroundColorAttributeName value:colorObj range:(NSRange){ openRange.location, NSMaxRange(closeRange) - openRange.location }];
			
			[keyRanges addIndexesInRange:openRange];
			[keyRanges addIndexesInRange:closeRange];
			
			prevLoc = NSMaxRange(closeRange);
		} while (openRange.location != NSNotFound && closeRange.location != NSNotFound);
		
	}
	
	// Create an index set with full string
	NSMutableIndexSet *visibleIndices = [NSMutableIndexSet.alloc initWithIndexesInRange:NSMakeRange(0, attrStr.length)];
	[keyRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		[visibleIndices removeIndexesInRange:range];
	}];
	
	NSMutableAttributedString *result = NSMutableAttributedString.new;
	[visibleIndices enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		[result appendAttributedString:[attrStr attributedSubstringFromRange:range]];
	}];
	
	return result;
}

- (void)saveToDocument
{
	[self.editorDelegate.documentSettings set:@"Notes" as:[self stringForSaving]];
}

- (NSString*)stringForSaving
{
	NSMutableString *result = [NSMutableString.alloc initWithString:@""];
	
	[self.attributedString enumerateAttribute:NSForegroundColorAttributeName inRange:(NSRange){0,self.string.length} options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
		
		NSString *colorTag;
		
		// Do nothing for default color
		if (value != self.defaultColor) {
			for (NSString *colorName in BeatColors.colors.allKeys) {
				if (BeatColors.colors[colorName] == value) {
					colorTag = colorName;
					break;
				}
			}
		}
		
		if (colorTag) {
			[result appendFormat:@"<%@>", colorTag];
			[result appendString:[self.string substringWithRange:range]];
			[result appendFormat:@"</%@>", colorTag];
		} else {
			[result appendString:[self.string substringWithRange:range]];
		}
	}];
	
	return result;
}



#pragma mark - Text events and I/O

-(void)didChangeText
{
	// Save contents into document settings
	[self saveToDocument];
	[self.editorDelegate addToChangeCount];
	[super didChangeText];
	[self notifyTextChange];
}

- (void)notifyTextChange
{
	if (_observerDisabled) return;
	for (id<BeatTextChangeObserver>observer in self.observers) [observer observedTextDidChange:self];
}

- (void)replaceRange:(NSInteger)position length:(NSInteger)length string:(NSString*)string color:(NSString*)colorName
{
	NSRange range = NSMakeRange(position, length);
	if (NSMaxRange(range) > self.string.length) {
		[BeatConsole.shared logToConsole:@"ERROR: replaceRange: selection out of range" pluginName:@"notepad" context:nil];
		return;
	}
	
	NSColor* color;
	if (colorName.length > 0) color = [BeatColors color:colorName];
	if (color == nil) color = _currentColor;
	
	NSAttributedString* result = [NSAttributedString.alloc initWithString:string attributes:@{
		NSForegroundColorAttributeName: color
	}];
	
	
	if ([self shouldChangeTextInRange:range replacementString:string]) {
		[self.textStorage beginEditing];
		[self.textStorage replaceCharactersInRange:range withAttributedString:result];
		[self.textStorage endEditing];
		
		[self didChangeText];
	}
}

- (void)setSelectedRange:(NSRange)selectedRange
{
	if (NSMaxRange(selectedRange) > self.text.length) return;
	[super setSelectedRange:selectedRange];
}

#pragma mark - UI actions

-(IBAction)setInputColor:(id)sender
{
	ColorCheckbox *box = sender;
	[self setColor:box.colorName];
	
	for (ColorCheckbox *button in _buttons) {
		if ([button.colorName isEqualToString:_currentColorName]) button.state = NSOnState;
		else button.state = NSControlStateValueOff;
	}
	
	if (self.selectedRange.length) {
		// If a range was selected when color was changed, save it to document
		NSRange range = self.selectedRange;
		NSAttributedString *attrStr = [self.attributedString attributedSubstringFromRange:range];
		[self.textStorage addAttribute:NSForegroundColorAttributeName value:_currentColor range:range];
		
		[self.undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
			[self.textStorage replaceCharactersInRange:range withAttributedString:attrStr];
		}];
		[self saveToDocument];
	}
	
	[self setTypingAttributes:@{
		NSForegroundColorAttributeName: _currentColor
	}];
	
	self.selectedRange = (NSRange){ self.selectedRange.location + self.selectedRange.length, 0 };
}

/// Sets the current input color
- (void)setColor:(NSString*)colorName
{
	self.currentColorName = colorName;
	
	if ([colorName isEqualToString:@"default"]) {
		self.currentColor = self.defaultColor;
	} else {
		self.currentColor = [BeatColors color:colorName];
	}
}


/// Cuts a piece of text from editor to notepad
- (IBAction)cutToNotepad:(id)sender
{
	NSRange range = self.editorDelegate.selectedRange;
	NSString* string = [self.editorDelegate.text substringWithRange:range];
	
	// Add line breaks if needed
	if (self.text.length > 1 && [self.text characterAtIndex:self.text.length - 1] != '\n') {
		string = [NSString stringWithFormat:@"\n\n%@", string];
	}
	
	[self replaceCharactersInRange:NSMakeRange(self.string.length, 0) withString:string];
	[self didChangeText];
	
	[self.editorDelegate replaceRange:range withString:@""];
	
	[self.undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
		[self replaceCharactersInRange:NSMakeRange(self.string.length - string.length, string.length) withString:@""];
	}];
}


#pragma mark - Make observable for plugins

- (void)addTextChangeObserver:(id<BeatTextChangeObserver>)observer
{
	if (_observers == nil) _observers = NSMutableArray.new;
	[self.observers addObject:observer];
}

- (void)removeTextChangeObserver:(id<BeatTextChangeObserver>)observer
{
	[self.observers removeObject:observer];
}


@end
/*
 
 lopulta unohdan yksityiskohdat
 mun rauhattomasta nuoruudesta
 silti muistan
 sinut tuollaisena
 selaamassa ydinräjähdysten kuvia
 vain niiden kauneuden takia
 
 */
