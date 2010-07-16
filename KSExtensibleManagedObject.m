//
//  KSExtensibleManagedObject.m
//
//  Created by Mike Abdullah on 25/08/2007.
//  Copyright 2007-2010 Karelia Software. All rights reserved.
//
//  THIS SOFTWARE IS PROVIDED BY KARELIA SOFTWARE AND ITS CONTRIBUTORS "AS-IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUR OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//
//	A special kind of managed object that allows you to use -valueForKey: and
//	-setValueForKey: using any key. If the object does not normally accept this
//	key, it is stored internally in a dictionary and then archived as data.


#import "KSExtensibleManagedObject.h"
#import "Debug.h" // for assertions

@interface KSExtensibleManagedObject (Private)

- (NSMutableDictionary *)_extensibleProperties;
+ (NSSet *)modifiedKeysBetweenDictionary:(NSDictionary *)dict1 andDictionary:(NSDictionary *)dict2;
- (NSDictionary *)archivedExtensibleProperties;

@end


#pragma mark -


@implementation KSExtensibleManagedObject

#pragma mark Class Methods

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return NO; }

#pragma mark Extensible Properties

- (id)extensiblePropertyForKey:(NSString *)key;
{
    return [[self _extensibleProperties] valueForKey:key];
}

- (NSDictionary *)extensibleProperties
{
	NSDictionary *result = [[[self _extensibleProperties] copy] autorelease];
	return result;
}

- (void)setExtensibleProperty:(id)value forKey:(NSString *)key;
{
    [[self _extensibleProperties] setObject:value forKey:key];
    
    // Archive the new properties. This has to be done every time so Core Data knows
    // that some kind of change was made.
    [self setValue:[self archiveExtensibleProperties:[self _extensibleProperties]]
            forKey:[[self class] extensiblePropertiesDataKey]];
}

- (void)removeExtensiblePropertyForKey:(NSString *)key;
{
    [[self _extensibleProperties] removeObjectForKey:key];
    
    // Archive the new properties. This has to be done every time so Core Data knows
    // that some kind of change was made.
    [self setValue:[self archiveExtensibleProperties:[self _extensibleProperties]]
            forKey:[[self class] extensiblePropertiesDataKey]];
}

- (void)awakeFromExtensiblePropertyUndoUpdateForKey:(NSString *)key; { }

- (NSMutableDictionary *)_extensibleProperties;
{
	// Fault in the properties on-demand
	if (!_extensibleProperties)
	{
		_extensibleProperties = [[self archivedExtensibleProperties] mutableCopy];
		
		if (!_extensibleProperties)
		{
			_extensibleProperties = [[NSMutableDictionary alloc] init];
		}
	}
	
	return _extensibleProperties;
}

#pragma mark Extensible Property Storage

/*	Fetches all custom values from the persistent store rather than the in-memory representation.
 */
- (NSDictionary *)archivedExtensibleProperties
{
	NSDictionary *result = nil;
	
	NSString *key = [[self class] extensiblePropertiesDataKey];
	if (key)
	{
		NSData *data = [self valueForKey:key];
		result = [self unarchiveExtensibleProperties:data];
	}
	
	return result;
}

- (NSDictionary *)unarchiveExtensibleProperties:(NSData *)propertiesData
{
	NSMutableDictionary *result = nil;
	
	if (propertiesData)
	{
		id unarchivedDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:propertiesData];
		if ([unarchivedDictionary isKindOfClass:[NSMutableDictionary class]])
		{
			result = unarchivedDictionary;
		}
	}
	
	return result;
}

- (NSData *)archiveExtensibleProperties:(NSDictionary *)properties;
{
	NSData *result = [NSKeyedArchiver archivedDataWithRootObject:properties];
	return result;
}

+ (NSString *)extensiblePropertiesDataKey
{
	return @"extensiblePropertiesData";
}

+ (NSSet *)modifiedKeysBetweenDictionary:(NSDictionary *)dict1 andDictionary:(NSDictionary *)dict2
{
	// It's easy if either dictionary is nil
	if (!dict1) return [NSSet setWithArray:[dict2 allKeys]];
	if (!dict2) return [NSSet setWithArray:[dict1 allKeys]];
	
	
	// Build the set containing all the keys that exist in either dictionary
	NSMutableSet *allKeys = [[NSMutableSet alloc] initWithArray:[dict1 allKeys]];
	[allKeys addObjectsFromArray:[dict2 allKeys]];
	
	
	// Then run through these building a list of keys which the two dictionaries have different values for
	NSString *aKey;
	NSMutableSet *result = [NSMutableSet set];
	
	for (aKey in allKeys)
	{
		if (![[dict1 valueForKey:aKey] isEqual:[dict2 valueForKey:aKey]])
        {
			OBASSERT(aKey);
            [result addObject:aKey];
		}
	}
	
	// Tidy up
	[allKeys release];
	
	return result;
}

#pragma mark KVC Integration

- (BOOL)usesExtensiblePropertiesForUndefinedKey:(NSString *)key; { return NO; }

/*	We catch all undefined keys and pull them from the extensible properties dictionary.
 */
- (id)valueForUndefinedKey:(NSString *)key
{
	if ([self usesExtensiblePropertiesForUndefinedKey:key])
    {
        id result = [self extensiblePropertyForKey:key];
        return result;
    }
    else
    {
        return [super valueForUndefinedKey:key];
    }
}

/*	Undefined keys are caught and A) stored in-memory B) archived persistently
 */
- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
	OBPRECONDITION(key);
    
    if ([self usesExtensiblePropertiesForUndefinedKey:key])
    {
        [self willChangeValueForKey:key];
        if (value)
        {
            [self setExtensibleProperty:value forKey:key];
        }
        else
        {
            [self removeExtensiblePropertyForKey:key];
        }
        [self didChangeValueForKey:key];
    }
    else
    {
        return [super setValue:value forUndefinedKey:key];
    }
}

/*	Whenever a change to our dictionary data is made due to an undo or redo, match the changes to
 *	our in-memory dictionary
 */
- (void)didChangeValueForKey:(NSString *)key
{
	if ([key isEqualToString:[[self class] extensiblePropertiesDataKey]])
	{
		NSUndoManager *undoManager = [[self managedObjectContext] undoManager];
		if ([undoManager isUndoing] || [undoManager isRedoing])
		{
			// Comparison of the old and new dictionaries in order to to send out approrpriate KVO notifications
			// We specifically access the ivar directly to avoid faulting it in.
			NSDictionary *replacementDictionary = [self archivedExtensibleProperties];
			NSSet *modifiedKeys =
            [KSExtensibleManagedObject modifiedKeysBetweenDictionary:_extensibleProperties
                                                       andDictionary:replacementDictionary];
			
			
			// Change each of the modified keys in our in-memory dictionary
			NSString *aKey;
			for (aKey in modifiedKeys)
			{
				BOOL fireKVONotificiations = [self usesExtensiblePropertiesForUndefinedKey:aKey];
                
                if (fireKVONotificiations) [self willChangeValueForKey:aKey];
				[[self _extensibleProperties] setValue:[replacementDictionary valueForKey:aKey]
                                                forKey:aKey];
                [self awakeFromExtensiblePropertyUndoUpdateForKey:aKey];
				if (fireKVONotificiations) [self didChangeValueForKey:aKey];
			}
		}
	}
	
	
	// Finally go ahead and do the default behavior. This is required to balance the
	// earlier -willChangeValueForKey: that must have ocurred.
	[super didChangeValueForKey:key];
}

#pragma mark Core Data Integration

/*	Throw away our internal dictionary just like normal Core Data faulting behavior.
 */
- (void)didTurnIntoFault
{
	[_extensibleProperties release];	_extensibleProperties = nil;
	[super didTurnIntoFault];
}

/*	Extend the default behaviour of these 2 methods to take into account extensible properties
 */
- (NSDictionary *)committedValuesForKeys:(NSArray *)keys includeExtensibleProperties:(BOOL)flag
{
	if (!flag) return [self committedValuesForKeys:keys];
	
	
	NSMutableDictionary *buffer = [NSMutableDictionary dictionary];
	
	
	// Pull out the committed values
	NSArray *committedStandardKeys = nil;
	if (keys) {
		committedStandardKeys = [keys arrayByAddingObject:[[self class] extensiblePropertiesDataKey]];
	}
	NSDictionary *committedStandardProperties = [self committedValuesForKeys:committedStandardKeys];
	
	
	// Add required extensible keys to the buffer
	NSData *extensiblePropertiesData = [committedStandardProperties valueForKey:[[self class] extensiblePropertiesDataKey]];
	if (extensiblePropertiesData && (id)extensiblePropertiesData != [NSNull null])
	{
		NSDictionary *extensibleProperties = [self unarchiveExtensibleProperties:extensiblePropertiesData];
		
		NSDictionary *requestedExtensibleProperties = extensibleProperties;
		if (keys)
		{
			requestedExtensibleProperties = [extensibleProperties dictionaryWithValuesForKeys:keys];
		}
		
		[buffer addEntriesFromDictionary:requestedExtensibleProperties];
	}
	
	
	// Add in the standard properties
	[buffer addEntriesFromDictionary:committedStandardProperties];
	
	
	// Unless specifically requested, leave out the extensible properties data
	if (!keys || ![keys containsObject:[[self class] extensiblePropertiesDataKey]])
	{
		[buffer removeObjectForKey:[[self class] extensiblePropertiesDataKey]];
	}
	
	
	// Tidy up
	NSDictionary *result = [[buffer copy] autorelease];
	return result;
}

- (NSDictionary *)changedValuesIncludingExtensibleProperties:(BOOL)flag
{
	NSMutableDictionary *result = [[[self changedValues] mutableCopy] autorelease];
	
	
	// If interested in extensible properties, replace the archived data with unarchived version
	if (flag && [result objectForKey:[[self class] extensiblePropertiesDataKey]])
	{
		[result removeObjectForKey:[[self class] extensiblePropertiesDataKey]];
		[result addEntriesFromDictionary:[self extensibleProperties]];
	}
	
	
	return result;
}

@end
