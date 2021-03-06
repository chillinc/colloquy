#import "JVAppearancePreferences.h"
#import "JVStyle.h"
#import "JVStyleView.h"
#import "JVEmoticonSet.h"
#import "JVFontPreviewField.h"
#import "JVColorWellCell.h"
#import "JVDetailCell.h"
#import "NSBundleAdditions.h"

#import <objc/objc-runtime.h>

@interface WebView (WebViewPrivate) // WebKit 1.3 pending public API
- (void) setDrawsBackground:(BOOL) draws;
- (BOOL) drawsBackground;
@end

#pragma mark -

@implementation JVAppearancePreferences
- (id) init {
	if( ( self = [super init] ) ) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( colorWellDidChangeColor: ) name:JVColorWellCellColorDidChangeNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( updateChatStylesMenu ) name:JVStylesScannedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( updateEmoticonsMenu ) name:JVEmoticonSetsScannedNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( reloadStyles: ) name:NSApplicationDidBecomeActiveNotification object:[NSApplication sharedApplication]];

		_style = nil;
		_styleOptions = nil;
		_userStyle = nil;
	}
	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[optionsTable setDataSource:nil];
	[optionsTable setDelegate:nil];

	[optionsDrawer setDelegate:nil];

	[preview setUIDelegate:nil];
	[preview setResourceLoadDelegate:nil];
	[preview setDownloadDelegate:nil];
	[preview setFrameLoadDelegate:nil];
	[preview setPolicyDelegate:nil];

	_style = nil;

}

- (NSString *) preferencesNibName {
	return @"JVAppearancePreferences";
}

- (BOOL) hasChangesPending {
	return NO;
}

- (NSImage *) imageForPreferenceNamed:(NSString *) name {
	return [NSImage imageNamed:@"AppearancePreferences"];
}

- (BOOL) isResizable {
	return NO;
}

- (void) moduleWillBeRemoved {
	[optionsDrawer close];
}

#pragma mark -

- (void) selectStyleWithIdentifier:(NSString *) identifier {
	[self setStyle:[JVStyle styleWithIdentifier:identifier]];
	[self changePreferences];
}

- (void) selectEmoticonsWithIdentifier:(NSString *) identifier {
	JVEmoticonSet *emoticonSet = [JVEmoticonSet emoticonSetWithIdentifier:identifier];
	[_style setDefaultEmoticonSet:emoticonSet];
	[preview setEmoticons:emoticonSet];
	[self updateEmoticonsMenu];
}

#pragma mark -

- (void) setStyle:(JVStyle *) style {
	_style = style;

	JVChatTranscript *transcript = [JVChatTranscript chatTranscriptWithContentsOfURL:[_style previewTranscriptLocation]];
	[preview setTranscript:transcript];

	[preview setEmoticons:[_style defaultEmoticonSet]];
	[preview setStyle:_style];

	[[NSNotificationCenter defaultCenter] removeObserver:self name:JVStyleVariantChangedNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( updateVariant ) name:JVStyleVariantChangedNotification object:_style];
}

#pragma mark -

- (void) initializeFromDefaults {
	[preview setPolicyDelegate:self];
	[preview setUIDelegate:self];
	[optionsTable setRefusesFirstResponder:YES];

	NSTableColumn *column = [optionsTable tableColumnWithIdentifier:@"key"];
	JVDetailCell *prototypeCell = [JVDetailCell new];
	[prototypeCell setFont:[NSFont boldSystemFontOfSize:11.]];
	[prototypeCell setAlignment:NSRightTextAlignment];
	[column setDataCell:prototypeCell];

	[JVStyle scanForStyles];
	[self setStyle:[JVStyle defaultStyle]];

	[self changePreferences];
}

- (IBAction) changeBaseFontSize:(id) sender {
	NSInteger size = [sender intValue];
	[baseFontSize setIntValue:size];
	[baseFontSizeStepper setIntValue:size];
	[[preview preferences] setDefaultFontSize:size];
}

- (IBAction) changeMinimumFontSize:(id) sender {
	NSInteger size = [sender intValue];
	[minimumFontSize setIntValue:size];
	[minimumFontSizeStepper setIntValue:size];
	[[preview preferences] setMinimumFontSize:size];
}

- (IBAction) changeDefaultChatStyle:(id) sender {
	JVStyle *style = [[sender representedObject] objectForKey:@"style"];
	NSString *variant = [[sender representedObject] objectForKey:@"variant"];

	if( style == _style ) {
		[_style setDefaultVariantName:variant];

		_styleOptions = [[_style styleSheetOptions] mutableCopy];

		[self updateChatStylesMenu];

		if( _variantLocked ) [optionsTable deselectAll:nil];

		[self updateVariant];
		[self parseStyleOptions];
	} else {
		[self setStyle:style];

		[JVStyle setDefaultStyle:_style];
		[_style setDefaultVariantName:variant];

		[self changePreferences];
	}
}

- (void) changePreferences {
	[self updateChatStylesMenu];
	[self updateEmoticonsMenu];

	_styleOptions = [[_style styleSheetOptions] mutableCopy];

	[preview setPreferencesIdentifier:[_style identifier]];

	WebPreferences *prefs = [preview preferences];
	[prefs setAutosaves:YES];

	// disable the user style sheet for users of 2C4 who got this
	// turned on, we do this different now and the user style can interfere
	[prefs setUserStyleSheetEnabled:NO];

	[standardFont setFont:[NSFont fontWithName:[prefs standardFontFamily] size:[prefs defaultFontSize]]];

	[minimumFontSize setIntValue:[prefs minimumFontSize]];
	[minimumFontSizeStepper setIntValue:[prefs minimumFontSize]];

	[baseFontSize setIntValue:[prefs defaultFontSize]];
	[baseFontSizeStepper setIntValue:[prefs defaultFontSize]];

	if( _variantLocked ) [optionsTable deselectAll:nil];

	[self parseStyleOptions];
}

- (IBAction) changeDefaultEmoticons:(id) sender {
	[self selectEmoticonsWithIdentifier:[sender representedObject]];
}

#pragma mark -

- (void) updateChatStylesMenu {
	NSString *variant = [_style defaultVariantName];

	_variantLocked = ! [_style isUserVariantName:variant];

	NSMenu *menu = [[NSMenu alloc] initWithTitle:@""], *subMenu = nil;
	NSMenuItem *menuItem = nil, *subMenuItem = nil;

	id item = nil;
	for( JVStyle *style in [[[JVStyle styles] allObjects] sortedArrayUsingSelector:@selector( compare: )] ) {
		menuItem = [[NSMenuItem alloc] initWithTitle:[style displayName] action:@selector( changeDefaultChatStyle: ) keyEquivalent:@""];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:style, @"style", nil]];
		if( [_style isEqualTo:style] ) [menuItem setState:NSOnState];
		[menu addItem:menuItem];

		NSArray *variants = [style variantStyleSheetNames];
		NSArray *userVariants = [style userVariantStyleSheetNames];

		if( [variants count] || [userVariants count] ) {
			subMenu = [[NSMenu alloc] initWithTitle:@""];

			subMenuItem = [[NSMenuItem alloc] initWithTitle:[style mainVariantDisplayName] action:@selector( changeDefaultChatStyle: ) keyEquivalent:@""];
			[subMenuItem setTarget:self];
			[subMenuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:style, @"style", nil]];
			if( [_style isEqualTo:style] && ! variant ) [subMenuItem setState:NSOnState];
			[subMenu addItem:subMenuItem];

			for( item in variants ) {
				subMenuItem = [[NSMenuItem alloc] initWithTitle:item action:@selector( changeDefaultChatStyle: ) keyEquivalent:@""];
				[subMenuItem setTarget:self];
				[subMenuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:style, @"style", item, @"variant", nil]];
				if( [_style isEqualTo:style] && [variant isEqualToString:item] )
					[subMenuItem setState:NSOnState];
				[subMenu addItem:subMenuItem];
			}

			if( [userVariants count] ) [subMenu addItem:[NSMenuItem separatorItem]];

			for( item in userVariants ) {
				subMenuItem = [[NSMenuItem alloc] initWithTitle:item action:@selector( changeDefaultChatStyle: ) keyEquivalent:@""];
				[subMenuItem setTarget:self];
				[subMenuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:style, @"style", item, @"variant", nil]];
				if( [_style isEqualTo:style] && [variant isEqualToString:item] )
					[subMenuItem setState:NSOnState];
				[subMenu addItem:subMenuItem];
			}

			[menuItem setSubmenu:subMenu];
		}

		subMenu = nil;
	}

	[styles setMenu:menu];
}

- (void) updateEmoticonsMenu {
	NSMenu *menu = nil;
	NSMenuItem *menuItem = nil;
	JVEmoticonSet *defaultEmoticon = [_style defaultEmoticonSet];

	menu = [[NSMenu alloc] initWithTitle:@""];

	JVEmoticonSet *emoticon = [JVEmoticonSet textOnlyEmoticonSet];
	menuItem = [[NSMenuItem alloc] initWithTitle:[emoticon displayName] action:@selector( changeDefaultEmoticons: ) keyEquivalent:@""];
	[menuItem setTarget:self];
	[menuItem setRepresentedObject:[emoticon identifier]];
	if( [defaultEmoticon isEqual:emoticon] ) [menuItem setState:NSOnState];
	[menu addItem:menuItem];

	[menu addItem:[NSMenuItem separatorItem]];

	for( JVEmoticonSet *emoticon in [[[JVEmoticonSet emoticonSets] allObjects] sortedArrayUsingSelector:@selector( compare: )] ) {
		if( ! [[emoticon displayName] length] ) continue;
		menuItem = [[NSMenuItem alloc] initWithTitle:[emoticon displayName] action:@selector( changeDefaultEmoticons: ) keyEquivalent:@""];
		[menuItem setTarget:self];
		[menuItem setRepresentedObject:[emoticon identifier]];
		if( [defaultEmoticon isEqual:emoticon] ) [menuItem setState:NSOnState];
		[menu addItem:menuItem];
	}

	[emoticons setMenu:menu];
}

- (void) updateVariant {
	[preview setStyleVariant:[_style defaultVariantName]];
	[preview reloadCurrentStyle];
}

#pragma mark -

- (void) fontPreviewField:(JVFontPreviewField *) field didChangeToFont:(NSFont *) font {
	[[preview preferences] setStandardFontFamily:[font familyName]];
	[[preview preferences] setFixedFontFamily:[font familyName]];
	[[preview preferences] setSerifFontFamily:[font familyName]];
	[[preview preferences] setSansSerifFontFamily:[font familyName]];
}

- (NSArray *) webView:(WebView *) sender contextMenuItemsForElement:(NSDictionary *) element defaultMenuItems:(NSArray *) defaultMenuItems {
	return nil;
}

- (void) webView:(WebView *) sender decidePolicyForNavigationAction:(NSDictionary *) actionInformation request:(NSURLRequest *) request frame:(WebFrame *) frame decisionListener:(id <WebPolicyDecisionListener>) listener {
	NSURL *url = [actionInformation objectForKey:WebActionOriginalURLKey];

	if( [[url scheme] isEqualToString:@"about"] ) {
		if( [[[url standardizedURL] path] length] ) [listener ignore];
		else [listener use];
	} else if( [url isFileURL] && [[url path] hasPrefix:[[NSBundle mainBundle] resourcePath]] ) {
		[listener use];
	} else {
		[[NSWorkspace sharedWorkspace] openURL:url];
		[listener ignore];
	}
}

#pragma mark -

- (void) buildFileMenuForCell:(NSPopUpButtonCell *) cell andOptions:(NSMutableDictionary *) options {
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
	NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"None", "no background image label" ) action:NULL keyEquivalent:@""];
	[menuItem setRepresentedObject:@"none"];
	[menu addItem:menuItem];

	NSArray *files = [[_style bundle] pathsForResourcesOfType:nil inDirectory:[options objectForKey:@"folder"]];
	NSString *resourcePath = [[_style bundle] resourcePath];
	BOOL matched = NO;

	if( [files count] ) [menu addItem:[NSMenuItem separatorItem]];

	for( NSString *path in files ) {
		NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
		NSRect rect = NSMakeRect( 0., 0., 12., 12. );
		NSImageRep *sourceImageRep = [icon bestRepresentationForRect:rect context:[NSGraphicsContext currentContext] hints:nil];
		NSImage *smallImage = [[NSImage alloc] initWithSize:NSMakeSize( 12., 12. )];
		[smallImage lockFocus];
		[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationLow];
		[sourceImageRep drawInRect:rect];
		[smallImage unlockFocus];

		menuItem = [[NSMenuItem alloc] initWithTitle:[[[NSFileManager defaultManager] displayNameAtPath:path] stringByDeletingPathExtension] action:NULL keyEquivalent:@""];
		[menuItem setImage:smallImage];
		[menuItem setRepresentedObject:path];
		[menuItem setTag:5];
		[menu addItem:menuItem];

		NSString *fullPath = ( [[options objectForKey:@"path"] isAbsolutePath] ? [options objectForKey:@"path"] : [resourcePath stringByAppendingPathComponent:[options objectForKey:@"path"]] );
		if( [path isEqualToString:fullPath] ) {
			NSInteger index = [menu indexOfItemWithRepresentedObject:path];
			[options setObject:[NSNumber numberWithLong:index] forKey:@"value"];
			matched = YES;
		}
	}

	NSString *path = [options objectForKey:@"path"];
	if( ! matched && [path length] ) {
		[menu addItem:[NSMenuItem separatorItem]];

		NSString *fullPath = ( [path isAbsolutePath] ? path : [resourcePath stringByAppendingPathComponent:path] );
		NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:fullPath];
		NSRect rect = NSMakeRect( 0., 0., 12., 12. );
		NSImageRep *sourceImageRep = [icon bestRepresentationForRect:rect context:[NSGraphicsContext currentContext] hints:nil];
		NSImage *smallImage = [[NSImage alloc] initWithSize:NSMakeSize( 12., 12. )];
		[smallImage lockFocus];
		[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationLow];
		[sourceImageRep drawInRect:rect];
		[smallImage unlockFocus];

		menuItem = [[NSMenuItem alloc] initWithTitle:[[NSFileManager defaultManager] displayNameAtPath:path] action:NULL keyEquivalent:@""];
		[menuItem setImage:smallImage];
		[menuItem setRepresentedObject:path];
		[menuItem setTag:10];
		[menu addItem:menuItem];

		NSInteger index = [menu indexOfItemWithRepresentedObject:path];
		[options setObject:[NSNumber numberWithLong:index] forKey:@"value"];
	}

	[menu addItem:[NSMenuItem separatorItem]];

	menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString( @"Other...", "other image label" ) action:@selector( selectImageFile: ) keyEquivalent:@""];
	[menuItem setTarget:self];
	[menuItem setTag:10];
	[menu addItem:menuItem];

	[cell setMenu:menu];
	[cell synchronizeTitleAndSelectedItem];
	[optionsTable performSelector:@selector( reloadData ) withObject:nil afterDelay:0.];
}

#pragma mark -

// Called when Colloquy reactivates.
- (void) reloadStyles:(NSNotification *) notification {
	if( ! [[preview window] isVisible] ) return;
	[JVStyle scanForStyles];

	if( ! [_userStyle length] ) return;
	[self parseStyleOptions];
	[self updateVariant];
}

// Parses the style options plist and reads the CSS files to figure out the current selected values.
- (void) parseStyleOptions {
	[self setUserStyle:[_style contentsOfVariantStyleSheetWithName:[_style defaultVariantName]]];

	NSString *css = _userStyle;
	css = [css stringByAppendingString:[_style contentsOfMainStyleSheet]];

	// Step through each options.
	for( NSMutableDictionary *info in _styleOptions ) {
		NSMutableArray *styleLayouts = [NSMutableArray array];
		NSArray *sarray = nil;
		if( ! [info objectForKey:@"style"] ) continue;
		if( [[info objectForKey:@"style"] isKindOfClass:[NSArray class]] && [[info objectForKey:@"type"] isEqualToString:@"list"] )
			sarray = [info objectForKey:@"style"];
		else sarray = [NSArray arrayWithObject:[info objectForKey:@"style"]];

		[info removeObjectForKey:@"value"]; // Clear any old values, we will get the new value later on.

		// Step through each style choice per option, colors have only one; lists have one style per list item.
		NSUInteger count = 0;
		for( NSString *style in sarray ) {
			// Parse all the selectors in the style.
			AGRegex *regex = [AGRegex regexWithPattern:@"(\\S.*?)\\s*\{([^\\}]*?)\\}" options:( AGRegexCaseInsensitive | AGRegexDotAll )];

			NSMutableArray *styleLayout = [NSMutableArray array];
			[styleLayouts addObject:styleLayout];

			// Step through the selectors.
			for( AGRegexMatch *selector in [regex findAllInString:style] ) {
				// Parse all the properties for the selector.
				regex = [AGRegex regexWithPattern:@"(\\S*?):\\s*(.*?);" options:( AGRegexCaseInsensitive | AGRegexDotAll )];

				// Step through all the properties and build a dictionary on this selector/property/value combo.
				for( AGRegexMatch *property in [regex findAllInString:[selector groupAtIndex:2]] ) {
					NSMutableDictionary *propertyInfo = [NSMutableDictionary dictionary];
					NSString *p = [property groupAtIndex:1];
					NSString *s = [selector groupAtIndex:1];
					NSString *v = [property groupAtIndex:2];

					[propertyInfo setObject:s forKey:@"selector"];
					[propertyInfo setObject:p forKey:@"property"];
					[propertyInfo setObject:v forKey:@"value"];
					[styleLayout addObject:propertyInfo];

					// Get the current value of this selector/property from the Variant CSS and the Main CSS to compare.
					NSString *value = [self valueOfProperty:p forSelector:s inStyle:css];
					if( [[info objectForKey:@"type"] isEqualToString:@"list"] ) {
						// Strip the "!important" flag to compare correctly.
						regex = [AGRegex regexWithPattern:@"\\s*!\\s*important\\s*$" options:AGRegexCaseInsensitive];
						NSString *compare = [regex replaceWithString:@"" inString:v];

						// Try to pick which option the list needs to select.
						if( ! [value isEqualToString:compare] ) { // Didn't match.
							NSNumber *value = [info objectForKey:@"value"];
							if( [value unsignedLongValue] == count ) [info removeObjectForKey:@"value"];
						} else [info setObject:[NSNumber numberWithUnsignedLong:count] forKey:@"value"]; // Matched for now.
					} else if( [[info objectForKey:@"type"] isEqualToString:@"color"] ) {
						if( value && [v rangeOfString:@"%@"].location != NSNotFound ) {
							// Strip the "!important" flag to compare correctly.
							regex = [AGRegex regexWithPattern:@"\\s*!\\s*important\\s*$" options:AGRegexCaseInsensitive];

							// Replace %@ with (.*) so we can pull the color value out.
							NSString *expression = [regex replaceWithString:@"" inString:v];
							expression = [expression stringByEscapingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"^[]{}()\\.$*+?|"]];
							expression = [NSString stringWithFormat:expression, @"(.*)"];

							// Store the color value if we found one.
							regex = [AGRegex regexWithPattern:expression options:AGRegexCaseInsensitive];
							AGRegexMatch *vmatch = [regex findInString:value];
							if( [vmatch count] ) [info setObject:[vmatch groupAtIndex:1] forKey:@"value"];
						}
					} else if( [[info objectForKey:@"type"] isEqualToString:@"file"] ) {
						if( value && [v rangeOfString:@"%@"].location != NSNotFound ) {
							// Strip the "!important" flag to compare correctly.
							regex = [AGRegex regexWithPattern:@"\\s*!\\s*important\\s*$" options:AGRegexCaseInsensitive];

							[info setObject:[NSNumber numberWithUnsignedLong:0] forKey:@"value"];
							[info setObject:[NSNumber numberWithUnsignedLong:0] forKey:@"default"];

							// Replace %@ with (.*) so we can pull the path value out.
							NSString *expression = [regex replaceWithString:@"" inString:v];
							expression = [expression stringByEscapingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"^[]{}()\\.$*+?|"]];
							expression = [NSString stringWithFormat:expression, @"(.*)"];

							// Store the path value if we found one.
							regex = [AGRegex regexWithPattern:expression options:AGRegexCaseInsensitive];
							AGRegexMatch *vmatch = [regex findInString:value];
							if( [vmatch count] ) {
								if( ! [[vmatch groupAtIndex:1] isEqualToString:@"none"] )
									[info setObject:[vmatch groupAtIndex:1] forKey:@"path"];
								else [info removeObjectForKey:@"path"];
								if( [info objectForKey:@"cell"] )
									[self buildFileMenuForCell:[info objectForKey:@"cell"] andOptions:info];
							}
						}
					}
				}
			}

			count++;
		}

		[info setObject:styleLayouts forKey:@"layouts"];
	}

	[optionsTable reloadData];
}

// reads a value form a CSS file for the property and selector provided.
- (NSString *) valueOfProperty:(NSString *) property forSelector:(NSString *) selector inStyle:(NSString *) style {
	NSCharacterSet *escapeSet = [NSCharacterSet characterSetWithCharactersInString:@"^[]{}()\\.$*+?|"];
	selector = [selector stringByEscapingCharactersInSet:escapeSet];
	property = [property stringByEscapingCharactersInSet:escapeSet];

	AGRegex *regex = [AGRegex regexWithPattern:[NSString stringWithFormat:@"%@\\s*\\{[^\\}]*?\\s%@:\\s*(.*?)(?:\\s*!\\s*important\\s*)?;.*?\\}", selector, property] options:( AGRegexCaseInsensitive | AGRegexDotAll )];
	AGRegexMatch *match = [regex findInString:style];
	if( [match count] > 1 ) return [match groupAtIndex:1];

	return nil;
}

// Saves a CSS value to the specified property and selector, creating it if one isn't already in the file.
- (void) setStyleProperty:(NSString *) property forSelector:(NSString *) selector toValue:(NSString *) value {
	NSCharacterSet *escapeSet = [NSCharacterSet characterSetWithCharactersInString:@"^[]{}()\\.$*+?|"];
	NSString *rselector = [selector stringByEscapingCharactersInSet:escapeSet];
	NSString *rproperty = [property stringByEscapingCharactersInSet:escapeSet];

	AGRegex *regex = [AGRegex regexWithPattern:[NSString stringWithFormat:@"(%@\\s*\\{[^\\}]*?\\s%@:\\s*)(?:.*?)(;.*?\\})", rselector, rproperty] options:( AGRegexCaseInsensitive | AGRegexDotAll )];
	if( [[regex findInString:_userStyle] count] ) { // Change existing property in selector block
		[self setUserStyle:[regex replaceWithString:[NSString stringWithFormat:@"$1%@$2", value] inString:_userStyle]];
	} else {
		regex = [AGRegex regexWithPattern:[NSString stringWithFormat:@"(\\s%@\\s*\\{)(\\s*)", rselector] options:AGRegexCaseInsensitive];
		if( [[regex findInString:_userStyle] count] ) { // Append to existing selector block
			[self setUserStyle:[regex replaceWithString:[NSString stringWithFormat:@"$1$2%@: %@;$2", rproperty, value] inString:_userStyle]];
		} else { // Create new selector block
			[self setUserStyle:[_userStyle stringByAppendingFormat:@"%@%@ {\n\t%@: %@;\n}", ( [_userStyle length] ? @"\n\n": @"" ), selector, property, value]];
		}
	}
}

- (void) setUserStyle:(NSString *) style {
	if( ! style ) _userStyle = [NSString string];
	else _userStyle = style;
}

// Saves the custom variant to the user's area.
- (void) saveStyleOptions {
	if( _variantLocked ) return;

	[_userStyle writeToURL:[_style variantStyleSheetLocationWithName:[_style defaultVariantName]] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[_style defaultVariantName], @"variant", nil];
	NSNotification *notification = [NSNotification notificationWithName:JVStyleVariantChangedNotification object:_style userInfo:info];
	[[NSNotificationQueue defaultQueue] enqueueNotification:notification postingStyle:NSPostASAP coalesceMask:( NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender ) forModes:nil];
}

// Shows the drawer, option clicking the button will open the custom variant CSS file.
- (IBAction) showOptions:(id) sender {
	if( ! _variantLocked && [[[NSApplication sharedApplication] currentEvent] modifierFlags] & NSAlternateKeyMask ) {
		[[NSWorkspace sharedWorkspace] openURL:[_style variantStyleSheetLocationWithName:[_style defaultVariantName]]];
		return;
	}

	if( _variantLocked && [optionsDrawer state] == NSDrawerClosedState )
		[self showNewVariantSheet];

	[optionsDrawer setParentWindow:[sender window]];
	[optionsDrawer setPreferredEdge:NSMaxXEdge];
	if( [optionsDrawer contentSize].width < [optionsDrawer minContentSize].width )
		[optionsDrawer setContentSize:[optionsDrawer minContentSize]];
	[optionsDrawer toggle:sender];
}

#pragma mark -

- (NSInteger) numberOfRowsInTableView:(NSTableView *) view {
	return [_styleOptions count];
}

- (id) tableView:(NSTableView *) view objectValueForTableColumn:(NSTableColumn *) column row:(NSInteger) row {
	if( [[column identifier] isEqualToString:@"key"] ) {
		return NSLocalizedString( [[_styleOptions objectAtIndex:row] objectForKey:@"description"], "description of style options, appearance preferences" );
	} else if( [[column identifier] isEqualToString:@"value"] ) {
		NSDictionary *info = [_styleOptions objectAtIndex:row];
		id value = [info objectForKey:@"value"];
		if( value ) return value;
		return [info objectForKey:@"default"];
	}
	return nil;
}

- (void) tableView:(NSTableView *) view setObjectValue:(id) object forTableColumn:(NSTableColumn *) column row:(NSInteger) row {
	if( _variantLocked ) return;

	if( [[column identifier] isEqualToString:@"value"] ) {
		NSMutableDictionary *info = [_styleOptions objectAtIndex:row];
		if( [[info objectForKey:@"type"] isEqualToString:@"list"] ) {
			[info setObject:object forKey:@"value"];

			for( NSDictionary *styleInfo in [[info objectForKey:@"layouts"] objectAtIndex:[object intValue]] )
				[self setStyleProperty:[styleInfo objectForKey:@"property"] forSelector:[styleInfo objectForKey:@"selector"] toValue:[styleInfo objectForKey:@"value"]];

			[self saveStyleOptions];
		} else if( [[info objectForKey:@"type"] isEqualToString:@"file"] ) {
			if( [object intValue] == -1 ) return;

			NSString *path = [[(NSPopUpButtonCell *)[info objectForKey:@"cell"] itemAtIndex:[object intValue]] representedObject];
			if( ! path ) return;

			[info setObject:object forKey:@"value"];

			for( NSDictionary *styleInfo in [[info objectForKey:@"layouts"] objectAtIndex:0] ) {
				NSString *setting = [NSString stringWithFormat:[styleInfo objectForKey:@"value"], path];
				[self setStyleProperty:[styleInfo objectForKey:@"property"] forSelector:[styleInfo objectForKey:@"selector"] toValue:setting];
			}

			[self saveStyleOptions];
		} else return;
	}
}

// Called when JVColorWell's color changes.
- (void) colorWellDidChangeColor:(NSNotification *) notification {
	if( _variantLocked ) return;

	JVColorWellCell *cell = [notification object];
	if( ! [[cell representedObject] isKindOfClass:[NSNumber class]] ) return;
	NSInteger row = [[cell representedObject] intValue];

	NSMutableDictionary *info = [_styleOptions objectAtIndex:row];
	[info setObject:[cell color] forKey:@"value"];

	NSArray *style = [[info objectForKey:@"layouts"] objectAtIndex:0];
	NSString *value = [[cell color] CSSAttributeValue];
	NSString *setting = nil;

	for( NSDictionary *styleInfo in style ) {
		setting = [NSString stringWithFormat:[styleInfo objectForKey:@"value"], value];
		[self setStyleProperty:[styleInfo objectForKey:@"property"] forSelector:[styleInfo objectForKey:@"selector"] toValue:setting];
	}

	[self saveStyleOptions];
}

- (IBAction) selectImageFile:(id) sender {
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	NSInteger index = [optionsTable selectedRow];
	NSMutableDictionary *info = [_styleOptions objectAtIndex:index];

	[openPanel setAllowsMultipleSelection:NO];
	[openPanel setTreatsFilePackagesAsDirectories:NO];
	[openPanel setCanChooseDirectories:NO];

	NSArray *types = [NSArray arrayWithObjects:@"jpg", @"tif", @"tiff", @"jpeg", @"gif", @"png", @"pdf", nil];
	NSString *value = [sender representedObject];

	[openPanel setDirectoryURL:[NSURL fileURLWithPath:value isDirectory:NO]];
	[openPanel setAllowedFileTypes:types];

	if( [openPanel runModal] != NSOKButton )
		return;

	value = [[openPanel URL] path];
	[info setObject:value forKey:@"path"];

	NSArray *style = [[info objectForKey:@"layouts"] objectAtIndex:0];

	for( NSDictionary *styleInfo in style ) {
		NSString *setting = [NSString stringWithFormat:[styleInfo objectForKey:@"value"], value];
		[self setStyleProperty:[styleInfo objectForKey:@"property"] forSelector:[styleInfo objectForKey:@"selector"] toValue:setting];
	}

	[self saveStyleOptions];

	NSMutableDictionary *options = [_styleOptions objectAtIndex:index];
	[self buildFileMenuForCell:[options objectForKey:@"cell"] andOptions:options];
}

- (BOOL) tableView:(NSTableView *) view shouldSelectRow:(NSInteger) row {
	static NSTimeInterval lastTime = 0;
	if( _variantLocked && ( [NSDate timeIntervalSinceReferenceDate] - lastTime ) > 1. ) {
		[self showNewVariantSheet];
	}

	lastTime = [NSDate timeIntervalSinceReferenceDate];
	return ( ! _variantLocked );
}

- (id) tableView:(NSTableView *) view dataCellForRow:(NSInteger) row tableColumn:(NSTableColumn *) column {
	if( [[column identifier] isEqualToString:@"value"] ) {
		NSMutableDictionary *options = [_styleOptions objectAtIndex:row];
		if( [options objectForKey:@"cell"] ) {
			return [options objectForKey:@"cell"];
		} else if( [[options objectForKey:@"type"] isEqualToString:@"color"] ) {
			id cell = [JVColorWellCell new];
			[cell setRepresentedObject:[NSNumber numberWithLong:row]];
			[options setObject:cell forKey:@"cell"];
			return cell;
		} else if( [[options objectForKey:@"type"] isEqualToString:@"list"] ) {
			NSPopUpButtonCell *cell = [NSPopUpButtonCell new];
			NSMutableArray *localizedOptions = [NSMutableArray array];

			for( NSString *optionTitle in [options objectForKey:@"options"] )
				[localizedOptions addObject:NSLocalizedString( optionTitle, "title of style option value" )];
			[cell setControlSize:NSSmallControlSize];
			[cell setFont:[NSFont menuFontOfSize:[NSFont smallSystemFontSize]]];
			[cell addItemsWithTitles:localizedOptions];
			[options setObject:cell forKey:@"cell"];
			return cell;
        } else if( [[options objectForKey:@"type"] isEqualToString:@"file"] ) {
			NSPopUpButtonCell *cell = [NSPopUpButtonCell new];
			[cell setControlSize:NSSmallControlSize];
			[cell setFont:[NSFont menuFontOfSize:[NSFont smallSystemFontSize]]];
			[self buildFileMenuForCell:cell andOptions:options];
			[options setObject:cell forKey:@"cell"];
			return cell;
		}
	}

	return nil;
}

#pragma mark -

// Shows the new variant sheet asking for a name.
- (void) showNewVariantSheet {
	[newVariantName setStringValue:NSLocalizedString( @"Untitled Variant", "new variant name" )];
	[[NSApplication sharedApplication] beginSheet:newVariantPanel modalForWindow:[preview window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}

- (IBAction) closeNewVariantSheet:(id) sender {
	[newVariantPanel orderOut:nil];
	[[NSApplication sharedApplication] endSheet:newVariantPanel];
}

// Creates the new variant, making the proper folder and copying the current CSS settings.
- (IBAction) createNewVariant:(id) sender {
	[self closeNewVariantSheet:sender];

	NSMutableString *name = [[newVariantName stringValue] mutableCopy];
	[name replaceOccurrencesOfString:@"/" withString:@"-" options:NSLiteralSearch range:NSMakeRange( 0, [name length] )];
	[name replaceOccurrencesOfString:@":" withString:@"-" options:NSLiteralSearch range:NSMakeRange( 0, [name length] )];

	[[NSFileManager defaultManager] createDirectoryAtPath:[[NSString stringWithFormat:@"~/Library/Application Support/Colloquy/Styles/Variants/%@/", [_style identifier]] stringByExpandingTildeInPath] withIntermediateDirectories:YES attributes:nil error:nil];

	NSString *path = [[NSString stringWithFormat:@"~/Library/Application Support/Colloquy/Styles/Variants/%@/%@.css", [_style identifier], name] stringByExpandingTildeInPath];

	[_userStyle writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

	[_style setDefaultVariantName:name];

	[[NSNotificationCenter defaultCenter] postNotificationName:JVNewStyleVariantAddedNotification object:_style];

	[self updateChatStylesMenu];
	[self updateVariant];
}
@end
