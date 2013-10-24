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


#define RSSwizzleFactory id (RSSWizzleIMPProvider original, __unsafe_unretained Class hookedClass, SEL selector)


#define RSOriginalCast(type, original) ((__typeof(type (*)(__unsafe_unretained id, SEL, ...)))original()) //use for non objc types
#define RSOriginalVoid(original) RSOriginalCast(void, original) //use for void
#define RSOriginal(original) original() //use for id


/**
 A block returning a function pointer to the original implementation of the swizzled method.
 */

typedef IMP (^RSSWizzleIMPProvider)(void);

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

typedef id (^RSSwizzleFactoryBlock)(RSSWizzleIMPProvider original, __unsafe_unretained Class swizzledClass, SEL selector);


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


//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//@ Class method swizzling @
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@



/**
 Swizzles the class method of the class with the new implementation.
 
 Original implementation must always be called from the new implementation. And because of the the fact that for safe and robust swizzling original implementation must be dynamically fetched at the time of calling and not at the time of swizzling, swizzling API is a little bit complicated.
 
 You should pass a factory block that returns the block for the new implementation of the swizzled method. And use swizzleInfo argument to retrieve and call original implementation.
 
 Example for swizzling `+(int)[TestClass calculate:(int)];` method:
 
 @code
 
 [TestClass swizzleClassMethod:@selector(calculate:) usingFactory:^ RSSwizzleFactory {
    //The following block will be used as the new implementation.
    return ^ RSSwizzleReplacement(int, TestClass *, int number) {
        //You MUST always cast implementation to the correct function pointer.
        int orig = RSOriginalCast(int, original)(self, selector, number);
 
        //Returning modified return value.
        return orig+1;
    };
 }];
 
 @endcode
 
 Swizzling is fully thread-safe.
 
 @param selector Selector of the method that should be swizzled.
 
 @param factoryBlock The factory block returning the block for the new implementation of the swizzled method.
 
 */

+ (void)swizzleClassMethod:(SEL)selector usingFactory:(RSSwizzleFactoryBlock)factoryBlock;




/**
 Swizzles the class method of the class with the new implementation.
 
 Original implementation must always be called from the new implementation. And because of the the fact that for safe and robust swizzling original implementation must be dynamically fetched at the time of calling and not at the time of swizzling, swizzling API is a little bit complicated.
 
 You should pass a factory block that returns the block for the new implementation of the swizzled method. And use swizzleInfo argument to retrieve and call original implementation.
 
 Example for swizzling `+(int)[TestClass calculate:(int)];` method:
 
 @code
 
 [TestClass swizzleClassMethod:@selector(calculate:) usingFactory:^ RSSwizzleFactory {
    //The following block will be used as the new implementation.
    return ^ RSSwizzleReplacement(int, TestClass *, number) {
        //You MUST always cast implementation to the correct function pointer.
        int orig = RSOriginalCast(int, original)(self, selector, number);
 
        //Returning modified return value.
        return orig+1;
    };
 }];
 
 @endcode
 
 Swizzling is fully thread-safe.
 
 @param selector Selector of the method that should be swizzled.
 
 @param factoryBlock The factory block returning the block for the new implementation of the swizzled method.
 
 @param mode The mode is used in combination with the key to indicate whether the swizzling should be done for the given class.
 
 @param key The key is used in combination with the mode to indicate whether the swizzling should be done for the given class. May be NULL if the mode is RSSwizzleModeAlways.
 
 @return YES if successfully swizzled and NO if swizzling has been already done for given key and class (or one of superclasses, depends on the mode).
 */

+ (BOOL)swizzleClassMethod:(SEL)selector usingFactory:(RSSwizzleFactoryBlock)factoryBlock mode:(RSSwizzleMode)mode key:(const void *)key;











//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//@ Instance method swizzling @
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@



/**
 Swizzles the instance method of the class with the new implementation.
 
 Original implementation must always be called from the new implementation. And because of the the fact that for safe and robust swizzling original implementation must be dynamically fetched at the time of calling and not at the time of swizzling, swizzling API is a little bit complicated.
 
 You should pass a factory block that returns the block for the new implementation of the swizzled method. And use swizzleInfo argument to retrieve and call original implementation.
 
 Example for swizzling `-(int)[TestClass calculate:(int)];` method:
 
 @code
 
 [TestClass swizzleInstanceMethod:@selector(calculate:) usingFactory:^ RSSwizzleFactory {
    //The following block will be used as the new implementation.
    return ^ RSSwizzleReplacement(int, TestClass *, int number) {
        //You MUST always cast implementation to the correct function pointer.
        int orig = RSOriginalCast(int, original)(self, selector, number);
 
        //Returning modified return value.
        return orig+1;
    };
 }];
 
 @endcode
 
 Swizzling is fully thread-safe.
 
 @param selector Selector of the method that should be swizzled.
 
 @param factoryBlock The factory block returning the block for the new implementation of the swizzled method.
 */

+ (void)swizzleInstanceMethod:(SEL)selector usingFactory:(RSSwizzleFactoryBlock)factoryBlock;



/**
 Swizzles the instance method of the class with the new implementation.
 
 Original implementation must always be called from the new implementation. And because of the the fact that for safe and robust swizzling original implementation must be dynamically fetched at the time of calling and not at the time of swizzling, swizzling API is a little bit complicated.
 
 You should pass a factory block that returns the block for the new implementation of the swizzled method. And use swizzleInfo argument to retrieve and call original implementation.
 
 Example for swizzling `-(int)[TestClass calculate:(int)];` method:
 
 @code
 
 [TestClass swizzleInstanceMethod:@selector(calculate:) usingFactory:^ RSSwizzleFactory {
    //The following block will be used as the new implementation.
    return ^ RSSwizzleReplacement(int, TestClass *, int number) {
        //You MUST always cast implementation to the correct function pointer.
        int orig = RSOriginalCast(int, original)(self, selector, number);
 
        //Returning modified return value.
        return orig+1;
    };
 }];
 
 @endcode
 
 Most of the time swizzling goes along with checking whether this particular class (or one of its superclasses) has been already swizzled. Here the `mode` and `key` parameters can help.
 
 Here is an example of swizzling `-(void)dealloc;` only in case when neither class and no one of its superclasses has been already swizzled with our key. However "Deallocating ..." message still may be logged multiple times per method call if swizzling was called primarily for an inherited class and later for one of its superclasses.
 
 @code
 
 static const void *key = &key;
 
 [TestClass swizzleInstanceMethod:@selector(calculate:) usingFactory:^ RSSwizzleFactory {
    return ^ RSSwizzleReplacement(int, TestClass *) {
        NSLog(@"Deallocating %@.",self);
        RSOriginalVoid(original)(self, selector);
    };
 } mode:RSSwizzleModeOncePerClassAndSuperclasses key:key];
 
 @endcode
 
 Swizzling is fully thread-safe.
 
 @param selector Selector of the method that should be swizzled.
 
 @param factoryBlock The factory block returning the block for the new implementation of the swizzled method.
 
 @param mode The mode is used in combination with the key to indicate whether the swizzling should be done for the given class.
 
 @param key The key is used in combination with the mode to indicate whether the swizzling should be done for the given class. May be NULL if the mode is RSSwizzleModeAlways.
 
 @return YES if successfully swizzled and NO if swizzling has been already done for given key and class (or one of superclasses, depends on the mode).
 */

+ (BOOL)swizzleInstanceMethod:(SEL)selector usingFactory:(RSSwizzleFactoryBlock)factoryBlock mode:(RSSwizzleMode)mode key:(const void *)key;


@end




