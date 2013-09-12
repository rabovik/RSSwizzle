//
//  RSSwizzle.h
//  RSSwizzleTests
//
//  Created by Yan Rabovik on 05.09.13.
//
//

#import <Foundation/Foundation.h>

/**
 A function pointer to the original implementation of the swizzled method.
 */
typedef void (*RSSwizzleOriginalIMP)(void /* id, SEL, ... */ );

/**
 RSSwizzleInfo is used in the new implementation block to get and call original implementation of the swizzled method.
 */
@interface RSSwizzleInfo : NSObject

/**
 Returns the original implementation of the swizzled method.

 It is actually either an original implementation if the swizzled class implements the method itself; or a super implementation fetched from one of the superclasses.
 
 @note You must always cast returned implementation to the appropriate function pointer when calling.
 
 @return A function pointer to the original implementation of the swizzled method.
 */
-(RSSwizzleOriginalIMP)getOriginalImplementation;

@end

/**
 A factory block returning the block for the new implementation of the swizzled method.

 You must always obtain original implementation with swizzleInfo and call it from the new implementation.
 
 @param swizzleInfo An info used to get and call the original implementation of the swizzled method.

 @return A block that implements a method.
    Its signature should be: `method_return_type ^(id self, method_args...)`. 
    The selector is not available as a parameter to this block.
 */
typedef id (^RSSwizzleImpFactoryBlock)(RSSwizzleInfo *swizzleInfo);

typedef NS_ENUM(NSUInteger, RSSwizzleMode) {
    /// RSSwizzle always does swizzling.
    RSSwizzleModeAlways = 0,
    /// RSSwizzle does not do swizzling if the same class has been swizzled earlier with the same key.
    RSSwizzleModeOncePerClass = 1,
    /// RSSwizzle does not do swizzling if the same class or one of its superclasses have been swizzled earlier with the same key.
    /// @note There is no guarantee that your implementation will be called only once per method call. If the order of swizzling is: first inherited class, second superclass, then both swizzlings will be done and the new implementation will be called twice.
    RSSwizzleModeOncePerClassAndSuperclasses = 2
};

@interface RSSwizzle : NSObject


/**
 Swizzles the method of the class with the new implementation.

 Original implementation must always be called from the new implementation. And because of the the fact that for safe and robust swizzling original implementation must be dynamically fetched at the time of calling and not at the time of swizzling, swizzling API is a little bit complicated.

 You should pass a factory block that returns the block for the new implementation of the swizzled method. And use swizzleInfo (factory block's single argument) to retrieve and call original implementation.

 Example for swizzling `-(int)calculate:(int)number;` method:
 
 @code

    SEL selector = @selector(calculate:);
    [RSSwizzle
     swizzleInstanceMethod:selector
     inClass:classToSwizzle
     newImpFactory:^id(RSSWizzleInfo *swizzleInfo) {
         // This block will be used as the new implementation.
         return ^int(__unsafe_unretained id self, int num){
             // You MUST always cast IMP to the correct function pointer.
             int (*originalIMP)(__unsafe_unretained id, SEL, int);
             originalIMP = (__typeof(originalIMP))[swizzleInfo getOriginalImplementation];
             // Calling original implementation.
             int res = originalIMP(self,selector,num);
             // Returning modified return value.
             return res + 1;
         };
     }
     mode:RSSwizzleModeAlways
     key:NULL];
 
 @endcode

 Most of the time swizzling goes along with checking whether this particular class (or one of its superclasses) has been already swizzled. Here the `mode` and `key` parameters can help.

 Here is an example of swizzling `-(void)dealloc;` only in case when neither class and no one of its superclasses has been already swizzled with our key. However "Deallocating ..." message still may be logged multiple times per method call if swizzling was called primarily for an inherited class and later for one of its superclasses.
 
 @code
 
    static const void *key = &key;
    SEL selector = NSSelectorFromString(@"dealloc");
    [RSSwizzle
     swizzleInstanceMethod:selector
     inClass:classToSwizzle
     newImpFactory:^id(RSSWizzleInfo *swizzleInfo) {
         return ^void(__unsafe_unretained id self){
             NSLog(@"Deallocating %@.",self);
             
             void (*originalIMP)(__unsafe_unretained id, SEL);
             originalIMP = (__typeof(originalIMP))[swizzleInfo getOriginalImplementation];
             originalIMP(self,selector);
         };
     }
     mode:RSSwizzleModeOncePerClassAndSuperclasses
     key:key];
 
 @endcode

 Swizzling is fully thread-safe.
 
 @param selector Selector of the method that should be swizzled.

 @param classToSwizzle The class with the method that should be swizzled.
 
 @param factoryBlock The factory block returning the block for the new implementation of the swizzled method.
 
 @param mode The mode is used in combination with the key to indicate whether the swizzling should be done for the given class.
 
 @param key The key is used in combination with the mode to indicate whether the swizzling should be done for the given class. May be NULL if the mode is RSSwizzleModeAlways.

 @return YES if successfully swizzled and NO if swizzling has been already done for given key and class (or one of superclasses, depends on the mode).
 */
+(BOOL)swizzleInstanceMethod:(SEL)selector
                     inClass:(Class)classToSwizzle
               newImpFactory:(RSSwizzleImpFactoryBlock)factoryBlock
                        mode:(RSSwizzleMode)mode
                         key:(const void *)key;

@end
