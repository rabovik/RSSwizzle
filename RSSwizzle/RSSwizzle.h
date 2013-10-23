//
//  RSSwizzle.h
//  RSSwizzleTests
//
//  Created by Yan Rabovik on 05.09.13.
//
//

#import <Foundation/Foundation.h>

/**
 Macros to make your life easier
 */

#define RSSwizzleReplacement(returntype, selftype, ...) returntype (__unsafe_unretained selftype self, ##__VA_ARGS__)
#define RSSwizzleFactory id (RSSWizzleImpProvider original, Class hookedClass, SEL selector)


#define RSOriginalCast(type, original) ((__typeof(type (*)(__unsafe_unretained id, SEL, ...)))original()) //use for non objc types
#define RSOriginalVoid(original) RSOriginalCast(void, original) //use for void
#define RSOriginal(original) original() //use for id


/**
 A function pointer to the original implementation of the swizzled method.
 */

typedef id (*RSSwizzleOriginalIMP)(id self, SEL _cmd, ...);

typedef IMP (^RSSWizzleImpProvider)(void);

/**
 A factory block returning the block for the new implementation of the swizzled method.
 
 You must always obtain original implementation with swizzleInfo and call it from the new implementation.
 
 @param original The original implementation of the swizzled method.
 
 @param swizzledClass The swizzled class.
 
 @param selector The swizzled selector.
 
 @return A block that implements a method.
 Its signature should be: `method_return_type ^(id self, method_args...)`.
 The selector is not available as a parameter to this block.
 */

typedef id (^RSSwizzleImpFactoryBlock)(RSSWizzleImpProvider original, Class swizzledClass, SEL selector);

typedef NS_ENUM(NSUInteger, RSSwizzleMode) {
    /// RSSwizzle always does swizzling.
    RSSwizzleModeAlways = 0,
    /// RSSwizzle does not do swizzling if the same class has been swizzled earlier with the same key.
    RSSwizzleModeOncePerClass = 1,
    /// RSSwizzle does not do swizzling if the same class or one of its superclasses have been swizzled earlier with the same key.
    /// @note There is no guarantee that your implementation will be called only once per method call. If the order of swizzling is: first inherited class, second superclass, then both swizzlings will be done and the new implementation will be called twice.
    RSSwizzleModeOncePerClassAndSuperclasses = 2
};


@interface NSObject (RSSwizzle)


//Class method swizzling
+ (BOOL)swizzleMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock;
+ (BOOL)swizzleMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock mode:(RSSwizzleMode)mode key:(const void *)key;



//Instance method swizzling
+ (BOOL)swizzleInstanceMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock;
+ (BOOL)swizzleInstanceMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock mode:(RSSwizzleMode)mode key:(const void *)key;


- (BOOL)swizzleMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock;
- (BOOL)swizzleMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock mode:(RSSwizzleMode)mode key:(const void *)key;


@end




