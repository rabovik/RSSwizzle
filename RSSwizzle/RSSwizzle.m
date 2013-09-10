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

static const char *blockGetType(id block){
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

static BOOL blockIsCompatibleWithMethodType(id block, const char *methodType){
    const char *blockType = blockGetType(block);
    NSMethodSignature *blockSignature =
        [NSMethodSignature signatureWithObjCTypes:blockType];
    NSMethodSignature *methodSignature =
        [NSMethodSignature signatureWithObjCTypes:methodType];
    
    if (!blockSignature || !methodSignature) {
        return NO;
    }
    
    if (blockSignature.numberOfArguments != methodSignature.numberOfArguments){
        return NO;
    }
    
    if (strcmp(blockSignature.methodReturnType, methodSignature.methodReturnType) != 0){
        return NO;
    }
    
    for (int i=0; i<methodSignature.numberOfArguments; ++i){
        if (i == 0){
            // self in method, block in block
            if (strcmp([methodSignature getArgumentTypeAtIndex:i], "@") != 0) {
                return NO;
            }
            if (strcmp([blockSignature getArgumentTypeAtIndex:i], "@?") != 0) {
                return NO;
            }
        }else if(i == 1){
            // SEL in method, self in block
            if (strcmp([methodSignature getArgumentTypeAtIndex:i], ":") != 0) {
                return NO;
            }
            if (strcmp([blockSignature getArgumentTypeAtIndex:i], "@") != 0) {
                return NO;
            }
        }else{
            if (strcmp([methodSignature getArgumentTypeAtIndex:i],
                       [blockSignature getArgumentTypeAtIndex:i]) != 0)
            {
                return NO;
            }
        }
    }
    
    return YES;
}

static BOOL blockIsAnImpFactoryBlock(id block){
    const char *blockType = blockGetType(block);
    RSSwizzleImpFactoryBlock dummyFactory = ^id(RSSWizzleImpProvider originalIMPProvider){
        return nil;
    };
    const char *factoryType = blockGetType(dummyFactory);
    return 0 == strcmp(factoryType, blockType);
}

#endif // NS_BLOCK_ASSERTIONS


#pragma mark - Swizzling

@implementation RSSwizzle

+(void)swizzleInstanceMethod:(SEL)selector
                     inClass:(Class)classToSwizzle
               newImpFactory:(RSSwizzleImpFactoryBlock)factoryBlock
{
    Method method = class_getInstanceMethod(classToSwizzle, selector);
    
    NSAssert(NULL != method,
             @"Selector %@ not found in instance methods of class %@.",
             NSStringFromSelector(selector),
             classToSwizzle);
    
    NSAssert(blockIsAnImpFactoryBlock(factoryBlock),
             @"Wrong type of implementation factory block.");
    
    __block OSSpinLock lock = OS_SPINLOCK_INIT;
    // To keep things thread-safe, we fill in the originalIMP later,
    // with the result of the class_replaceMethod call below.
    __block IMP originalIMP = NULL;

    // This block will be called by the client to get original implementation and call it.
    RSSWizzleImpProvider originalImpProvider = ^IMP{
        // It's possible that another thread can call the method between the call to
        // class_replaceMethod and its return value being set.
        // So to be sure originalIMP has the right value, we need a lock.
        OSSpinLockLock(&lock);
        IMP imp = originalIMP;
        OSSpinLockUnlock(&lock);
        
        if (NULL == imp){
            // If the class does not implement the method
            // we need to find an implementation in one of the superclasses.
            Class superclass = class_getSuperclass(classToSwizzle);
            imp = method_getImplementation(class_getInstanceMethod(superclass,selector));
        }
        return imp;
    };
    
    // We ask the client for the new implementation block.
    // We pass originalImpProvider as an argument to factory block, so the client can
    // call original implementation from the new implementation.
    id newIMPBlock = factoryBlock(originalImpProvider);
    
    const char *methodType = method_getTypeEncoding(method);
    
    NSAssert(blockIsCompatibleWithMethodType(newIMPBlock,methodType),
             @"Block returned from factory is not compatible with method type.");
    
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

@end
