//
//  RSSwizzle.m
//  RSSwizzleTests
//
//  Created by Yan Rabovik on 05.09.13.
//
//

#import "RSSwizzle.h"
#import <objc/runtime.h>
#import <libkern/OSAtomic.h>

#if !__has_feature(objc_arc)
#error This code needs ARC. Use compiler option -fobjc-arc
#endif

#pragma mark - Block Helpers
#if !defined(NS_BLOCK_ASSERTIONS)

// See http://clang.llvm.org/docs/Block-ABI-Apple.html#high-level
struct Block_literal_1 {
    void *isa; // initialized to &_NSConcreteStackBlock or &_NSConcreteGlobalBlock
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct Block_descriptor_1 {
        unsigned long int reserved;         // NULL
        unsigned long int size;         // sizeof(struct Block_literal_1)
        // optional helper functions
        void (*copy_helper)(void *dst, void *src);     // IFF (1<<25)
        void (*dispose_helper)(void *src);             // IFF (1<<25)
        // required ABI.2010.3.16
        const char *signature;                         // IFF (1<<30)
    } *descriptor;
    // imported variables
};

enum {
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25),
    BLOCK_HAS_CTOR =          (1 << 26), // helpers have C++ code
    BLOCK_IS_GLOBAL =         (1 << 28),
    BLOCK_HAS_STRET =         (1 << 29), // IFF BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE =     (1 << 30),
};
typedef int BlockFlags;

static const char *blockGetType(id block) {
    struct Block_literal_1 *blockRef = (__bridge struct Block_literal_1 *)block;
    BlockFlags flags = blockRef->flags;
    
    if (flags & BLOCK_HAS_SIGNATURE) {
        void *signatureLocation = blockRef->descriptor;
        signatureLocation += sizeof(unsigned long int);
        signatureLocation += sizeof(unsigned long int);
        
        if (flags & BLOCK_HAS_COPY_DISPOSE) {
            signatureLocation += sizeof(void(*)(void *dst, void *src));
            signatureLocation += sizeof(void (*)(void *src));
        }
        
        const char *signature = (*(const char **)signatureLocation);
        return signature;
    }
    
    return NULL;
}

static BOOL blockIsCompatibleWithMethodType(id block, const char *methodType) {
    const char *blockType = blockGetType(block);
    
    NSMethodSignature *blockSignature = [NSMethodSignature signatureWithObjCTypes:blockType];
    NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:methodType];
    
    if (!blockSignature || !methodSignature) {
        return NO;
    }
    
    if (blockSignature.numberOfArguments != methodSignature.numberOfArguments) {
        return NO;
    }
    const char *blockReturnType = blockSignature.methodReturnType;
    
    if (strncmp(blockReturnType, "@", 1) == 0) {
        blockReturnType = "@";
    }
    
    if (strcmp(blockReturnType, methodSignature.methodReturnType) != 0) {
        return NO;
    }
    
    for (unsigned int i = 0; i < methodSignature.numberOfArguments; i++) {
        if (i == 0) {
            // self in method, block in block
            if (strcmp([methodSignature getArgumentTypeAtIndex:i], "@") != 0) {
                return NO;
            }
            if (strcmp([blockSignature getArgumentTypeAtIndex:i], "@?") != 0) {
                return NO;
            }
        }
        else if(i == 1) {
            // SEL in method, self in block
            if (strcmp([methodSignature getArgumentTypeAtIndex:i], ":") != 0) {
                return NO;
            }
            if (strncmp([blockSignature getArgumentTypeAtIndex:i], "@", 1) != 0) {
                return NO;
            }
        }
        else {
            const char *blockSignatureArg = [blockSignature getArgumentTypeAtIndex:i];
            
            if (strncmp(blockSignatureArg, "@", 1) == 0) {
                blockSignatureArg = "@";
            }
            
            if (strcmp(blockSignatureArg, [methodSignature getArgumentTypeAtIndex:i]) != 0) {
                return NO;
            }
        }
    }
    
    return YES;
}

static BOOL blockIsAnImpFactoryBlock(id block) {
    const char *blockType = blockGetType(block);
    RSSwizzleImpFactoryBlock dummyFactory = ^id(RSSWizzleImpProvider provider, Class class, SEL selector) {
        return nil;
    };
    const char *factoryType = blockGetType(dummyFactory);
    return (strcmp(factoryType, blockType) == 0);
}

#endif // NS_BLOCK_ASSERTIONS


#pragma mark - Swizzling

static void swizzleCore_Instance(Class classToSwizzle, SEL selector, RSSwizzleImpFactoryBlock factoryBlock) {
    Method method = class_getInstanceMethod(classToSwizzle, selector);
    
    NSCAssert(method != NULL, @"Selector %@ not found in instance methods of class %@.", NSStringFromSelector(selector), classToSwizzle);
    
    NSCAssert(blockIsAnImpFactoryBlock(factoryBlock), @"Wrong type of implementation factory block.");
    
    __block OSSpinLock lock = OS_SPINLOCK_INIT;
    // To keep things thread-safe, we fill in the originalIMP later,
    // with the result of the class_replaceMethod call below.
    __block IMP originalIMP = NULL;

    // This block will be called by the client to get original implementation and call it.
    RSSWizzleImpProvider originalImpProvider = ^IMP {
        // It's possible that another thread can call the method between the call to
        // class_replaceMethod and its return value being set.
        // So to be sure originalIMP has the right value, we need a lock.
        OSSpinLockLock(&lock);
        IMP imp = originalIMP;
        OSSpinLockUnlock(&lock);
        
        if (NULL == imp) {
            // If the class does not implement the method
            // we need to find an implementation in one of the superclasses.
            Class superclass = class_getSuperclass(classToSwizzle);
            imp = method_getImplementation(class_getInstanceMethod(superclass, selector));
        }
        return imp;
    };
    
    // We ask the client for the new implementation block.
    // We pass swizzleInfo as an argument to factory block, so the client can
    // call original implementation from the new implementation.
    id newIMPBlock = factoryBlock(originalImpProvider, classToSwizzle, selector);
    
    NSCAssert(newIMPBlock, @"Block returned from factory cannot be nil.");
    
    const char *methodType = method_getTypeEncoding(method);
    
    NSCAssert(blockIsCompatibleWithMethodType(newIMPBlock, methodType), @"Block returned from factory is not compatible with method type.");
    
    IMP newIMP = imp_implementationWithBlock(newIMPBlock);
    
    // Atomically replace the original method with our new implementation.
    // This will ensure that if someone else's code on another thread is messing
    // with the class' method list too, we always have a valid -dealloc at all times.
    //
    // If the class does not implement the method itself then
    // class_replaceMethod returns NULL and superclasses's implementation will be used.
    //
    // We need a lock to be sure that originalIMP has the right value in the
    // originalImpProvider block above.
    OSSpinLockLock(&lock);
    originalIMP = class_replaceMethod(classToSwizzle, selector, newIMP, methodType);
    OSSpinLockUnlock(&lock);
}


static void swizzleCore_Class(Class classToSwizzle, SEL selector, RSSwizzleImpFactoryBlock factoryBlock) {
    Method method = class_getClassMethod(classToSwizzle, selector);
    
    NSCAssert(method != NULL, @"Selector %@ not found in class methods of class %@.", NSStringFromSelector(selector), classToSwizzle);
    
    NSCAssert(blockIsAnImpFactoryBlock(factoryBlock), @"Wrong type of implementation factory block.");
    
    __block OSSpinLock lock = OS_SPINLOCK_INIT;
    // To keep things thread-safe, we fill in the originalIMP later,
    // with the result of the class_replaceMethod call below.
    __block IMP originalIMP = NULL;
    
    // This block will be called by the client to get original implementation and call it.
    RSSWizzleImpProvider originalImpProvider = ^IMP {
        // It's possible that another thread can call the method between the call to
        // class_replaceMethod and its return value being set.
        // So to be sure originalIMP has the right value, we need a lock.
        OSSpinLockLock(&lock);
        IMP imp = originalIMP;
        OSSpinLockUnlock(&lock);
        
        if (imp == NULL) {
            // If the class does not implement the method
            // we need to find an implementation in one of the superclasses.
            Class superclass = class_getSuperclass(classToSwizzle);
            imp = method_getImplementation(class_getClassMethod(superclass, selector));
        }
        
        return imp;
    };
    
    // We ask the client for the new implementation block.
    // We pass swizzleInfo as an argument to factory block, so the client can
    // call original implementation from the new implementation.
    id newIMPBlock = factoryBlock(originalImpProvider, classToSwizzle, selector);
    
    const char *methodType = method_getTypeEncoding(method);
    
    NSCAssert(blockIsCompatibleWithMethodType(newIMPBlock, methodType), @"Block returned from factory is not compatible with method type.");
    
    IMP newIMP = imp_implementationWithBlock(newIMPBlock);
    
    // Atomically replace the original method with our new implementation.
    // This will ensure that if someone else's code on another thread is messing
    // with the class' method list too, we always have a valid -dealloc at all times.
    //
    // If the class does not implement the method itself then
    // class_replaceMethod returns NULL and superclasses's implementation will be used.
    //
    // We need a lock to be sure that originalIMP has the right value in the
    // originalImpProvider block above.
    OSSpinLockLock(&lock);
    originalIMP = class_replaceMethod(object_getClass(classToSwizzle), selector, newIMP, methodType);
    OSSpinLockUnlock(&lock);
}




static NSMutableDictionary *swizzledClassesDictionary() {
    static NSMutableDictionary *swizzledClasses;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzledClasses = [NSMutableDictionary new];
    });
    return swizzledClasses;
}

static NSMutableSet *swizzledClassesForKey(const void *key) {
    NSMutableDictionary *classesDictionary = swizzledClassesDictionary();
    
    NSValue *keyValue = [NSValue valueWithPointer:key];
    
    
    NSMutableSet *swizzledClasses = [classesDictionary objectForKey:keyValue];
    
    if (!swizzledClasses) {
        swizzledClasses = [NSMutableSet new];
        [classesDictionary setObject:swizzledClasses forKey:keyValue];
    }
    
    return swizzledClasses;
}

static BOOL swizzleInstanceMethod(SEL selector, __unsafe_unretained Class classToSwizzle, RSSwizzleImpFactoryBlock factoryBlock, RSSwizzleMode mode, const void *key) {
    NSCAssert(!(key == NULL && mode != RSSwizzleModeAlways), @"Key may not be NULL if mode is not RSSwizzleModeAlways.");

    @synchronized(swizzledClassesDictionary()) {
        if (key) {
            NSSet *swizzledClasses = swizzledClassesForKey(key);
            
            if (mode == RSSwizzleModeOncePerClass) {
                if ([swizzledClasses containsObject:classToSwizzle]) {
                    return NO;
                }
            }
            else if (mode == RSSwizzleModeOncePerClassAndSuperclasses) {
                for (Class currentClass = classToSwizzle; currentClass != nil; currentClass = class_getSuperclass(currentClass)) {
                    if ([swizzledClasses containsObject:currentClass]) {
                        return NO;
                    }
                }
            }
        }
        
        swizzleCore_Instance(classToSwizzle, selector, factoryBlock);
        
        if (key) {
            [swizzledClassesForKey(key) addObject:classToSwizzle];
        }
    }
    
    return YES;
}

static BOOL swizzleClassMethod(SEL selector, __unsafe_unretained Class classToSwizzle, RSSwizzleImpFactoryBlock factoryBlock, RSSwizzleMode mode, const void *key) {
    NSCAssert(!(key == NULL && mode != RSSwizzleModeAlways), @"Key may not be NULL if mode is not RSSwizzleModeAlways.");

    NSCAssert(!(key == NULL && mode != RSSwizzleModeAlways), @"Key may not be NULL if mode is not RSSwizzleModeAlways.");
    
    @synchronized(swizzledClassesDictionary()) {
        if (key) {
            NSSet *swizzledClasses = swizzledClassesForKey(key);
            
            if (mode == RSSwizzleModeOncePerClass) {
                if ([swizzledClasses containsObject:classToSwizzle]) {
                    return NO;
                }
            }
            else if (mode == RSSwizzleModeOncePerClassAndSuperclasses) {
                for (Class currentClass = classToSwizzle; currentClass != nil; currentClass = class_getSuperclass(currentClass)) {
                    if ([swizzledClasses containsObject:currentClass]) {
                        return NO;
                    }
                }
            }
        }
        
        swizzleCore_Class(classToSwizzle, selector, factoryBlock);
        
        if (key) {
            [swizzledClassesForKey(key) addObject:classToSwizzle];
        }
    }
    
    return YES;
}



@implementation NSObject (RSSwizzle)


+ (BOOL)swizzleMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock {
    return [self swizzleMethod:selector usingFactory:factoryBlock mode:RSSwizzleModeAlways key:NULL];
}

+ (BOOL)swizzleMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock mode:(RSSwizzleMode)mode key:(const void *)key {
    return swizzleClassMethod(selector, self, factoryBlock, mode, key);
}


+ (BOOL)swizzleInstanceMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock {
    return [self swizzleInstanceMethod:selector usingFactory:factoryBlock mode:RSSwizzleModeAlways key:NULL];
}

+ (BOOL)swizzleInstanceMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock mode:(RSSwizzleMode)mode key:(const void *)key {
    return swizzleInstanceMethod(selector, self, factoryBlock, mode, key);
}


- (BOOL)swizzleMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock {
    return [self swizzleMethod:selector usingFactory:factoryBlock mode:RSSwizzleModeAlways key:NULL];
}

- (BOOL)swizzleMethod:(SEL)selector usingFactory:(RSSwizzleImpFactoryBlock)factoryBlock mode:(RSSwizzleMode)mode key:(const void *)key {
    return [self.class swizzleInstanceMethod:selector usingFactory:factoryBlock mode:mode key:key];
}

@end

