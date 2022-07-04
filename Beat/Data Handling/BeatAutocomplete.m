//
//  BeatAutocomplete.m
//  Beat
//
//  Created by Lauri-Matti Parppei on 1.7.2022.
//  Copyright © 2022 Lauri-Matti Parppei. All rights reserved.
//

#import "BeatAutocomplete.h"
#import "ContinuousFountainParser.h"
#import "BeatUserDefaults.h"

@interface BeatAutocomplete ()
@property (nonatomic, weak) IBOutlet NSPopUpButton *characterBox;
@end

@implementation BeatAutocomplete 

- (void)collectCharacterNames {
	/*
	 
	 So let me elaborate a bit. This is currently two systems upon each
	 other and two separate lists of character names are stored.
	 
	 Other use is to collect character cues for autocompletion.
	 There, it doesn't really matter if we have strange stuff after names,
	 because different languages can use their own abbreviations.
	 
	 Characters are also collected for the filtering feature, so we will
	 just strip away everything after the name (such as V.O. or O.S.), and
	 hope for the best.
		  
	 */
	
	[characterNames removeAllObjects];
	
	// If there was a character selected in Character Filter Box, save it
	NSString *selectedCharacter = _characterBox.selectedItem.title;
	
	NSMutableArray *characterList = NSMutableArray.new;
	NSMutableDictionary <NSString*, NSNumber*>* charactersAndLines = NSMutableDictionary.new;
	
	[_characterBox removeAllItems];
	[_characterBox addItemWithTitle:@" "]; // Add one empty item at the beginning
	
	Line* currentLine = self.delegate.currentLine;
	
	for (Line *line in self.delegate.parser.lines) {
		if ((line.isAnyCharacter) && line != currentLine
			) {
			// Character name, EXCLUDING any suffixes, such as (CONT'D), (V.O.') etc.
			NSString *character = line.characterName;
			// For some reason there are random misinterpretations of character cues, so skip empty lines
			if (character.length == 0) continue;
			
			// Add the character + suffix into dict and calculate number of appearances
			if (charactersAndLines[character]) {
				NSInteger lines = charactersAndLines[character].integerValue + 1;
				charactersAndLines[character] = [NSNumber numberWithInteger:lines];
			} else {
				charactersAndLines[character] = [NSNumber numberWithInteger:1];
			}
			
			// Add character to list
			if (character && ![characterList containsObject:character]) {
				[_characterBox addItemWithTitle:character]; // Add into the dropown
				[characterList addObject:character];
			}
		}
	}
	
	// Create an ordered list with all the character names. One with the most lines will be the first suggestion.
	// Btw, I don't think this works :-)
	NSArray *characters = [charactersAndLines keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2){
		return [obj2 compare:obj1];
	}];
	for (NSString *character in characters) {
		[characterNames addObject:character];
		[characterNames addObject:[NSString stringWithFormat:@"%@ (%@)", character, [BeatUserDefaults.sharedDefaults get:@"screenplayItemContd"]]];
	}
	
	// There was a character selected in the filtering menu, so select it again (if applicable)
	if (selectedCharacter.length) {
		for (NSMenuItem *item in _characterBox.itemArray) {
			if ([item.title isEqualToString:selectedCharacter]) [_characterBox selectItem:item];
		}
	}
}

- (void)collectHeadings {
	Line *currentLine = self.delegate.currentLine;
	
	[sceneHeadings removeAllObjects];
	for (Line *line in self.delegate.parser.lines) {
		NSString *sceneHeading = line.stripFormatting;
		
		if (line.type == heading &&
			line != currentLine &&
			![sceneHeadings containsObject:sceneHeading]) {
			[sceneHeadings addObject:sceneHeading];
		}
	}
}

- (void)autocompleteOnCurrentLine {
	Line *currentLine = self.delegate.currentLine;
	
	if (_delegate.textView.selectedRange.location == NSMaxRange(currentLine.textRange)) {

		if (currentLine.isAnyCharacter) {
			if (characterNames.count) [self collectCharacterNames];
			[_delegate.textView setAutomaticTextCompletionEnabled:YES];
		} else if (currentLine.type == heading) {
			if (!sceneHeadings.count) [self collectHeadings];
			[_delegate.textView setAutomaticTextCompletionEnabled:YES];
		} else {
			[characterNames removeAllObjects];
			[sceneHeadings removeAllObjects];
			[_delegate.textView setAutomaticTextCompletionEnabled:NO];
		}
		
	} else {
		[_delegate.textView setAutomaticTextCompletionEnabled:NO];
	}
}

#pragma mark - Autocomplete delegate method (forwarded from document)

- (NSArray *)textView:(NSTextView *)textView completions:(NSArray *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index {
	NSMutableArray *matches = [NSMutableArray array];
	NSMutableArray *search = [NSMutableArray array];
	
	Line *currentLine = self.delegate.currentLine;
	
	// Choose which array to search
	if (currentLine.type == character) search = characterNames;
	else if (currentLine.type == heading) search = sceneHeadings;
	
	// Find matching lines for the partially typed line
	for (NSString *string in search) {
		if ([string rangeOfString:[textView.string substringWithRange:charRange].uppercaseString options:NSAnchoredSearch range:NSMakeRange(0, string.length)].location != NSNotFound) {
			[matches addObject:string];
		}
	}
	
	[matches sortUsingSelector:@selector(compare:)];
	return matches;
}



@end
